<!-- markdownlint-disable MD013 MD022 MD031 MD032 -->

# HP Chromebook 13 G1 (CHELL) Linux 安裝與顯示黑屏故障排除紀錄

本專案記錄在 **HP Chromebook 13 G1**（Google 開發代號：`CHELL`）上安裝與運行 Linux（Ubuntu 26.04 LTS）的硬體規格、問題排查過程及解決方案。

---

## 1. 硬體規格概覽 (Hardware Specifications)

| 元件 | 規格詳細資訊 |
| :--- | :--- |
| **主機代號** | Google `CHELL` (Glados 家族) |
| **BIOS / 韌體** | `coreboot` + `MrChromebox-2606.1 UEFI` (Release: 2026/07/14) |
| **處理器 (CPU)** | Intel Core m7-6Y75 @ 1.20GHz (Skylake-Y / ULX, 4.5W TDP, 2C/4T) |
| **顯示晶片 (GPU)** | Intel HD Graphics 515 (Skylake GT2 `[8086:191e]`, rev 07) |
| **螢幕面板** | Samsung 13.3 吋 QHD+ 面板 (`SDC 16730` / `SDC415A`), 原生解析度 **3200x1800 @ 60Hz** |
| **音效晶片** | Intel Sunrise Point-LP HD Audio (`snd_soc_avs`) |
| **無線網路** | Intel Wireless 7265 Dual Band AC (`iwlwifi`) |
| **作業系統** | Ubuntu 26.04.1 LTS (Linux Kernel 7.0.0-30-generic) |

---

## 2. 問題描述 (Problem Description)

* **情境**：在安裝 Linux 時，因驅動相容問題啟動參數加入了 `nomodeset` 才能順利進入安裝程式。
* **現象**：安裝完成並更新驅動後，將 `nomodeset` 移除，開機時面板**完全黑屏（無畫面輸出）**，但系統背景服務（SSH、GDM3、GNOME Wayland Session）正常運作，背光亦有通電。
* **復發性**：只要使用原生 `i915` 驅動（不帶 `nomodeset`），必定出現黑屏。

---

## 3. 根本原因剖析 (Root Cause Analysis) — 經 subagents 實機驗證

> **硬體指紋**: `Google Chell` (`lars`/`Glados` family, `/sys/class/dmi/id/board_name:1`=`Chell`), `MrChromebox-2606.1` (`/sys/class/dmi/id/bios_version:1`, `coreboot` 2026-07-14, VBIOS `Build 1000 PC 14.34 1/21/2015` via `/sys/kernel/debug/dri/1/i915_vbt:1`), `m7-6Y75` Skylake-Y ULX + `HD Graphics 515 [8086:191e] rev 07` (`lspci -nnk:00:02.0`), `Samsung SDC415A 3200x1800@60 361.31MHz` (`xrandr:1`/`i915_display_info: mode 361310`), `Sunrise Point-LP HD Audio [8086:9d70]` (`lspci -nnk:00:1f.3`=`snd_soc_avs`)

### 3.1 硬體時鐘瓶頸 — Pixel Clock > CDCLK (主因, 已驗證)

* 面板 DTD 要求 **`361.310 MHz`** (`xrandr --verbose:1`, `i915_display_info: CRTC pipe A mode 361310, port_clock 540000 x4 lanes`), 而 Skylake-Y 預設 `CDCLK=337.5 MHz` (`README 原 337.5MHz` + `journalctl -k -b -6:1` `Reducing the compressed framebuffer size...`).
* 因 `361.31 > 337.5` 頻寬不足，`i915` 在 KMS modeset 瞬間連續觸發 **`[drm] *ERROR* CPU pipe A FIFO underrun`** (`journalctl -k -b -6/-5:1`, 每 boot 1-2次, `dmesg | grep FIFO` 在未修復時 6 boots 連續復現), 畫面鎖死黑屏但 SSH/GDM Wayland 存活。修復後 `CDCLK=450.0 MHz` (`450000 kHz`) 且 `FIFO underrun` 近零（近 3 次啟動 0 次，9 boots 內偶發 1-2 次單發 `FIFO underrun`/`Atomic update failure`，不再連發致黑屏；可用 `journalctl -k | grep -E "FIFO|Atomic"` 持續監控）。

### 3.2 GOP/VBT 未為 QHD+ 定製 + 節能時序衝突 (協同主因, 已驗證)

* `sudo cat /sys/kernel/debug/dri/1/i915_vbt | strings:1` 顯示 `$VBT SKYLAKE Build Number: 1000 PC 14.34 1/21/2015` 為 Intel 公版參考 VBIOS, `LFP_PanelName` 連續 16 次空字串占位, 未寫入 `SDC415A` 的 `port_clock 540MHz / 4 lanes / DPCD 1.2` 真實 DTD。`chell` 作為 `lars` family 唯一 QHD+ 變種沿用 1080p 模板, 導致 UEFI GOP 僅能以固定 CDCLK 點亮 `simpledrm` (`[drm] Initialized simpledrm 1.0.0 for simple-framebuffer.0 on minor 0` via `journalctl -k:1`), KMS 重算 CDCLK 時未自動升頻。
* **PSR / FBC / DC5-6** 在 3200x1800 eDP 上加劇爭用: `i915_edp_psr_status: Sink support PSR=yes, mode disabled (due to module param)` + `i915_fbc_status: disabled per module param` + `DC3->DC5 count 0` 為修復後 `i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0` (`/proc/cmdline:1`, `/etc/default/grub:9`, `/sys/module/i915/parameters/enable_psr:1`=0) 狀態, 未禁用時與 MrChromebox-2606.1 配置衝突。
* 已排除 **韌體缺漏**: `/lib/firmware/i915/skl_dmc_ver1_27.bin.zst:1` 存在且 `journalctl -k:1` `Finished loading DMC firmware i915/skl_dmc_ver1_27.bin (v1.27)` 成功, `linux-firmware-intel-graphics:1` 為最新, `modinfo i915:1` 所需 `skl_huc_2.0.0/skl_guc_70.1.1` 齊全, `CONFIG_DRM_I915=m` 在 `7.0.0-14` 與 `7.0.0-30` 皆支援 `191e`。

### 3.3 為何 `nomodeset` / `Ubuntu (safe graphics)` 可以開機 (已驗證)

* `nomodeset` 為 `kernel-parameters.txt:1` 全局開關, 使 `drm_core_init()` 直接 `return -ENODEV`, **禁用所有 DRM KMS 驅動** (`i915/xe/amdgpu` 皆禁), 退回 UEFI GOP 的 `simple-framebuffer simple-framebuffer.0 [drm] fb0: simpledrmdrmfb` (`simpledrm 1.0.0 on minor 0` via `journalctl -k:1`), 無 `gem`/`backlight`/`atomic commit` 但保證 Live 桌面。證據: `installer-journal.txt:3` `BOOT_IMAGE=/casper/vmlinuz --- quiet splash nomodeset` + `gnome-shell: Not hardware accelerated` + `snd_soc_avs: i915 init unsuccessful: -19`。
* **GRUB 兩路徑等價**: `Try or Install Ubuntu` 按 `e` 在 `linux` 行尾加 `nomodeset` 與選 `Ubuntu (safe graphics)` 皆產生 `/proc/cmdline: quiet splash nomodeset` (`docs/pitfalls/01-safe-graphics-nomodeset.md:18`).

### 3.4 安裝程式殘留陷阱 — Ubuntu `curtin` 獨有 (已驗證)

* `Subiquity + curtin` 在 `curthooks` 階段執行 `updated /target/etc/default/grub to set: GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nomodeset"` (`curtin-install.log:1382`, `installer-journal.txt:7050`), 並 `update-grub` 生成 `/boot/grub/grub.cfg:168 linux ... quiet splash nomodeset`。`GRUB_TIMEOUT_STYLE=hidden` + `TIMEOUT=0` (`/etc/default/grub:7-8`) 使使用者難以察覺, 導致後續 `lsmod | grep i915` 空、`readlink /sys/class/drm/card1/device/driver:1` 指向 `simple-framebuffer`、`xrandr` 僅 `None-1`。
* **是否僅 Ubuntu**: 觸發條件 (需 `nomodeset` 才能 Live) 為所有 `kernel 6.8+/7.0+` + `simpledrm` 在 `chell/Skylake-Y` 共通; **持久化殘留為 Ubuntu/curtin 獨有** (Fedora/Arch 不自動抄寫 Live cmdline)。

> **一句話總結**: 非韌體缺失/核心移除 SKL, 而是 **2015 公版 GOP/VBT 對 QHD+ 時序支援不足 + 預設 CDCLK 過低 + PSR/FBC/DC 節能衝突** 共同導致 FIFO 欠載, `nomodeset` 僅靠退至 `simpledrm` 規避而「看似可行」, 並被安裝程式持久化。

---

## 4. 解決方案與步驟 (Fix & Implementation)

### 步驟 1：修改 GRUB 核心參數
編輯 `/etc/default/grub`：
```bash
sudo nano /etc/default/grub
```
將 `GRUB_CMDLINE_LINUX_DEFAULT` 修改為包含 `i915` 穩定性參數：
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0"
```

* **`i915.enable_psr=0`**：停用 Panel Self Refresh，消除 eDP 面板時序不同步。
* **`i915.enable_fbc=0`**：停用幀緩衝區壓縮，避免 3200x1800 記憶體緩衝區爭用。
* **`i915.enable_dc=0`**：停用 Display C-States，防止顯示核心進入過深休眠導致動態時鐘不足。

### 步驟 2：更新 GRUB 與模組參數並安裝自動修復服務
亦可直接執行專案自動化腳本一鍵配置與驗證：
```bash
# 自動移除 nomodeset、設定 i915 參數並安裝開機 CDCLK 修復服務
sudo ./scripts/fix-graphics.sh
sudo update-grub
sudo reboot
```

> [!NOTE]
> **冷開機 Fastboot 陷阱防護**：MrChromebox UEFI GOP 開機時將 CDCLK 置於 337.5 MHz，Linux `i915` 無縫接管（fastboot）在冷開機時可能未觸發 Modeset 重算時鐘。腳本安裝的 `chell-cdclk-fix.service` 會在 GDM 啟動時自動檢查 CDCLK，若未滿 450 MHz 則自動觸發極短的 DPMS 重設，確保螢幕每次冷開機皆必定亮屏。

---

## 5. 驗證結果 (Verification)

重開機後，經實機診斷確認：
* **Core Display Clock (CDCLK)**：從 337.5 MHz 成功自動提升並穩定於 **`450.0 MHz`**（`450000 kHz`），高於像素時鐘 361.31 MHz。
* **FIFO Underrun 報錯**：近 3 次啟動 `CPU pipe A FIFO underrun` 為 0，9 boots 內偶發單次 `FIFO underrun`/`Atomic update failure`（修復前 6/6 連續復現，修復後頻率與嚴重度大幅下降，不再連發致黑屏）。
* **顯示狀態**：GDM3 與 GNOME Shell 桌面正常輸出，Intel HD 515 硬體加速與背光調節功能皆運作正常。`xrandr` 在 Wayland `scale-monitor-framebuffer` 下顯示 3840x2160 為 XWayland 邏輯放大，DRM 物理層仍為 3200x1800@60（以 `Mutter GetCurrentState` / `i915_display_info` 為準）。
