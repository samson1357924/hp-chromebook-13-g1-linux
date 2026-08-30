<!-- markdownlint-disable MD013 -->

# Graphics CDCLK & Display Pipeline Deep-Dive (QHD+ FIFO Underrun)

> **Target Device**: HP Chromebook 13 G1 (Google `chell`, Skylake-Y HD Graphics 515 `[8086:191e]`, rev 07)  
> **Display Panel**: Samsung SDC415A 13.3" QHD+ (3200x1800 @ 60Hz, Pixel Clock 361.310 MHz)  
> **Firmware**: MrChromebox-2606.1 (Coreboot 2026-07-14, UEFI GOP)  
> **Last Verified**: 2026-08-31 on Ubuntu 26.04 LTS (Kernel 7.0.0-30-generic)

---

## 1. Problem Overview & Symptom

When booting Linux with native Intel KMS graphics acceleration (`i915`), the internal display often powers on (backlight active) but outputs **no picture (completely black screen)**.
Meanwhile, all background system services—including SSH, systemd, GDM3, and GNOME Wayland session—operate normally.

When inspecting the kernel log (`dmesg` / `journalctl -k`), the following error appears immediately during display initialization:

```text
i915 0000:00:02.0: [drm] *ERROR* CPU pipe A FIFO underrun
```

---

## 2. Hardware Clock & Display Architecture

### 2.1 Display Timing Requirements

The Samsung SDC415A QHD+ panel native resolution is $3200 \times 1800$ @ 60 Hz.
According to the Detailed Timing Descriptor (DTD) via `i915_display_info`:

* **Active Resolution**: $3200 \times 1800$
* **Total Frame Geometry**: $3316 \times 1816$
* **Pixel Clock (Dot Clock)**: **`361.310 MHz`** (361,310 kHz)
* **eDP Link Configuration**: 4 lanes @ 5.4 Gbps (`port_clock = 540000 kHz`)

### 2.2 Core Display Clock (CDCLK) Constraints on Skylake-Y

On Intel Skylake-Y GT2 (Core m3/m5/m7 6Yxx / HD Graphics 515), the GPU display engine uses the **Core Display Clock (CDCLK)** to feed the display pipe FIFOs from memory.

Supported Skylake CDCLK frequency steps:
* 308.57 MHz
* **337.50 MHz** (Default low-power boot clock)
* **450.00 MHz** (Required minimum for 361.31 MHz Pixel Clock)
* 540.00 MHz
* 617.14 MHz
* 675.00 MHz (Maximum CDCLK)

**Rule of Display Engine**:  
$$\text{CDCLK} \ge \text{Pixel Clock}$$

If $\text{CDCLK} < \text{Pixel Clock}$ ($337.5\text{ MHz} < 361.31\text{ MHz}$), the display hardware pipe FIFO drains faster than the memory controller can fill it, triggering a **CPU pipe FIFO underrun**. The hardware display pipeline locks up, causing a black screen.

---

## 3. The Root Cause: GOP Fastboot Handover Trap

### 3.1 Firmware Initialization
1. MrChromebox UEFI / Coreboot GOP initializes the eDP display at power-on with **`CDCLK = 337.5 MHz`** (standard default for Skylake power envelope).
2. GOP displays the initial boot logo / GRUB menu using basic framebuffers (`simple-framebuffer` / `simpledrm`).

### 3.2 Kernel Fastboot Seamless Takeover
1. When Linux boots and loads `i915`, the driver detects an active display pipeline configured by the GOP firmware.
2. By default, `i915` uses *fastboot* (seamless takeover) to avoid screen flicker during boot.
3. Because fastboot avoids a full CRTC modeset, **`i915` does not recalculate or elevate CDCLK upon initial module load**.
4. Consequently, CDCLK remains at **`337.5 MHz`**.
5. As the display begins driving full $3200 \times 1800$ @ 60Hz ($361.31\text{ MHz}$), the pipe immediately underruns:
   ```text
   [    7.587274] i915 0000:00:02.0: [drm] *ERROR* CPU pipe A FIFO underrun
   [    8.082974] i915 0000:00:02.0: [drm] *ERROR* CPU pipe A FIFO underrun
   ```

---

## 4. Power Management Tuning (`enable_psr=0 enable_fbc=0 enable_dc=0`)

To ensure long-term stability once CDCLK is elevated to 450 MHz, conflicting power-saving features must be disabled in `/etc/modprobe.d/99-hp-chell-power.conf` and `/etc/default/grub`:

```ini
options i915 enable_psr=0 enable_fbc=0 enable_dc=0
```

* **`enable_psr=0` (Panel Self-Refresh)**: Disables PSR1/PSR2. The generic Skylake VBT in MrChromebox does not provide custom panel timing tables for the SDC415A, leading to link synchronization losses during sleep/wake.
* **`enable_fbc=0` (Framebuffer Compression)**: Disables FBC. At $3200 \times 1800$, FBC allocation causes pipe memory contention and FIFO underrun re-arming failures.
* **`enable_dc=0` (Display C-States)**: Disables DC5/DC6 deep sleep display power states, preventing voltage/clock down-stepping below 450 MHz while active.

---

## 5. Live Recovery & Permanent Fix

### 5.1 Real-Time Modeset Trigger (DPMS Cycle)

Because `i915` recalculates CDCLK during an actual CRTC modeset / power-cycle, triggering a brief DPMS off/on cycle forces the driver to reprogram CDCLK to **450.0 MHz**:

**Via Mutter DBus (Wayland Session)**:
```bash
# Find active GDM/greeter session bus
GDM_UID=$(id -u gdm 2>/dev/null || id -u gdm-greeter 2>/dev/null || id -u gdm-greeter-2 2>/dev/null || echo 60579)

# Trigger DPMS cycle (Off -> On)
sudo -u $(id -nu $GDM_UID) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$GDM_UID/bus \
  gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
  --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<3>'

sleep 1

sudo -u $(id -nu $GDM_UID) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$GDM_UID/bus \
  gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
  --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<0>'
```

**Via Virtual Terminal Switch**:
```bash
sudo chvt 2 && sleep 1 && sudo chvt 1
```

### 5.2 Verification

Check debugfs clock status:
```bash
sudo cat /sys/kernel/debug/dri/1/i915_cdclk_info
```

Expected output:
```text
Current CD clock frequency: 450000 kHz
Max CD clock frequency:     675000 kHz
Max pixel clock frequency:  675000 kHz
```

And verify FIFO underrun errors are zero:
```bash
sudo dmesg | grep -iE 'underrun|fifo'
```

### 5.3 Automated Startup Fix

The project provides `scripts/fix-graphics.sh` to automate configuration and ensure CDCLK elevates to 450 MHz on cold boots.
