<!-- markdownlint-disable MD013 MD022 MD031 MD032 MD037 MD038 -->

# 🛠️ Troubleshooting & Pitfall Guide (HP Chromebook 13 G1 - chell)

> **First install**: If the USB installer shows black screen, see [PITFALL-01: Safe Graphics / nomodeset](pitfalls/01-safe-graphics-nomodeset.md) - you must select **Ubuntu (safe graphics)** or add `nomodeset` via GRUB `e`.

## 🖥️ Graphics & Display

### 1. Black screen when selecting "Try or Install Ubuntu" from USB

* **Root cause**: `i915` KMS incompatible with chell's GOP/VBT on kernel 7.0
* **Solution**: Use **Ubuntu (safe graphics)** or edit GRUB `linux` line to append `nomodeset`, then `Ctrl+x` boot. See `docs/pitfalls/01-safe-graphics-nomodeset.md`

### 2. After install still using simpledrm, no i915 (`lsmod | grep i915` empty)

* **Root cause**: Installer left `nomodeset` in `/etc/default/grub` (`quiet splash nomodeset`)
* **Solution**:
  ```bash
  ./scripts/fix-graphics.sh
  # or
  sudo sed -i 's/ *nomodeset//g' /etc/default/grub && sudo update-grub && sudo reboot
  ```

### 3. `xrandr` shows only `None-1` / `simpledrm` / no backlight

* **Solution**: Same as #2 - enable `i915`, then `ls /sys/class/backlight/` should appear.

### 3.1 Black screen on boot with i915 loaded (CDCLK 337.5 MHz FIFO Underrun Trap)

* **Symptom**: `i915` is loaded, display backlight is ON, SSH / GDM3 is fully running, but screen outputs no image (black). `dmesg` reports `[drm] *ERROR* CPU pipe A FIFO underrun`.
* **Root cause**: MrChromebox UEFI GOP starts the display at CDCLK = 337.5 MHz. Linux `i915` fastboot handover inherits the framebuffer without a modeset. Because 3200x1800 requires Pixel Clock 361.31 MHz ($> 337.5\text{ MHz}$), the pipe underruns on cold boot.
* **Solution**:
  ```bash
  # Quick live recovery (triggers DPMS cycle / modeset to bump CDCLK to 450 MHz)
  ./scripts/fix-graphics.sh --cycle-dpms

  # Permanent fix (ensures kernel params + installs startup auto-fix service)
  sudo ./scripts/fix-graphics.sh
  ```
* **Deep-Dive**: See [docs/deep-dive/i915-graphics-cdclk.md](deep-dive/i915-graphics-cdclk.md) for full hardware analysis.

## 🔊 Audio (AVS SSM4567 / NAU8825 / DMIC)

### 4. No sound / Dummy Output

* **Check**: `aplay -l` should show `SSM4567`, `NAU8825`, `DMIC`; `wpctl status` shows sinks
* **Solution**: `systemctl --user restart wireplumber pipewire`; AVS needs no SOF UCM (unlike c640)

### 5. Headset mic not working

* **Solution**: `arecord -l` check `NAU8825` capture; `wpctl status` sources

---

## ⌨️ Keyboard

### 6. Top-row ChromeOS keys not mapped

* **Solution**: `./setup.sh --keyboard` installs `hwdb` 90-cros-keyboard

---

## 🔋 EC / Power

### 7. `/dev/cros_ec` missing

* **Check**: `ls -l /dev/cros_ec` should be `crw-------` (MrChromebox 2606.1 OK)
* **Solution**: Ensure MrChromebox UEFI, not stock ChromeOS firmware

---

## 📌 Other

* **Wi-Fi 7265 not found**: `lspci -k | grep 7265` -> `iwlwifi` should bind, reload `sudo modprobe iwlwifi`
* **More**: See `docs/pitfalls/01-safe-graphics-nomodeset.md`
