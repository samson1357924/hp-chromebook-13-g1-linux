[English](README.md) | [繁體中文](README.zh-TW.md)

# HP Chromebook 13 G1 (Google Chell) Linux: Complete Hardware Enablement & Pitfall Guide

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Chromebook Linux](https://img.shields.io/badge/Platform-Chromebook%20Linux-green.svg)](docs/COMPATIBILITY.md)
[![Hardware: Google Chell / Skylake](https://img.shields.io/badge/Hardware-Google%20Chell%20(Skylake--Y)-orange.svg)](docs/COMPATIBILITY.md)
[![Board: chell](https://img.shields.io/badge/Board-chell-blue.svg)](docs/COMPATIBILITY.md)

This project provides a complete Linux hardware enablement plan for the **HP Chromebook 13 G1** (Google Board: **`chell`** / Baseboard: `lars` / Intel 6th Gen Skylake-Y), including driver notes, cross-distribution automated scripts, and a pitfall-avoidance guide. Reference template: [hp-pro-c640-chromebook-linux](https://github.com/samson1357924/hp-pro-c640-chromebook-linux).

---

## 💻 Device Specifications

* **Model**: [HP Chromebook 13 G1](https://support.hp.com/tw-zh/product/product-specs/hp-chromebook-13-g1/model/10467908) (HP `10467908`)
* **Board Codename**: Google `chell` (Baseboard: `lars` family, Skylake)
* **Processor**: Intel Core m3-6Y30 / m5-6Y57 / **m7-6Y75** (this unit: `m7-6Y75 @ 1.20GHz, 4 threads`, Skylake-Y 4.5W, HD Graphics 515 [8086:191e])
* **Graphics**: Intel HD Graphics 515 (GT2, 24EU, 300-1000MHz) - `i915` / `xe` (Skylake)
* **Memory**: 4GB / 8GB / 16GB LPDDR3 (this unit: 15Gi detected) | **Storage**: 32GB eMMC + external via JMS567 (this unit: 238GB HFS256G39TND via USB)
* **Display**: 13.3" 16:9 3200×1800 QHD **or** 1920×1080 FHD IPS, glossy (this unit: 1920×1080@59.96 via `simpledrm`/`i915`)
* **Audio**: Intel Sunrise Point-LP HD Audio [8086:9d70] + AVS driver (`avs_ssm4567` Speakers, `avs_nau8825` Headset, `avs_dmic` DMIC) - PipeWire 1.6.2
* **Network**: Intel Wireless 7265 [8086:095a] (Wi-Fi 5 802.11ac + Bluetooth 4.2 `8087:0a2a`)
* **Camera**: HP Truevision HD 720p `0408:5060` | **Input**: ELAN I2C touchpad `ELAN0000:00`, ChromeOS EC keyboard
* **EC**: ChromeOS EC (`/dev/cros_ec`, `/dev/cros_pd`) | **Firmware**: MrChromebox UEFI Full ROM `MrChromebox-2606.1` | **Battery**: 45Wh 3950mAh, USB-C PD
* **Test Platform**: Ubuntu 26.04.1 LTS, kernel `7.0.0-14-generic`, Wayland, PipeWire

---

## 📊 Hardware Status (this unit: ubuntu-13g1, chell, m7-6Y75)

| Hardware Component | Status | Driver / Solution | Notes |
| :--- | :---: | :--- | :--- |
| **Intel HD 515 Display** | ⚠️ **Needs fix** | `i915` (kernel) + `simpledrm` fallback | Currently booted with `nomodeset` (safe graphics remnant) -> `simple-framebuffer` only, `lsmod` no `i915`. Fix: remove `nomodeset` in `/etc/default/grub` then `i915` accelerates. See TROUBLESHOOTING. |
| **Audio Speakers/Mic/Headset** | 🟢 **Working** | `avs_ssm4567` / `avs_nau8825` / `avs_dmic` + PipeWire | `aplay -l` shows SSM4567 Speakers, NAU8825 Headset, DMIC. `wpctl status` sinks/sources OK. UCM not needed like c640's SOF. |
| **Wi-Fi & Bluetooth** | 🟢 **Working** | `iwlwifi` / `btusb` + `iwl7265` | `wlp1s0` connected `B1721_wifi6`, `tailscale0` OK. BT `8087:0a2a` present. |
| **Touchpad / Touchscreen** | ⚠️ **Driver bound** | `elan_i2c` / `i2c_hid` `Synopsys DesignWare` | `ELAN0000:00` detected, `INT343B` present. Gestures not yet verified. |
| **Keyboard Top-Row** | ⚠️ **Top-row verified** | `cros_ec` + `hwdb`/`keyd` | ChromeOS top-row (search/brightness/volume) via EC, needs `hwdb` mapping same as c640. |
| **ChromeOS EC / Battery / Fan** | 🟢 **EC present** | `cros_ec` LPC (`/dev/cros_ec`) | Direct EC access OK. Battery 90% bypass daemon from c640 EC module portable. |
| **Sleep/Resume S3** | 🟢 **S3 available** | ACPI `deep` (kernel 7.0) | Real S3 lid cycle to be verified. Chell traditionally uses S3, not S0ix. |
| **USB-C PD / Charging** | ⚠️ **Charging OK** | `cros_pd` `/dev/cros_pd` | PD device present, 45W charging, alt-mode display not yet tested. |
| **Fingerprint** | ⛔ **N/A** | — | HP 13 G1 has no fingerprint sensor (unlike c640). Module removed. |
| **SD Reader** | 🟢 **Working** | `sdhci` `9d2b` + JMS567 | microSD via `00:1e.4`, external SSD via `152d:0562` OK. |

> Detailed `COMPATIBILITY.md` lists Skylake vs Comet Lake differences. `VERIFICATION.md` marks tested vs untested on this physical `chell/m7-6Y75` unit.

---

## 🚀 Quick Start

### 1. One-Click Automated Setup

```bash
git clone https://github.com/samson1357924/hp-chromebook-13-g1-linux.git ~/projects/hp-chromebook-13-g1-linux
cd ~/projects/hp-chromebook-13-g1-linux
chmod +x setup.sh
./setup.sh --all        # keyboard + audio + power + ec + check
```

### 2. Common Commands

| Requirement | Command |
| :--- | :--- |
| **Full Setup (keyboard + audio + power + EC)** | `./setup.sh --all` |
| **Audio check/fix (AVS SSM4567/NAU8825)** | `./setup.sh --audio` (or `./audio/install-audio.sh`) |
| **Keyboard top-row mapping only** | `./setup.sh --keyboard` |
| **Power & EC battery limit** | `./setup.sh --power` / `./setup.sh --ec` |
| **Graphics fix (remove nomodeset, enable i915)** | `./scripts/fix-graphics.sh` |
| **Hardware diagnostics** | `./setup.sh --check` (or `./scripts/detect-hardware.sh`) |
| **Dry-run preview** | `./setup.sh --all --dry-run` |
| **Uninstall & restore** | `./setup.sh --uninstall` |

---

## 📚 Documentation

* ✅ **[VERIFICATION.md](docs/verification.md)**: Tested vs untested on real `chell/m7-6Y75`
* 🚀 **[QUICKSTART.md](docs/QUICKSTART.md)**: Getting started flow
* 📊 **[COMPATIBILITY.md](docs/COMPATIBILITY.md)**: Skylake chell chip specs & kernel reqs
* 🔧 **[FIRMWARE.md](docs/FIRMWARE.md)**: MrChromebox UEFI flashing, Cr50 WP, ChromeOS restore (recovery image `chell`)
* 🛠️ **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**: `nomodeset` trap, AVS vs SOF, backlight, S3
* 🔄 **[UNINSTALL.md](docs/UNINSTALL.md)**: Backup/restore

### Deep Dive (ported from c640)

* 🔊 **AVS Audio vs SOF**: Chell uses `snd_soc_avs` (SSM4567/NAU8825) not SOF; PipeWire routing differences
* 🔋 **Power & Suspend**: S3 `deep` on Skylake vs S0ix on Comet Lake

### Distro Guides

* Ubuntu/Debian, Fedora, Arch, openSUSE, NixOS (see `docs/distros/`)

---

## 🧩 Modules

### 🔊 Audio (`audio/`)

Chell's Skylake AVS topology differs from c640's SOF: 3 cards (`SSM4567` speaker, `NAU8825` headset, `DMIC`). No UCM `sof-rt5682` needed; PipeWire handles AVS. Diagnose via `diagnose-audio.sh` ported from c640 but adapted.

### ⌨️ Keyboard (`keyboard/`)

Same `cros_ec` + `systemd-hwdb` as c640: `90-cros-keyboard.hwdb` maps Search->Super, top-row to F1-F10/media. Optional `keyd` dual-mode.

### 🔋 EC & Power (`ec/`, `power/`)

Reuses `c640-ec-control` logic: `/dev/cros_ec` 90% limit daemon, `cros_pd` PD monitor. Skylake S3 suspend, not S0ix.

---

## 🙏 Credits

Template and scripts derived from [hp-pro-c640-chromebook-linux](https://github.com/samson1357924/hp-pro-c640-chromebook-linux) (MIT). Thanks to MrChromebox/Chrultrabook, WeirdTreeThing (UCM), Chromium EC team. See `CREDITS.md`.

## 📜 License

REUSE 3.0 / SPDX: Master scripts `MIT`, audio UCM `BSD-3-Clause`, docs `CC0-1.0`. See `LICENSES/`.
