<!-- markdownlint-disable MD013 MD022 MD031 MD032 MD037 -->

[English](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/README.md) | [繁體中文](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/README.zh-TW.md)

# 🚀 快速上手指南 (Quick Start Guide)

本指南將在幾分鐘內引導您在 **HP Chromebook 13 G1** (Google `chell` / `lars`) 上完成所有硬體驅動配置。

---

## ⚡ 一鍵全自動安裝 (One-Liner Setup)

複製並執行以下指令，全自動安裝頂排鍵盤映射、ALSA UCM2 音效配置（AVS）：

```bash
git clone https://github.com/samson1357924/hp-chromebook-13-g1-linux.git ~/projects/hp-chromebook-13-g1-linux
cd ~/projects/hp-chromebook-13-g1-linux
chmod +x setup.sh
./setup.sh --all
```

---

## 🧭 常用指令一覽

| 目的 | 指令 |
| :--- | :--- |
| **一鍵全功能安裝** | `./setup.sh --all` |
| **僅安裝音訊 UCM 配置** | `./setup.sh --audio` 或 `./audio/install-audio.sh` |
| **僅安裝鍵盤頂排映射** | `./setup.sh --keyboard` 或 `./keyboard/install-keyboard.sh` |
| **僅安裝電源管理調校** | `./power/install-power.sh` |
| **啟用電池保護服務（預設 90%，本機 85%）** | `./ec/install-ec.sh --enable-battery-limit 85` |
| **系統硬體綜合診斷** | `./setup.sh --check` 或 `./scripts/detect-hardware.sh` |
| **預覽所有變更 (Dry-Run)** | `./setup.sh --all --dry-run` |
| **一鍵解除安裝與還原** | `./setup.sh --uninstall` |

---

## 🔊 音效即時測試

```bash
# 測試立體聲喇叭輸出
speaker-test -c 2 -t wav

# 查看當前音效設備狀態
wpctl status
```

---

## 🔋 EC 與電池保護測試

```bash
# 查看完整 EC 健康度儀表板（電池、風扇、全板溫度）
c640-ec-control status

# 設定 85% 充電上限保護（預設 90%，具備自動 AC 旁路）
c640-ec-control battery-limit 85

# 打字靜音模式（風扇 0 RPM）
c640-ec-control fan-silent
```

---

## 📖 下一步閱讀

* 遇到任何疑難雜症？請參閱 [疑難排解與避坑 FAQ (TROUBLESHOOTING.md)](TROUBLESHOOTING.md)。
* 想了解 MrChromebox 刷機與硬體寫入保護解除？請參閱 [韌體刷機與還原指南 (FIRMWARE.md)](FIRMWARE.md)。
* 特定發行版 (Fedora/Arch/NixOS)？請參閱 [發行版專屬指南 (distros/)](distros/ubuntu-debian.md)。
