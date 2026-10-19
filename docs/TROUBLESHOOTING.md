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

### 4. No sound — only `Dummy Output` in `wpctl status` (kernel >= 6.16 UCM PCM index mismatch)

* **Check**: `wpctl status` Sinks shows only `Dummy Output` instead of `* Built-in Speakers (SSM4567)`; `pw-dump` shows every AVS card with profiles `{off, pro-audio}` and active `off`; `aplay -D hw:SSM4567,1 ...` fails with ENOENT (message is localized — English text `No such file or directory`) — that is the failure signature; on a working system the device exists (a bare `aplay -D hw:SSM4567,0 ...` returns `EBUSY` while PipeWire's sink holds the PCM, which is expected). Kernel >= 6.16 exposes SSM4567/NAU8825/DMIC as PCM device `0` only; the HDMI card (`avs_hdaudio`) keeps devices `0`-`2` (HDMI1-HDMI3).
* **Root cause**: kernel >= 6.16 renamed the AVS cards (`AVS I2S SSM4567`, `AVS I2S NAU8825`, `AVS DMIC`, `AVS HDMI`) and renumbered the front-end PCMs; the distro UCM still references `hw:${CardId},1` (SSM4567/NAU8825) and `,2` (DMIC), so PipeWire's ACP backend cannot open the PCM, no HiFi profile is built, all cards stay on profile `off`, no hardware sink exists and PipeWire falls back to the silent `Dummy Output` — apps "play" and exit 0. Full chain: [audio/docs/root-cause.md](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/docs/root-cause.md).
  * `alsaucm -c hw:SSM4567 dump text` can exit 0 and print `Verb.HiFi` while the profile still fails — parsing OK is **not** proof the PCM opens.
  * Secondary: HDMI vs speakers priority tie, fixed by `50-avs-chell.conf` (speakers 1500 > HDMI 500; mainly matters when a display with audio is attached).
* **Solution**:

  ```bash
  sudo ./audio/install-audio.sh --install   # conf.d symlinks + ,1/,2 -> ,0 + mixers + WirePlumber
  ./audio/diagnose-audio.sh
  wpctl status                              # expect Built-in Speakers (SSM4567) + Internal Digital Mic (DMIC)
  speaker-test -D plughw:SSM4567,0 -c2 -l1
  ```

  > **After `alsa-ucm-conf` package updates, re-run the installer**: upgrades overwrite the patched UCM HiFi files and the stale `,1`/`,2` indices come back.
  Chell uses Intel AVS (`snd_soc_avs`) and needs no SOF UCM (unlike c640 `sof-rt5682`).

### 4.1 Speaker volume extremely low / silent after login

* **Root cause**: WirePlumber restores its saved node volume on login (observed as low as `0.06`) and writes it to the `DSP Volume` mixer, overriding the installer value; after reinstall/reboot `Left/Right Master` also resets to `15/255 (-65dB)` and `DSP Volume` to `0` — effective mute with switches `[on]`.
* **Check**: `wpctl get-volume @DEFAULT_AUDIO_SINK@` (the diagnose script warns below `0.2`).
* **Solution**: `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5` is the persistent knob; re-run `sudo ./audio/install-audio.sh --install` if the mixer itself was reset (sets `Left/Right Master 191`, `DSP 1500000000`, `alsactl store`).

### 4.2 Internal microphone not working (DMIC)

* **Root cause**: same UCM PCM index mismatch — DMIC capture references `hw:${CardId},2` while kernel >= 6.16 exposes device `0`; the installer rewrites `,2` -> `,0` as well.
* **Check / solution**:

  ```bash
  sudo ./audio/install-audio.sh --install   # also fixes the DMIC CapturePCM index
  wpctl status                              # source: Internal Digital Mic (DMIC)
  arecord -D plughw:DMIC,0 -d2 -f S16_LE -r48000 -c2 /tmp/mic.wav
  aplay -D plughw:SSM4567,0 /tmp/mic.wav    # or inspect the WAV on another device
  ```

  The DMIC NHLT warning `Endpoint format configuration not found` in `dmesg` is harmless.

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
