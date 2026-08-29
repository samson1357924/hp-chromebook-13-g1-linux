<!-- markdownlint-disable MD013 -->

# ✅ Verification Matrix (HP Chromebook 13 G1 - chell)

## Test Environment

| Item | Value |
| :--- | :--- |
| **Device** | HP Chromebook 13 G1 (board `chell`, SKU 10467908) |
| **Board** | `chell` 1.0, MrChromebox 2606.1, m7-6Y75 |
| **OS** | Ubuntu 26.04.1 LTS, Wayland, kernel 7.0.0-30-generic (2026-08-29), 7.0.0-14-generic (2026-08-15 baseline) |
| **Graphics** | `i915` active (CDCLK 450MHz, FIFO 0), `nomodeset` removed via `scripts/fix-graphics.sh` |
| **Audio** | AVS SSM4567/NAU8825/DMIC, PipeWire 1.6.2 |
| **Network** | 7265 AC, wlp1s0 |
| **EC** | `/dev/cros_ec` + `/dev/cros_pd` present, `chell_v1.9.425` |

## Verified (2026-08-29)

* **EC** `/dev/cros_ec` + `/dev/cros_pd` present (`cros_ec_lpcs` mec1322)
* **Audio** 3 cards via `aplay -l`, wpctl sinks/sources OK
* **Wi-Fi/BT** iwlwifi/btusb bound, connected
* **Display** `i915` driver bound (`/sys/class/drm/card1/device/driver -> i915`, `glxinfo` `Mesa HD 515`, `direct rendering: Yes`, `xrandr` `3200x1800@60 361.31MHz`, `i915.enable_psr=0 fbc=0 dc=0`, `journalctl -k` FIFO underrun `0`)
* **Keyboard backlight** `/sys/class/leds/chromeos::kbd_backlight` (`cros_kbd_led_backlight`, max 100) — sysfs `echo 0/100 > brightness` and GNOME `org.gnome.SettingsDaemon.Power.Keyboard` `StepUp/StepDown/Toggle` both verified; `systemd-backlight@leds:chromeos::kbd_backlight.service` active and `c640-ec-control kblight [PCT]` + udev `61-chromeos-kbd-backlight.rules` (`TAG+="uaccess"` + `GROUP plugdev MODE="0660"`) deployed
* **Backlight (display)** `/sys/class/backlight/intel_backlight` present (max 187) via `i915`
* **Fingerprint** - N/A (no hardware)
* **Battery 90% protection** — `c640-ec-control` + `c640-battery-limit.service` verified (`inhibit-charge` 0 mA bypass + S3 wake hook)

## Untested / Needs Fix

* **Touchpad gestures**, **S3 resume**, **Type-C DP** (driver bound, functional test pending)
* **Fingerprint** - N/A (no hardware)

See VERIFICATION for evidence vs claims.
