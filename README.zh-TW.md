<!-- markdownlint-disable MD013 MD033 MD041 -->
[English](README.md) | **繁體中文** · 📚 [線上文件 (GitHub Pages)](https://samson1357924.github.io/hp-chromebook-13-g1-linux/zh-TW/) · [English Docs](https://samson1357924.github.io/hp-chromebook-13-g1-linux/)

# HP Chromebook 13 G1 (Google Chell) Linux — 完整硬體啟用

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![REUSE 3.0](https://img.shields.io/badge/REUSE-3.0-green.svg)](https://reuse.software/)
[![平台: Chell / Skylake-Y](https://img.shields.io/badge/平台-Chell%20(Skylake--Y)-orange.svg)](docs/zh-TW/COMPATIBILITY.md)
[![文件: Pages](https://img.shields.io/badge/文件-GitHub%20Pages-blue.svg)](https://samson1357924.github.io/hp-chromebook-13-g1-linux/zh-TW/)

> **一句話簡介** — 為 **HP Chromebook 13 G1**（主機板 `chell` / Baseboard `lars`，Intel 6th Gen Skylake-Y `m7-6Y75 / m5-6Y57 / m3-6Y30`，HD Graphics 515 `[8086:191e]`）提供完整 Linux 支援：一鍵安裝、誠實的已驗證/未驗證硬體矩陣與地雷指南。**主要語言：English（`README.md`）**；本檔為繁體中文對等版本。

---

## ✨ 專案功能

將已刷 MrChromebox UEFI `2606.1` / Coreboot 的 HP Chromebook 13 G1 變為可日常使用的 Linux 筆電：

- **顯示** — 修復 `i915` 黑屏陷阱（`CDCLK 337.5 → 450 MHz`，`FIFO underrun` 近零）`i915.enable_psr=0 fbc=0 dc=0` + `chell-cdclk-fix.service`
- **音訊** — Intel AVS（`snd_soc_avs`）三卡分流：`SSM4567` 喇叭 + `NAU8825` 耳機 + `DMIC`，UCM2 + WirePlumber `50-avs-chell.conf`
- **鍵盤** — ChromeOS EC 頂排透過 `systemd-hwdb` `90-chromebook-keyboard.hwdb`（零開銷）與選用 `keyd` `cros.conf`；背光 `chromeos::kbd_backlight`（max 100）經 `61-chromeos-kbd-backlight.rules`
- **電源與 EC** — TLP `99-hp-chell.conf`、`cros_ec` 電池上限 `85%`（本機）/ `90%`（預設）`c640-battery-limit.service`、風扇 `c640-ec-control`、`[s2idle] deep` 休眠
- **自動化與安全** — `setup.sh --all/--dry-run/--uninstall` 含備份/manifest、`detect-hardware.sh` / `diagnose-audio.sh` / `sysreport.sh`

> **誠實狀態** — `docs/zh-TW/verification.md:3` `最後驗證 2026-08-29` 於 `Ubuntu 26.04.1 / 7.0.0-30 / PipeWire 1.6.2 / Wayland`。見[相容性矩陣](docs/zh-TW/COMPATIBILITY.md)與[實測驗證](docs/zh-TW/verification.md)的 🟢/⚠️/⛔ 證據。

---

## 📊 硬體狀態（精簡）

> 完整矩陣：[docs/zh-TW/COMPATIBILITY.md](docs/zh-TW/COMPATIBILITY.md) · 16 列 · 最後驗證 `2026-08-29` · 見[實測驗證](docs/zh-TW/verification.md)

| 元件 | 狀態 | 驅動 / 方案 | 備註 |
| :--- | :---: | :--- | :--- |
| **顯示 / GPU** | 🟢 已驗證 | `i915` `psr=0 fbc=0 dc=0` | `3200x1800@60 361.31 MHz` CDCLK 450 MHz，FIFO 近零 — [深度解析](docs/zh-TW/deep-dive/i915-graphics-cdclk.md) |
| **喇叭 / 麥克風 / 耳機** | 🟢 正常 | `avs_ssm4567` / `avs_nau8825` / `avs_dmic` | 三 ALSA 卡，PipeWire 正常 — [AVS 深度解析](docs/zh-TW/deep-dive/intel-avs-audio.md) |
| **鍵盤頂排 + 背光** | 🟢 已驗證 | `hwdb` / `keyd` + `cros_ec` | `evtest` 已映射，`chromeos::kbd_backlight` max 100 |
| **電源 / EC / 電池 85%** | 🟢 正常 | `cros_ec` + `c640-battery-limit` | `BATTERY_LIMIT=85` 本機，AC 旁路 |
| **休眠** | ⚠️ 驅動已綁定 | `[s2idle] deep` | `s2idle` 預設，`deep` 可用；上蓋週期待完整驗證 — [實測驗證](docs/zh-TW/verification.md) |
| **Wi-Fi 7265 AC / 藍牙** | ⚠️ 驅動已綁定 | `iwlwifi` / `btusb` | `wlp1s0` 存在、已連線 — 吞吐量測試有限 |
| **觸控板 / 相機 / 儲存** | ⚠️ 驅動已綁定 | `elan_i2c` / `uvcvideo` | 驅動已綁定，手勢未驗證 |
| **指紋辨識** | ⛔ 無硬體 | — | G1 無指紋感測器 |

---

## 🐧 系統需求

- **裝置**：HP Chromebook 13 G1（`chell`，`lars` 家族）— SKU `10467908` 已驗證
- **韌體**：MrChromebox UEFI Full ROM `2606.1`（2026-07-14）— [韌體刷機](docs/zh-TW/FIRMWARE.md)
- **核心**：`>=5.15` 建議 `>=6.5`（`7.0.0-30` 已驗證 `2026-08-29`，`7.0.0-14` 基線可用）
- **發行版**：Ubuntu 26.04 / Debian、Fedora、Arch、openSUSE、NixOS — [發行版指南](docs/zh-TW/distros/ubuntu-debian.md)
- **音訊**：PipeWire `1.6.2` + `snd_soc_avs`（無需 SOF UCM）

---

## 🚀 快速開始

> 首次安裝必須使用 **Ubuntu (safe graphics)** 或 GRUB `nomodeset` — 見[地雷-01](docs/zh-TW/pitfalls/01-safe-graphics-nomodeset.md)。

```bash
git clone https://github.com/samson1357924/hp-chromebook-13-g1-linux.git ~/projects/hp-chromebook-13-g1-linux
cd ~/projects/hp-chromebook-13-g1-linux
chmod +x setup.sh
./setup.sh --all
```

| 需求 | 指令 |
| :--- | :--- |
| 完整安裝（鍵盤 + 音訊 + 電源 + EC + 顯示） | `./setup.sh --all` |
| 僅音訊 | `./setup.sh --audio` 或 `./audio/install-audio.sh` |
| 僅鍵盤 | `./setup.sh --keyboard` |
| 電源與 EC | `./setup.sh --power` / `./setup.sh --ec` |
| 顯示修復（移除 nomodeset） | `./setup.sh --graphics` 或 `./scripts/fix-graphics.sh` |
| 硬體檢測 | `./setup.sh --check` |
| 預覽模式 | `./setup.sh --all --dry-run` |
| 解除安裝與還原 | `./setup.sh --uninstall` |

安裝後：`aplay -l` → `SSM4567 / NAU8825 / DMIC`，`wpctl status` → sinks，`lsmod | grep i915` → 已載入，`cat /sys/kernel/debug/dri/1/i915_display_info | grep CDCLK` → `450000`。

---

## ⚠️ 地雷 — 安裝時黑屏（Chell + i915 + QHD+）

> **現象**：`Try or Install Ubuntu` → 黑屏但 `simpledrm`（`journalctl -k -b -6 -5:1` `FIFO underrun` 6/6 啟動），SSH 存活。**原因**：`Pixel 361.31 > CDCLK 337.5 MHz` + 2015 VBT `PC 14.34` + `PSR/FBC/DC` 衝突 — [根因精簡 → 深度解析](docs/zh-TW/deep-dive/i915-graphics-cdclk.md)。

- **暫時解**（二選一）：`Ubuntu (safe graphics)` **或** GRUB 按 `e` → 在 `quiet splash` 後加 `nomodeset` → `Ctrl+x`
- **修復**：`sudo ./scripts/fix-graphics.sh && sudo reboot`（移除 `nomodeset`、設定 `i915.enable_*=0`、安裝 `chell-cdclk-fix.service` 冷開機 fastboot 防護）。詳見[地雷-01](docs/zh-TW/pitfalls/01-safe-graphics-nomodeset.md) · [iGPU 替代方案](docs/zh-TW/pitfalls/02-igpu-install-alternatives.md) · [顯示深度解析](docs/zh-TW/deep-dive/i915-graphics-cdclk.md)。

---

## 🗂️ 倉庫結構

```text
setup.sh                # 總管 (--all/--audio/--keyboard/--power/--ec/--graphics/--check/--uninstall)
lib/{logger,distro,backup,syscheck}.sh
audio/{install-audio.sh,diagnose-audio.sh,wireplumber/50-avs-chell.conf}
keyboard/{install-keyboard.sh,90-chromebook-keyboard.hwdb,keyd/cros.conf}
power/{install-power.sh,tlp/99-hp-chell.conf,kbd-follow-idle.sh}
ec/{install-ec.sh,systemd/c640-battery-limit.service} + scripts/c640-ec-control.sh
scripts/{fix-graphics.sh,detect-hardware.sh,sysreport.sh}
docs/{QUICKSTART.md,COMPATIBILITY.md,verification.md,TROUBLESHOOTING.md,UNINSTALL.md,pitfalls/*,deep-dive/*,distros/*}
```

---

## 📚 文件導覽

| 分類 | 連結 |
| :--- | :--- |
| **開始使用** | [快速開始](docs/zh-TW/QUICKSTART.md) · [相容性](docs/zh-TW/COMPATIBILITY.md) · [韌體刷機](docs/zh-TW/FIRMWARE.md) |
| **驗證與協助** | [實測驗證矩陣](docs/zh-TW/verification.md) · [疑難排解](docs/zh-TW/TROUBLESHOOTING.md) · [解除安裝](docs/zh-TW/UNINSTALL.md) |
| **地雷** | [安全顯示 / nomodeset](docs/zh-TW/pitfalls/01-safe-graphics-nomodeset.md) · [iGPU 替代方案](docs/zh-TW/pitfalls/02-igpu-install-alternatives.md) |
| **深度解析** | [AVS 音訊](docs/zh-TW/deep-dive/intel-avs-audio.md) · [顯示 CDCLK](docs/zh-TW/deep-dive/i915-graphics-cdclk.md) · [電源與休眠](docs/zh-TW/deep-dive/power-and-suspend.md) |
| **發行版** | [Ubuntu/Debian](docs/zh-TW/distros/ubuntu-debian.md) · [Fedora](docs/zh-TW/distros/fedora.md) · [Arch](docs/zh-TW/distros/arch-linux.md) · [openSUSE](docs/zh-TW/distros/opensuse.md) · [NixOS](docs/zh-TW/distros/nixos.md) |
| **線上** | [GitHub Pages](https://samson1357924.github.io/hp-chromebook-13-g1-linux/zh-TW/) · [English](https://samson1357924.github.io/hp-chromebook-13-g1-linux/) |

---

## 🔧 疑難排解與解除安裝

- **安裝後黑屏** → [地雷-01](docs/zh-TW/pitfalls/01-safe-graphics-nomodeset.md) 或 `journalctl -k | grep -E "FIFO|Atomic"`；GRUB 臨時 `nomodeset` 可恢復
- **無聲音 / Dummy Output** → `./audio/diagnose-audio.sh` + `audio/docs/diagnostics.md` + `audio/docs/root-cause.md`
- **上蓋休眠失效** → `scripts/check-s0ix.sh` + `docs/zh-TW/deep-dive/power-and-suspend.md`
- **還原** → `./setup.sh --uninstall`（manifest + backup）或 `scripts/backup-restore.sh` — [解除安裝](docs/zh-TW/UNINSTALL.md)

---

## 🤝 貢獻

見 [CONTRIBUTING.md](CONTRIBUTING.md) 的 `mkdocs serve`、`markdownlint-cli2`、`lychee`、`reuse lint` 與 PR 流程。請保持 `docs/index.md`（EN）與 `docs/zh-TW/index.md`（ZH）對稱。

---

## 🙏 致謝

感謝 [MrChromebox](https://mrchromebox.tech/) / [Chrultrabook](https://chrultrabook.com/)、[WeirdTreeThing](https://github.com/WeirdTreeThing)、[ChromiumOS EC Team](https://chromium.googlesource.com/chromiumos/platform/ec/) — 見 [CREDITS.md](CREDITS.md)。

---

## 📜 授權與合規

`REUSE 3.0` + SPDX：

| 模組 | 路徑 | 授權 |
| :--- | :--- | :--- |
| 主控與工具 | `setup.sh`、`scripts/`、`lib/`、`power/`、`ec/` | **MIT** |
| 音訊 WirePlumber | `audio/wireplumber/` | **MIT** |
| 鍵盤 hwdb 與文件 | `keyboard/90-*.hwdb`、`docs/` | **CC0-1.0 / MIT** |

見 [LICENSE](LICENSE)、[LICENSES/](LICENSES) 與 [CREDITS.md](CREDITS.md)。

---

*模板參考：[hp-pro-c640-chromebook-linux](https://github.com/samson1357924/hp-pro-c640-chromebook-linux) — 已為 Chell/Skylake-Y 調整。*
