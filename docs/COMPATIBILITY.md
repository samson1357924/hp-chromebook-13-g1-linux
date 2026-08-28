<!-- markdownlint-disable MD013 MD022 MD031 MD032 MD037 MD038 -->

# 📊 Hardware Compatibility Matrix

Hardware support under Linux for **HP Chromebook 13 G1** (Google **`chell`**, baseboard `lars` family, Intel 6th Gen Skylake-Y):

---

## 💻 Component Status Overview (this unit: chell / m7-6Y75 / HD 515)

| Hardware Component | Chip Model / Spec | Linux Kernel Driver | Support Status | Notes |
| :--- | :--- | :--- | :---: | :--- |
| **CPU** | Intel Core m7-6Y75 (m3-6Y30/m5-6Y57 options) Skylake-Y 4.5W | `intel_pstate` | 🟢 **Working** | 4 threads, 1.2-3.1GHz, `lscpu` OK |
| **GPU / Display** | Intel HD Graphics 515 (GT2, 24EU) [8086:191e] | `i915` | 🟢 **Working (2026-08-29)** | `i915` bound to `card1`, `Mesa HD 515` `direct rendering: Yes`, `3200x1800@60 361.31MHz` CDCLK 450MHz FIFO 0 with `i915.enable_psr=0 fbc=0 dc=0` (via `scripts/fix-graphics.sh`). |
| **Keyboard Backlight** | ChromeOS EC `chromeos::kbd_backlight` max 100 | `cros_kbd_led_backlight` / `leds_cros_ec` + `61-chromeos-kbd-backlight.rules` | 🟢 **Working (2026-08-29)** | `/sys/class/leds/chromeos::kbd_backlight` + GNOME `Power.Keyboard` `StepUp/Down/Toggle` (+5/step) + `c640-ec-control kblight [PCT]` + `systemd-backlight` verified; uaccess/plugdev deployed. |
| **Speakers** | SSM4567 I2S Amp (AVS) | `avs_ssm4567` | 🟢 **Working** | `aplay -l` Card0 SSM4567, PipeWire sink OK |
| **Headset Jack** | Nuvoton NAU8825 (I2C) | `avs_nau8825` | 🟢 **Working** | Card1 NAU8825, headset playback+capture OK |
| **DMIC Array** | Digital Mic | `avs_dmic` | 🟢 **Working** | Card2 DMIC, `arecord -l` OK |
| **Wi-Fi** | Intel 7265 AC [8086:095a] | `iwlwifi` | 🟢 **Working** | `wlp1s0` Wi-Fi 5 AC, connected |
| **Bluetooth** | Intel 7265 BT `8087:0a2a` | `btusb` | 🟢 **Present** | BT device present |
| **Touchpad** | ELAN0000:00 I2C | `elan_i2c` / `i2c_hid` | ⚠️ **Driver bound** | `ELAN0000:00` + `Synopsys DesignWare` I2C OK, gestures not verified |
| **Camera** | Quanta HP Truevision HD `0408:5060` | `uvcvideo` | 🟢 **Present** | `PipeWire` v4l2 nodes 41/48 present |
| **Storage** | eMMC 32GB + HFS256G39 via JMS567 USB | `sdhci` / `xhci` | 🟢 **Working** | SD `9d2b`, external 238GB OK |
| **Keyboard Top-Row** | ChromeOS EC top-row | `cros_ec` + `hwdb`/`keyd` | 🟢 **Working** | `90-chromebook-keyboard.hwdb` + `keyd/cros.conf` mapped, verified via `evtest`. |
| **Display Backlight** | `intel_backlight` max 187 | `i915` | 🟢 **Present** | `/sys/class/backlight/intel_backlight` via `i915` eDP-1 |
| **EC / PD** | ChromeOS EC LPC + PD | `cros_ec` / `cros_pd` | 🟢 **Present** | `/dev/cros_ec` + `/dev/cros_pd` OK |
| **Sleep** | S3 deep | `S3` | 🟢 **Available** | Skylake uses legacy S3, not S0ix |
| **Fingerprint** | — | — | ⛔ **N/A** | G1 has no fingerprint sensor |

---

## 🐧 Kernel & Distro Requirements

* **Kernel**: `>=5.15` recommended `>=6.5` (Ubuntu 26.04 `7.0.0-30` verified 2026-08-29, `7.0.0-14` baseline OK; i915 fixed via `psr=0 fbc=0 dc=0`)
* **Audio**: PipeWire 1.6.2 + AVS driver (`snd_soc_avs`); no SOF UCM needed unlike c640
* **Tested**: Ubuntu 26.04.1 LTS, kernel 7.0.0-30-generic (Wayland, `i915` + `kbd_backlight` verified 2026-08-29), 15Gi RAM
* **Recovery image**: `chell` (via `chromeos-recovery` tool)
