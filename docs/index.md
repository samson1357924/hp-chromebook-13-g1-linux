<!-- SPDX-License-Identifier: MIT -->
<!-- SPDX-FileCopyrightText: 2026 Samson <https://github.com/samson1357924> -->

# HP Chromebook 13 G1 (Chell) Linux

<div class="mdx-hero" markdown>

<div class="mdx-hero__content" markdown>

## Complete Hardware Enablement & Pitfall Guide

Complete Linux support for **HP Chromebook 13 G1** (Board: `chell` / Baseboard: `lars` / Intel 6th Gen Skylake-Y m7-6Y75) — driver patches, cross-distro automation, and honest verified/unverified docs.

[Quick Start :material-rocket-launch:](QUICKSTART.md){ .md-button .md-button--primary }
[Verification :material-shield-check:](verification.md){ .md-button }
[View on GitHub :fontawesome-brands-github:](https://github.com/samson1357924/hp-chromebook-13-g1-linux){ .md-button }

</div>

</div>

---

## 💻 Hardware Specs

| Item | Details |
| :--- | :--- |
| **Model** | [HP Chromebook 13 G1](https://support.hp.com/tw-zh/product/product-specs/hp-chromebook-13-g1/model/10467908) |
| **Board** | Google `chell` (Baseboard: `lars`, Glados family) |
| **CPU** | Intel 6th Gen Skylake-Y m7-6Y75 (1.2GHz / 3.1GHz, HD Graphics 515) |
| **Fingerprint** | None (no hardware) |
| **Audio** | Intel AVS (`snd_soc_avs`) + SSM4567 (Speaker) + NAU8825 (Headphone) + DMIC + HDMI |
| **Firmware** | MrChromebox UEFI Full ROM / Coreboot |

---

## 📊 Hardware Status

> **Honesty first** — 🟢 = verified on HP Chromebook 13 G1 (Ubuntu 26.04 / kernel 7.0.0-30 / 2026-08-29), ⚠️ = driver bound but not fully tested, ❌ = not measured. See [Verification Matrix](verification.md).

| Component | Status | Driver / Solution | Notes |
| :--- | :---: | :--- | :--- |
| **Fingerprint** | ❌ **No hardware** | — | No fingerprint hardware (Chell / Lars has no `18d1:5002` FPMCU) — see [COMPATIBILITY.md](COMPATIBILITY.md). |
| **Speaker & Mic** | 🟢 **Speaker & Mic OK** | Intel AVS + ALSA UCM2 / PipeWire | Speaker (SSM4567), Headphone (NAU8825), DMIC verified. **Headphone jack auto-switch not fully evidenced** — see [verification.md](verification.md). |
| **Wi-Fi 5 & Bluetooth** | ⚠️ **Driver bound** | Intel 7265 (`iwlwifi` / `btusb`) | Driver binds out of box; **WPA3/throughput not measured** (see [verification.md](verification.md)). |
| **Touchscreen & Touchpad** | ⚠️ **Driver bound** | `i2c_hid` / `elan_i2c` | Module present; **gesture/palm rejection not evidenced** (see [verification.md](verification.md)). |
| **Intel Graphics** | 🟢 **Verified (2026-08-29)** | `i915` (`psr=0 fbc=0 dc=0`) | `i915` bound, `Mesa HD 515` `direct rendering: Yes`, FIFO near-zero, CDCLK 450MHz — see [verification.md](verification.md). |
| **Keyboard Backlight & Top Row** | 🟢 **Verified (2026-08-29)** | `cros_ec` + `udev hwdb` / `keyd` | Top row mapped; backlight `/sys/class/leds/chromeos::kbd_backlight` (max 100) verified — see [verification.md](verification.md). |
| **EC Battery & Fan** | 🟢 **Working** | ChromeOS EC LPC (`c640-ec-control` + `c640-battery-limit`, `BATTERY_LIMIT=85` local / 90 default) | 85% limit daemon, AC bypass, suspend hook, fan silent mode. |
| **Suspend** | 🟢 **s2idle lid cycle verified** | ACPI `[s2idle] deep` (s2idle default, deep available, no HW S0ix) | Lid suspend/resume verified 2026-08-18; deep via `mem_sleep_default=deep` — see [verification.md](verification.md). |
| **Dual Type-C** | ⚠️ **Charging OK** | USB-PD + DP 1.2 Alt Mode | PD charging OK; **Type-C display not verified** (see [verification.md](verification.md)). |

!!! note "Last verified"
    **2026-08-29** on Ubuntu 26.04 LTS (kernel `7.0.0-30-generic` / `7.0.0-14` baseline, PipeWire `1.6.2`, MrChromebox `2606.1`). `i915` fixed (FIFO near-zero, CDCLK 450MHz), keyboard backlight verified, EC daemon — see [verification.md](verification.md).

---

## 🚀 Quick Start

### One-line install

```bash
git clone https://github.com/samson1357924/hp-chromebook-13-g1-linux.git ~/projects/hp-chromebook-13-g1-linux
cd ~/projects/hp-chromebook-13-g1-linux
chmod +x setup.sh
./setup.sh --all
```

### Common commands

| Need | Command |
| :--- | :--- |
| **Full install (keyboard + audio + power + EC)** | `./setup.sh --all` |
| **Audio UCM only** | `./setup.sh --audio` (or `./audio/install-audio.sh`) |
| **Keyboard mapping only** | `./setup.sh --keyboard` |
| **System check** | `./setup.sh --check` |
| **Dry-run** | `./setup.sh --all --dry-run` |
| **Uninstall & rollback** | `./setup.sh --uninstall` |

---

## 📚 Docs Map

<div class="grid cards" markdown>

- :material-rocket-launch: **Getting Started**

    ---

    New to this device? Start here.

    [:octicons-arrow-right-24: Quick Start](QUICKSTART.md)
    [:octicons-arrow-right-24: Compatibility](COMPATIBILITY.md)
    [:octicons-arrow-right-24: Firmware](FIRMWARE.md)

- :material-shield-check: **Verification & Help**

    ---

    Honest verified matrix, troubleshooting & rollback.

    [:octicons-arrow-right-24: Verification Matrix](verification.md) — **Read first**
    [:octicons-arrow-right-24: Troubleshooting (15 pitfalls)](TROUBLESHOOTING.md)
    [:octicons-arrow-right-24: Uninstall](UNINSTALL.md)

- :material-microscope: **Deep Dive**

    ---

    Protocol-level analysis for audio, graphics & power.

    [:octicons-arrow-right-24: AVS Audio (Chell)](deep-dive/intel-avs-audio.md)
    [:octicons-arrow-right-24: Graphics CDCLK Fix](deep-dive/i915-graphics-cdclk.md)
    [:octicons-arrow-right-24: Power & Suspend](deep-dive/power-and-suspend.md)

- :material-linux: **Distro Guides**

    ---

    Per-distro steps and packaging notes.

    [:octicons-arrow-right-24: Ubuntu / Debian](distros/ubuntu-debian.md)
    [:octicons-arrow-right-24: Fedora](distros/fedora.md)
    [:octicons-arrow-right-24: Arch Linux](distros/arch-linux.md)
    [:octicons-arrow-right-24: openSUSE](distros/opensuse.md)
    [:octicons-arrow-right-24: NixOS](distros/nixos.md)

</div>

---

## 🙏 Credits

Thanks to **[MrChromebox](https://mrchromebox.tech/) / [Chrultrabook](https://chrultrabook.com/)**, **[WeirdTreeThing](https://github.com/WeirdTreeThing)** and **[ChromiumOS EC Team](https://chromium.googlesource.com/chromiumos/platform/ec/)** — see [CREDITS](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/CREDITS.md).

---

## 📜 License & Compliance

This project follows [REUSE 3.0](https://reuse.software/) and SPDX:

| Module | Path | License |
| :--- | :--- | :--- |
| Orchestrator & tools | `setup.sh`, `scripts/`, `lib/`, `power/`, `ec/` | **MIT** |
| Audio WirePlumber | `audio/wireplumber/` | **MIT** |
| Keyboard hwdb & docs | `keyboard/90-*.hwdb`, `docs/` | **CC0-1.0 / MIT** |

See [LICENSE](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/LICENSE), [LICENSES/](https://github.com/samson1357924/hp-chromebook-13-g1-linux/tree/main/LICENSES) and [CREDITS](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/CREDITS.md).
