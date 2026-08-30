<!-- markdownlint-disable MD013 MD022 MD031 MD032 MD037 MD038 -->

[English](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/README.md) | [繁體中文](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/README.zh-TW.md)

# 📊 硬體相容性矩陣 (Hardware Compatibility Matrix)

**HP Chromebook 13 G1**（開發代號：**Google `chell`**，Baseboard：**`lars` family**，Intel 第 6 代 Skylake-Y）在 Linux 下的硬體組件支援狀況如下：

---

## 💻 組件狀態總覽（本機：chell / m7-6Y75 / HD 515）

| 硬體組件 | 晶片型號 / 規格 | Linux 核心驅動 | 支援狀態 | 備註 / 解決方案 |
| :--- | :--- | :--- | :---: | :--- |
| **處理器** | Intel Core m7-6Y75（另有 m3-6Y30/m5-6Y57）Skylake-Y 4.5W | `intel_pstate` | 🟢 **正常** | 4 threads, 1.2-3.1GHz, `lscpu` 已驗證 |
| **GPU / 顯示** | Intel HD Graphics 515 (GT2, 24EU) [8086:191e] | `i915` | 🟢 **正常 (2026-08-29)** | `i915` 綁定 `card1`，`Mesa HD 515` `direct rendering: Yes`，`3200x1800@60 361.31MHz` CDCLK 450MHz FIFO 近零，`i915.enable_psr=0 fbc=0 dc=0`（經 `scripts/fix-graphics.sh`；近 3 次啟動 0 次，9 boots 內偶發單次不再連發）。DRM 物理 3200x1800，`xrandr` 3840x2160 為 XWayland 縮放。 |
| **鍵盤背光** | ChromeOS EC `chromeos::kbd_backlight` max 100 | `cros_kbd_led_backlight` / `leds_cros_ec` + `61-chromeos-kbd-backlight.rules` | 🟢 **正常 (2026-08-29)** | `/sys/class/leds/chromeos::kbd_backlight` + GNOME `Power.Keyboard` `StepUp/Down/Toggle`（+5/級）+ `c640-ec-control kblight [PCT]` + `systemd-backlight` 已驗證；uaccess/plugdev 已部署。 |
| **立體聲喇叭** | SSM4567 I2S Amp (AVS) | `avs_ssm4567` | 🟢 **正常** | `aplay -l` Card SSM4567, PipeWire sink 正常 |
| **3.5mm 耳機孔** | Nuvoton NAU8825 (I2C) | `avs_nau8825` | 🟢 **正常** | Card NAU8825, 耳機播放+錄音正常 |
| **內建數位麥克風** | Digital Mic | `avs_dmic` | 🟢 **正常** | Card DMIC, `arecord -l` 正常 |
| **Wi-Fi** | Intel 7265 AC [8086:095a] | `iwlwifi` | 🟢 **正常** | `wlp1s0` Wi-Fi 5 AC 已連線 |
| **藍牙** | Intel 7265 BT `8087:0a2a` | `btusb` | 🟢 **存在** | 藍牙裝置存在 |
| **觸控板** | ELAN0000:00 I2C | `elan_i2c` / `i2c_hid` | ⚠️ **驅動已綁定** | `ELAN0000:00` + `Synopsys DesignWare` I2C 正常，手勢未驗證 |
| **視訊鏡頭** | Quanta HP Truevision HD `0408:5060` | `uvcvideo` | 🟢 **存在** | `PipeWire` v4l2 節點 41/48 存在 |
| **儲存** | eMMC 32GB + HFS256G39 via JMS567 USB | `sdhci` / `xhci` | 🟢 **正常** | SD `9d2b`, 外接 238GB 正常 |
| **鍵盤頂排** | ChromeOS EC top-row | `cros_ec` + `hwdb`/`keyd` | 🟢 **正常** | `90-chromebook-keyboard.hwdb` + `keyd/cros.conf` 已映射，`evtest` 已驗證。 |
| **螢幕背光** | `intel_backlight` max 187 | `i915` | 🟢 **存在** | `/sys/class/backlight/intel_backlight` 經 `i915` eDP-1 |
| **EC / PD** | ChromeOS EC LPC + PD | `cros_ec` / `cros_pd` | 🟢 **存在** | `/dev/cros_ec` + `/dev/cros_pd` 正常 |
| **待機休眠** | `[s2idle] deep`（s2idle 預設，deep 可用） | `s2idle` | 🟢 **可用** | 核心同時暴露 `s2idle`（預設）與 `deep`；`deep` 可經 `mem_sleep_default=deep` 或 `echo deep > /sys/power/mem_sleep` 啟用，無硬體 S0ix。 |
| **指紋辨識** | — | — | ⛔ **無硬體** | G1 無指紋感測器 |

---

## 🐧 核心與發行版需求

* **核心**：`>=5.15` 建議 `>=6.5`（Ubuntu 26.04 `7.0.0-30` 已驗證 2026-08-29，`7.0.0-14` baseline 正常；i915 經 `psr=0 fbc=0 dc=0` 修正）
* **音訊**：PipeWire 1.6.2 + AVS 驅動（`snd_soc_avs`）；無需 SOF UCM（與 c640 不同）
* **已測試**：Ubuntu 26.04.1 LTS, kernel 7.0.0-30-generic（Wayland，`i915` + `kbd_backlight` 已驗證 2026-08-29），15Gi RAM
* **復原映像**：`chell`（透過 `chromeos-recovery` 工具）
