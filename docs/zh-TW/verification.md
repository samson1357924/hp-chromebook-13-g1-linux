<!-- markdownlint-disable MD013 MD022 MD031 MD032 MD037 MD038 -->

[English](../verification.md) | [繁體中文](verification.md)

# ✅ 實測驗證矩陣 (HP Chromebook 13 G1 - chell)

## 實測環境

| 項目 | 數值 |
| :--- | :--- |
| **裝置** | HP Chromebook 13 G1 (board `chell`, SKU 10467908) |
| **主機板** | `chell` 1.0, MrChromebox 2606.1, m7-6Y75 |
| **作業系統** | Ubuntu 26.04.1 LTS, Wayland, kernel 7.0.0-14-generic |
| **顯示** | simpledrm（nomodeset 陷阱），i915 可用但被阻擋 |
| **音訊** | AVS SSM4567/NAU8825/DMIC, PipeWire 1.6.2 |
| **網路** | 7265 AC, wlp1s0 |
| **EC** | `/dev/cros_ec` + `/dev/cros_pd` 存在，`chell_v1.9.425` |

## 已驗證

* **EC** `/dev/cros_ec` + `/dev/cros_pd` 存在（`cros_ec_lpcs` LPC，mec1322）
* **音訊** 3 卡經 `aplay -l`，wpctl sinks/sources 正常（SSM4567/NAU8825/DMIC）
* **Wi-Fi/BT** iwlwifi/btusb 已綁定並連線
* **顯示** 1920x1080 經 simpledrm（需修 i915 參數 `i915.enable_psr=0 fbc=0 dc=0`）
* **指紋** — 無硬體（N/A，Chell 無感測器）

## 尚未驗證 / 需修復

* **i915 硬體加速** — 被 nomodeset 阻擋，執行 `scripts/fix-graphics.sh` 修復
* **觸控板手勢**、**背光**、**S3 喚醒**、**Type-C DP** 未完整功能測試
* **電池 90% 保護** — `c640-ec-control` + `c640-battery-limit.service` 已實測（`inhibit-charge` 0 mA 旁路 + S3 喚醒鉤子）

詳見 `docs/verification.md` 英文版對照。
