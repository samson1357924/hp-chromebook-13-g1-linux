<!-- markdownlint-disable MD013 MD022 MD031 MD032 MD037 -->

[English](README.md) | [繁體中文](README.zh-TW.md)

# HP Chromebook 13 G1 (Google Chell) Linux 完整硬體啟用指南

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Chromebook Linux](https://img.shields.io/badge/Platform-Chromebook%20Linux-green.svg)](docs/COMPATIBILITY.md)
[![Hardware: Google Chell](https://img.shields.io/badge/Hardware-Google%20Chell%20(Skylake--Y)-orange.svg)](docs/COMPATIBILITY.md)

本專案為 **HP Chromebook 13 G1** (Board `chell`, Skylake-Y) 的 Linux 完整啟用計畫，包含驅動說明、跨發行版自動化腳本與地雷迴避指南。模板參考 [hp-pro-c640-chromebook-linux](https://github.com/samson1357924/hp-pro-c640-chromebook-linux)。

## 💻 規格
* **型號**: [HP Chromebook 13 G1](https://support.hp.com/tw-zh/product/product-specs/hp-chromebook-13-g1/model/10467908)
* **處理器**: m3-6Y30 / m5-6Y57 / **m7-6Y75** (本機 m7-6Y75), HD Graphics 515
* **顯示**: 13.3" 3200×1800 (本機 SDC415A QHD+) — 部分批次為 1920×1080
* **音訊**: Sunrise Point-LP HD Audio + AVS (`SSM4567`/`NAU8825`/`DMIC`)
* **網路**: Intel 7265 Wi-Fi 5 + BT 4.2 | **EC**: `/dev/cros_ec` | **韌體**: MrChromebox `2606.1`

## 📊 硬體狀態
與 `README.md` 表格一致：顯示需移除 `nomodeset` 啟用 `i915`，音訊/ Wi-Fi / EC 正常，無指紋辨識器。

## 🚀 快速開始
```bash
git clone https://github.com/samson1357924/hp-chromebook-13-g1-linux.git ~/projects/hp-chromebook-13-g1-linux
cd ~/projects/hp-chromebook-13-g1-linux
./setup.sh --all
```

詳見 `docs/`。
