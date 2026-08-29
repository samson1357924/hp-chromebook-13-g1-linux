<!-- markdownlint-disable MD013 MD022 MD031 MD032 MD037 MD038 -->

[English](../verification.md) | [繁體中文](verification.md)

# ✅ 實測驗證矩陣 (HP Chromebook 13 G1 - chell)

## 實測環境

| 項目 | 數值 |
| :--- | :--- |
| **裝置** | HP Chromebook 13 G1 (board `chell`, SKU 10467908) |
| **主機板** | `chell` 1.0, MrChromebox 2606.1, m7-6Y75 |
| **作業系統** | Ubuntu 26.04.1 LTS, Wayland, kernel 7.0.0-30-generic（2026-08-29）、7.0.0-14-generic（2026-08-15 baseline） |
| **顯示** | `i915` 已啟用（CDCLK 450MHz、FIFO 0），`nomodeset` 已移除（`scripts/fix-graphics.sh`） |
| **音訊** | AVS SSM4567/NAU8825/DMIC, PipeWire 1.6.2 |
| **網路** | 7265 AC, wlp1s0 |
| **EC** | `/dev/cros_ec` + `/dev/cros_pd` 存在，`chell_v1.9.425` |

## 已驗證（2026-08-29）

* **EC** `/dev/cros_ec` + `/dev/cros_pd` 存在（`cros_ec_lpcs` LPC，mec1322）
* **音訊** 3 卡經 `aplay -l`，wpctl sinks/sources 正常（SSM4567/NAU8825/DMIC）
* **Wi-Fi/BT** iwlwifi/btusb 已綁定並連線
* **顯示** `i915` 已綁定（`/sys/class/drm/card1/device/driver -> i915`、`glxinfo` `Mesa HD 515`、`direct rendering: Yes`、`xrandr` `3200x1800@60 361.31MHz`、`i915.enable_psr=0 fbc=0 dc=0`、`journalctl -k` FIFO `0`）
* **鍵盤背光** `/sys/class/leds/chromeos::kbd_backlight`（`cros_kbd_led_backlight`，max 100）— 已實測 `echo 0/100 > brightness` 與 GNOME `org.gnome.SettingsDaemon.Power.Keyboard` `StepUp/StepDown/Toggle`（每級 +5，Toggle 熄滅），`systemd-backlight@leds:chromeos::kbd_backlight.service` active，`c640-ec-control kblight [PCT]` + udev `61-chromeos-kbd-backlight.rules`（`TAG+="uaccess"` + `GROUP plugdev MODE="0660"`）已部署
* **螢幕背光** `/sys/class/backlight/intel_backlight` 存在（max 187）經 `i915`
* **指紋** — 無硬體（N/A，Chell 無感測器）
* **電池 90% 保護** — `c640-ec-control` + `c640-battery-limit.service` 已實測（`inhibit-charge` 0 mA 旁路 + S3 喚醒鉤子）

## 尚未驗證 / 需修復

* **觸控板手勢**、**S3 喚醒**、**Type-C DP** 未完整功能測試（驅動已綁定）

詳見 `docs/verification.md` 英文版對照。
