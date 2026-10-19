<!-- markdownlint-disable MD013 -->

# ✅ Verification Matrix (HP Chromebook 13 G1 - chell)

## Test Environment

| Item | Value |
| :--- | :--- |
| **Device** | HP Chromebook 13 G1 (board `chell`, SKU 10467908) |
| **Board** | `chell` 1.0, MrChromebox 2606.1, m7-6Y75 |
| **OS** | Ubuntu 26.04.1 LTS, Wayland, kernel 7.0.0-38-generic (2026-10-19 audio), 7.0.0-30-generic (2026-08-29), 7.0.0-14-generic (2026-08-15 baseline) |
| **Graphics** | `i915` active (CDCLK 450MHz, FIFO near-zero — 0 in last 3 boots, occasional single `FIFO`/`Atomic` in 9 boots), `nomodeset` removed via `scripts/fix-graphics.sh` |
| **Audio** | AVS SSM4567/NAU8825/DMIC, PipeWire 1.6.2 / WirePlumber 0.5.13, alsa-ucm-conf 1.2.15.3-1ubuntu1.7 |
| **Network** | 7265 AC, wlp1s0 |
| **EC** | `/dev/cros_ec` + `/dev/cros_pd` present, `chell_v1.9.425` |

## Verified (2026-10-19)

* **Audio (speakers + microphone)** - after `audio/install-audio.sh` patched the distro UCM (PCM indices `,1`/`,2` -> `,0` for the kernel >= 6.16 AVS renumbering): `wpctl status` sink `* Built-in Speakers (SSM4567)` (vol 0.50) + source `* Internal Digital Mic (DMIC)` (vol 0.55); `pw-link -io` shows `avs_ssm4567 ...HiFi__Speaker__sink:playback_FL/FR` and `avs_dmic ...HiFi__Mic__source:capture_FL/FR`; `pw-dump` active profiles `HiFi: Speaker: sink` / `HiFi: Mic: source`; `aplay -D hw:SSM4567,1` fails ENOENT (stale UCM index signature; on a working system the device `0` exists — a bare `aplay -D hw:SSM4567,0` returns EBUSY while PipeWire's sink holds the PCM, which is expected); DMIC `pw-record` capture non-silent (`max_volume` ≈ -15 dB, 2026-10-19 session; ambient-dependent); speakers user-confirmed audible; `aplay -l` shows `AVS I2S SSM4567` / `AVS I2S NAU8825` / `AVS DMIC` (PCM device `0` only) and `AVS HDMI` (devices `0`-`2`, HDMI1-HDMI3)
* **Audio caveat** - `alsa-ucm-conf` package updates overwrite the patched HiFi files and reintroduce the `Dummy Output` failure; re-run `sudo ./audio/install-audio.sh --install`. Headphone-jack auto-switch not fully re-verified

## Verified (2026-08-29)

* **EC** `/dev/cros_ec` + `/dev/cros_pd` present (`cros_ec_lpcs` mec1322)
* **Audio** 3 cards via `aplay -l`, wpctl sinks/sources OK
* **Wi-Fi/BT** iwlwifi/btusb bound, connected
* **Display** `i915` driver bound (`/sys/class/drm/card1/device/driver -> i915`, `glxinfo` `Mesa HD 515`, `direct rendering: Yes`, `xrandr` `3200x1800@60 361.31MHz`, `i915.enable_psr=0 fbc=0 dc=0`, `journalctl -k` FIFO near-zero — 0 in last 3 boots, occasional single `FIFO`/`Atomic` in 9 boots, no longer continuous black-screen)
* **Keyboard backlight** `/sys/class/leds/chromeos::kbd_backlight` (`cros_kbd_led_backlight`, max 100) — sysfs `echo 0/100 > brightness` and GNOME `org.gnome.SettingsDaemon.Power.Keyboard` `StepUp/StepDown/Toggle` both verified; `systemd-backlight@leds:chromeos::kbd_backlight.service` active and `c640-ec-control kblight [PCT]` + udev `61-chromeos-kbd-backlight.rules` (`TAG+="uaccess"` + `GROUP plugdev MODE="0660"`) deployed
* **Backlight (display)** `/sys/class/backlight/intel_backlight` present (max 187) via `i915`
* **Fingerprint** - N/A (no hardware)
* **Battery 85% protection (90% default)** — `c640-ec-control` + `c640-battery-limit.service` verified (`inhibit-charge` 0 mA bypass + suspend wake hook, `BATTERY_LIMIT=85` on this machine)

## Untested / Needs Fix

* **Touchpad gestures**, **suspend resume ([s2idle] default)**, **Type-C DP** (driver bound, functional test pending)
* **Fingerprint** - N/A (no hardware)

See VERIFICATION for evidence vs claims.
