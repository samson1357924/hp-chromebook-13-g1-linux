<!-- markdownlint-disable MD013 MD022 MD031 MD032 MD037 MD038 -->

[English](../verification.md) | [繁體中文](verification.md)

# ✅ 實測驗證矩陣 (HP Chromebook 13 G1 - chell)

## 實測環境

| 項目 | 數值 |
| :--- | :--- |
| **裝置** | HP Chromebook 13 G1 (board `chell`, SKU 10467908) |
| **主機板** | `chell` 1.0, MrChromebox 2606.1, m7-6Y75 |
| **作業系統** | Ubuntu 26.04.1 LTS, Wayland, kernel 7.0.0-38-generic（2026-10-19 音訊）、7.0.0-30-generic（2026-08-29）、7.0.0-14-generic（2026-08-15 baseline） |
| **顯示** | `i915` 已啟用（CDCLK 450MHz、FIFO 近零 — 近 3 次啟動 0 次，9 boots 內偶發單次 `FIFO`/`Atomic`），`nomodeset` 已移除（`scripts/fix-graphics.sh`） |
| **音訊** | AVS SSM4567/NAU8825/DMIC, PipeWire 1.6.2 / WirePlumber 0.5.13、alsa-ucm-conf 1.2.15.3-1ubuntu1.7 |
| **網路** | 7265 AC, wlp1s0 |
| **EC** | `/dev/cros_ec` + `/dev/cros_pd` 存在，`chell_v1.9.425` |

## 已驗證（2026-10-19）

* **音訊（喇叭 + 麥克風）** — `audio/install-audio.sh` 修補發行版 UCM 後（因應 kernel >= 6.16 AVS 重新編號的 PCM 索引 `,1`／`,2` -> `,0`）：`wpctl status` sink `* Built-in Speakers (SSM4567)`（vol 0.50）+ source `* Internal Digital Mic (DMIC)`（vol 0.55）；`pw-link -io` 顯示 `avs_ssm4567 ...HiFi__Speaker__sink:playback_FL/FR` 與 `avs_dmic ...HiFi__Mic__source:capture_FL/FR`；`pw-dump` 作用中 profile `HiFi: Speaker: sink` / `HiFi: Mic: source`；`aplay -D hw:SSM4567,1` 報 ENOENT（此 ENOENT 在修復前後都會出現，因為 kernel >= 6.16 只暴露 device 0，不能作為判別；請看 `wpctl status` 與 UCM 的 `hw:\\${CardId},`）；DMIC `pw-record` 錄音非靜音（`max_volume` ≈ -15 dB，2026-10-19 場次；隨環境而異）；喇叭經使用者確認可聽；`aplay -l` 顯示 `AVS I2S SSM4567` / `AVS I2S NAU8825` / `AVS HDMI`（前兩者僅 PCM device `0`；HDMI 保留 device `0`-`2`）與 `arecord -l` 顯示 `AVS DMIC`（PCM device `0`）
* **音訊注意事項** — `alsa-ucm-conf` 套件更新會覆寫已修補的 HiFi 檔並重現 `Dummy Output` 故障；請重跑 `sudo ./audio/install-audio.sh --install`。耳機插拔自動切換尚未重新驗證

## 已驗證（2026-08-29）

* **EC** `/dev/cros_ec` + `/dev/cros_pd` 存在（`cros_ec_lpcs` LPC，mec1322）
* **音訊** 3 卡經 `aplay -l`，wpctl sinks/sources 正常（SSM4567/NAU8825/DMIC）
* **Wi-Fi/BT** iwlwifi/btusb 已綁定並連線
* **顯示** `i915` 已綁定（`/sys/class/drm/card1/device/driver -> i915`、`glxinfo` `Mesa HD 515`、`direct rendering: Yes`、`xrandr` `3200x1800@60 361.31MHz`、`i915.enable_psr=0 fbc=0 dc=0`、`journalctl -k` FIFO 近零 — 近 3 次啟動 0 次，9 boots 內偶發單次 `FIFO`/`Atomic`，不再連發）
* **鍵盤背光** `/sys/class/leds/chromeos::kbd_backlight`（`cros_kbd_led_backlight`，max 100）— 已實測 `echo 0/100 > brightness` 與 GNOME `org.gnome.SettingsDaemon.Power.Keyboard` `StepUp/StepDown/Toggle`（每級 +5，Toggle 熄滅），`systemd-backlight@leds:chromeos::kbd_backlight.service` active，`c640-ec-control kblight [PCT]` + udev `61-chromeos-kbd-backlight.rules`（`TAG+="uaccess"` + `GROUP plugdev MODE="0660"`）已部署
* **螢幕背光** `/sys/class/backlight/intel_backlight` 存在（max 187）經 `i915`
* **指紋** — 無硬體（N/A，Chell 無感測器）
* **電池 85% 保護（預設 90%）** — `c640-ec-control` + `c640-battery-limit.service` 已實測（`inhibit-charge` 0 mA 旁路 + 休眠喚醒鉤子，`BATTERY_LIMIT=85` 本機設定）

## 尚未驗證 / 需修復

* **觸控板手勢**、**休眠喚醒（[s2idle] 預設）**、**Type-C DP** 未完整功能測試（驅動已綁定）

詳見 `docs/verification.md` 英文版對照。
