# 🚀 Quick Start Guide (HP Chromebook 13 G1 - chell)

This guide walks you through enabling Linux on **HP Chromebook 13 G1 (Google `chell`, Skylake-Y)** in a few minutes.

> **First pitfall**: The Ubuntu installer will only enter the live/install UI via **Ubuntu (safe graphics)** or by pressing `e` in GRUB and appending `nomodeset` to the `linux` line. See [PITFALL-01: nomodeset for installer](pitfalls/01-safe-graphics-nomodeset.md).

## ⚡ One-Liner Setup

```bash
git clone https://github.com/samson1357924/hp-chromebook-13-g1-linux.git ~/projects/hp-chromebook-13-g1-linux
cd ~/projects/hp-chromebook-13-g1-linux
chmod +x setup.sh
./setup.sh --all
```

## 🧭 Common Commands

| Purpose | Command |
| :--- | :--- |
| **Full install (keyboard + audio + power + EC + graphics fix)** | `./setup.sh --all` |
| **Audio diagnostics (AVS SSM4567/NAU8825)** | `./setup.sh --audio` or `./audio/install-audio.sh` |
| **Keyboard top-row mapping** | `./setup.sh --keyboard` |
| **Power & EC (90% battery + S3)** | `./setup.sh --power` / `./setup.sh --ec` |
| **Graphics fix (remove nomodeset)** | `./setup.sh --graphics` or `./scripts/fix-graphics.sh` |
| **Hardware diagnostics** | `./setup.sh --check` |
| **Dry-run preview** | `./setup.sh --all --dry-run` |
| **Uninstall & rollback** | `./setup.sh --uninstall` |

## 📝 After Install

1. **Graphics**: If you installed via safe graphics, run `./scripts/fix-graphics.sh` then `sudo reboot` to enable `i915` acceleration (verify: `lsmod | grep i915`).
2. **Audio**: `aplay -l` should show `SSM4567` + `NAU8825` + `DMIC`; `wpctl status` should list sinks/sources.
3. **Keyboard**: Top-row maps to F1-F10/media via `hwdb`.
