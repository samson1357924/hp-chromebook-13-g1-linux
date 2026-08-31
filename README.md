<!-- markdownlint-disable MD013 MD033 MD041 -->
**English** | [繁體中文](README.zh-TW.md) · 📚 [Docs (GitHub Pages)](https://samson1357924.github.io/hp-chromebook-13-g1-linux/) · [繁體中文文件](https://samson1357924.github.io/hp-chromebook-13-g1-linux/zh-TW/)

# HP Chromebook 13 G1 (Google Chell) Linux — Complete Hardware Enablement

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![REUSE 3.0](https://img.shields.io/badge/REUSE-3.0-green.svg)](https://reuse.software/)
[![Platform: Chell / Skylake-Y](https://img.shields.io/badge/Platform-Chell%20(Skylake--Y)-orange.svg)](docs/COMPATIBILITY.md)
[![Docs: Pages](https://img.shields.io/badge/Docs-GitHub%20Pages-blue.svg)](https://samson1357924.github.io/hp-chromebook-13-g1-linux/)

> **TL;DR** — Complete Linux support for **HP Chromebook 13 G1** (Board `chell` / Baseboard `lars`, Intel 6th Gen Skylake-Y `m7-6Y75 / m5-6Y57 / m3-6Y30`, HD Graphics 515 `[8086:191e]`) — one-line setup, honest verified/unverified hardware matrix, and pitfall guides. **Primary language: English**; Traditional Chinese available in `README.zh-TW.md` and `docs/zh-TW/`.

---

## ✨ What This Repo Does

Turn a stock HP Chromebook 13 G1 (MrChromebox UEFI `2606.1` / Coreboot) into a daily-driver Linux laptop:

- **Display** — fixes the `i915` black-screen trap (`CDCLK 337.5 → 450 MHz`, `FIFO underrun` → near-zero) with `i915.enable_psr=0 fbc=0 dc=0` + `chell-cdclk-fix.service`
- **Audio** — Intel AVS (`snd_soc_avs`) 3-card split: `SSM4567` speaker + `NAU8825` headset + `DMIC`, UCM2 + WirePlumber `50-avs-chell.conf`
- **Keyboard** — ChromeOS EC top-row via `systemd-hwdb` `90-chromebook-keyboard.hwdb` (zero overhead) + optional `keyd` `cros.conf`; backlight `chromeos::kbd_backlight` (max 100) via `61-chromeos-kbd-backlight.rules`
- **Power & EC** — TLP `99-hp-chell.conf`, `cros_ec` battery limit `85%` (local) / `90%` (default) via `c640-battery-limit.service`, fan control `c640-ec-control`, `[s2idle] deep` suspend
- **Automation & Safety** — `setup.sh --all/--dry-run/--uninstall` with backup/manifest, `detect-hardware.sh` / `diagnose-audio.sh` / `sysreport.sh`

> **Honest status** — `verification.md:3` `Last verified 2026-08-29` on `Ubuntu 26.04.1 / 7.0.0-30 / PipeWire 1.6.2 / Wayland`. See [Compatibility Matrix](docs/COMPATIBILITY.md) and [Verification](docs/verification.md) for 🟢/⚠️/⛔ per-component evidence.

---

## 📊 Hardware Status (condensed)

> Full matrix: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) · 16 rows · Last verified `2026-08-29` · See [Verification](docs/verification.md) for evidence

| Component | Status | Driver / Solution | Notes |
| :--- | :---: | :--- | :--- |
| **Display / GPU** | 🟢 Verified | `i915` `psr=0 fbc=0 dc=0` | `3200x1800@60 361.31 MHz` CDCLK 450 MHz, FIFO near-zero — [Deep Dive](docs/deep-dive/i915-graphics-cdclk.md) |
| **Speakers / Mic / Headset** | 🟢 Working | `avs_ssm4567` / `avs_nau8825` / `avs_dmic` | 3 ALSA cards, PipeWire sinks — [AVS Deep Dive](docs/deep-dive/intel-avs-audio.md) |
| **Keyboard top-row + backlight** | 🟢 Verified | `hwdb` / `keyd` + `cros_ec` | `evtest` mapped, `chromeos::kbd_backlight` max 100 |
| **Power / EC / Battery 85%** | 🟢 Working | `cros_ec` + `c640-battery-limit` | `BATTERY_LIMIT=85` local, AC bypass |
| **Sleep** | ⚠️ Driver bound | `[s2idle] deep` | `s2idle` default, `deep` available; lid cycle pending full verification — [Verification](docs/verification.md) |
| **Wi-Fi 7265 AC / BT** | ⚠️ Driver bound | `iwlwifi` / `btusb` | `wlp1s0` present, connected — limited throughput test |
| **Touchpad / Camera / Storage** | ⚠️ Bound | `elan_i2c` / `uvcvideo` | Driver bound, gestures not verified |
| **Fingerprint** | ⛔ N/A | — | G1 has no sensor |

---

## 🐧 Requirements

- **Device**: HP Chromebook 13 G1 (`chell`, `lars` family) — SKU `10467908` verified
- **Firmware**: MrChromebox UEFI Full ROM `2606.1` (2026-07-14) — [FIRMWARE](docs/FIRMWARE.md)
- **Kernel**: `>=5.15` recommended `>=6.5` (`7.0.0-30` verified `2026-08-29`, `7.0.0-14` baseline OK)
- **Distros**: Ubuntu 26.04 / Debian, Fedora, Arch, openSUSE, NixOS — [Distros](docs/distros/ubuntu-debian.md)
- **Audio**: PipeWire `1.6.2` + `snd_soc_avs` (no SOF UCM)

---

## 🚀 Quick Start

> First install must use **Ubuntu (safe graphics)** or GRUB `nomodeset` — see [Pitfall-01](docs/pitfalls/01-safe-graphics-nomodeset.md).

```bash
git clone https://github.com/samson1357924/hp-chromebook-13-g1-linux.git ~/projects/hp-chromebook-13-g1-linux
cd ~/projects/hp-chromebook-13-g1-linux
chmod +x setup.sh
./setup.sh --all
```

| Need | Command |
| :--- | :--- |
| Full install (keyboard + audio + power + EC + graphics) | `./setup.sh --all` |
| Audio only | `./setup.sh --audio` or `./audio/install-audio.sh` |
| Keyboard only | `./setup.sh --keyboard` |
| Power & EC | `./setup.sh --power` / `./setup.sh --ec` |
| Graphics fix (remove nomodeset) | `./setup.sh --graphics` or `./scripts/fix-graphics.sh` |
| Check hardware | `./setup.sh --check` |
| Dry-run preview | `./setup.sh --all --dry-run` |
| Uninstall & rollback | `./setup.sh --uninstall` |

After install: `aplay -l` → `SSM4567 / NAU8825 / DMIC`, `wpctl status` → sinks, `lsmod | grep i915` → bound, `cat /sys/kernel/debug/dri/1/i915_display_info | grep CDCLK` → `450000`.

---

## ⚠️ Pitfall — Installer Black Screen (Chell + i915 + QHD+)

> **Symptom**: `Try or Install Ubuntu` → black screen with `simpledrm` (`journalctl -k -b -6 -5:1` `FIFO underrun` 6/6 boots), SSH alive. **Cause**: `Pixel 361.31 > CDCLK 337.5 MHz` + 2015 VBT `PC 14.34` + `PSR/FBC/DC` contention — [Root Cause (5 lines → Deep Dive)](docs/deep-dive/i915-graphics-cdclk.md).

- **Workaround** (choose one): `Ubuntu (safe graphics)` **or** GRUB `e` → add `nomodeset` after `quiet splash` → `Ctrl+x`
- **Fix**: `sudo ./scripts/fix-graphics.sh && sudo reboot` (removes `nomodeset`, sets `i915.enable_*=0`, installs `chell-cdclk-fix.service` for cold-boot fastboot). Details: [PITFALL-01](docs/pitfalls/01-safe-graphics-nomodeset.md) · [iGPU Alternatives](docs/pitfalls/02-igpu-install-alternatives.md) · [Graphics Deep Dive](docs/deep-dive/i915-graphics-cdclk.md).

---

## 🗂️ Repo Layout

```text
setup.sh                # orchestrator (--all/--audio/--keyboard/--power/--ec/--graphics/--check/--uninstall)
lib/{logger,distro,backup,syscheck}.sh
audio/{install-audio.sh,diagnose-audio.sh,wireplumber/50-avs-chell.conf}
keyboard/{install-keyboard.sh,90-chromebook-keyboard.hwdb,keyd/cros.conf}
power/{install-power.sh,tlp/99-hp-chell.conf,kbd-follow-idle.sh}
ec/{install-ec.sh,systemd/c640-battery-limit.service} + scripts/c640-ec-control.sh
scripts/{fix-graphics.sh,detect-hardware.sh,sysreport.sh}
docs/{QUICKSTART.md,COMPATIBILITY.md,verification.md,TROUBLESHOOTING.md,UNINSTALL.md,pitfalls/*,deep-dive/*,distros/*}
```

---

## 📚 Documentation

| Section | Links |
| :--- | :--- |
| **Getting Started** | [Quick Start](docs/QUICKSTART.md) · [Compatibility](docs/COMPATIBILITY.md) · [Firmware](docs/FIRMWARE.md) |
| **Verification & Help** | [Verification Matrix](docs/verification.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) · [Uninstall](docs/UNINSTALL.md) |
| **Pitfalls** | [Safe Graphics / nomodeset](docs/pitfalls/01-safe-graphics-nomodeset.md) · [iGPU Alternatives](docs/pitfalls/02-igpu-install-alternatives.md) |
| **Deep Dive** | [AVS Audio](docs/deep-dive/intel-avs-audio.md) · [Graphics CDCLK](docs/deep-dive/i915-graphics-cdclk.md) · [Power & Suspend](docs/deep-dive/power-and-suspend.md) |
| **Distros** | [Ubuntu/Debian](docs/distros/ubuntu-debian.md) · [Fedora](docs/distros/fedora.md) · [Arch](docs/distros/arch-linux.md) · [openSUSE](docs/distros/opensuse.md) · [NixOS](docs/distros/nixos.md) |
| **Online** | [GitHub Pages](https://samson1357924.github.io/hp-chromebook-13-g1-linux/) · [繁體中文](https://samson1357924.github.io/hp-chromebook-13-g1-linux/zh-TW/) |

---

## 🔧 Troubleshooting & Uninstall

- **Black screen after install** → [PITFALL-01](docs/pitfalls/01-safe-graphics-nomodeset.md) or `journalctl -k | grep -E "FIFO|Atomic"`; temporary GRUB `nomodeset` recovers.
- **No sound / Dummy Output** → `./audio/diagnose-audio.sh` + `audio/docs/diagnostics.md` + `audio/docs/root-cause.md`
- **Lid suspend fails** → `scripts/check-s0ix.sh` + `docs/deep-dive/power-and-suspend.md`
- **Rollback** → `./setup.sh --uninstall` (manifest + backup) or `scripts/backup-restore.sh` — [UNINSTALL](docs/UNINSTALL.md)

---

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for `mkdocs serve`, `markdownlint-cli2`, `lychee`, `reuse lint`, and PR flow. Keep `docs/index.md` (EN) and `docs/zh-TW/index.md` (ZH) symmetric.

---

## 🙏 Credits

Thanks to [MrChromebox](https://mrchromebox.tech/) / [Chrultrabook](https://chrultrabook.com/), [WeirdTreeThing](https://github.com/WeirdTreeThing), [ChromiumOS EC Team](https://chromium.googlesource.com/chromiumos/platform/ec/) — see [CREDITS.md](CREDITS.md).

---

## 📜 License & Compliance

`REUSE 3.0` + SPDX:

| Module | Path | License |
| :--- | :--- | :--- |
| Orchestrator & tools | `setup.sh`, `scripts/`, `lib/`, `power/`, `ec/` | **MIT** |
| Audio WirePlumber | `audio/wireplumber/` | **MIT** |
| Keyboard hwdb & docs | `keyboard/90-*.hwdb`, `docs/` | **CC0-1.0 / MIT** |

See [LICENSE](LICENSE), [LICENSES/](LICENSES) and [CREDITS.md](CREDITS.md).

---

*Template reference: [hp-pro-c640-chromebook-linux](https://github.com/samson1357924/hp-pro-c640-chromebook-linux) — adapted for Chell/Skylake-Y.*
