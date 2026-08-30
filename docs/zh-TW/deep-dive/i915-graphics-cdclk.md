<!-- markdownlint-disable MD013 -->

# 顯示核心時鐘（CDCLK）與顯示管線深度剖析 (QHD+ FIFO Underrun)

> **目標裝置**: HP Chromebook 13 G1 (Google `chell`, Skylake-Y HD Graphics 515 `[8086:191e]`, rev 07)  
> **螢幕面板**: Samsung SDC415A 13.3" QHD+ (3200x1800 @ 60Hz，像素時鐘 361.310 MHz)  
> **韌體版本**: MrChromebox-2606.1 (Coreboot 2026-07-14, UEFI GOP)  
> **驗證日期**: 2026-08-31 於 Ubuntu 26.04 LTS (Kernel 7.0.0-30-generic)

---

## 1. 問題概述與現象 (Problem Overview)

在使用 Linux 原生 Intel KMS 顯示硬體加速驅動（`i915`）開機時，內建螢幕常出現背光已通電但**完全無畫面（全黑屏）**的現象。
在此同時，系統所有背景服務（包含 SSH 連線、systemd、GDM3 登入管理器與 GNOME Wayland Session 桌面）皆完全正常運作。

檢查核心日誌（`dmesg` / `journalctl -k`）可發現開機瞬間出現連續報錯：

```text
i915 0000:00:02.0: [drm] *ERROR* CPU pipe A FIFO underrun
```

---

## 2. 硬體時鐘與顯示架構 (Hardware Architecture)

### 2.1 面板時序需求 (Detailed Timing Descriptor)

Samsung SDC415A QHD+ 面板之原生解析度為 $3200 \times 1800$ @ 60 Hz。
根據 `i915_display_info` 取得之 DTD 詳細參數：

* **有效顯示解析度 (Active Resolution)**: $3200 \times 1800$
* **總訊框時序幾何 (Total Frame Geometry)**: $3316 \times 1816$
* **像素時鐘 (Pixel Clock / Dot Clock)**: **`361.310 MHz`** (361,310 kHz)
* **eDP 傳輸通道配置**: 4 通道 @ 5.4 Gbps (`port_clock = 540000 kHz`)

### 2.2 Skylake-Y GPU 核心顯示時鐘 (CDCLK) 限制

在 Intel Skylake-Y GT2 (Core m3/m5/m7 6Yxx 系列 / HD Graphics 515) 架構中，GPU 顯示引擎依靠 **Core Display Clock (CDCLK)** 將記憶體中的影格緩衝區寫入顯示管線 FIFO：

Skylake 支援的 CDCLK 階梯頻率（依 `drivers/gpu/drm/i915/display/intel_cdclk.c` `skl_cdclk_table[]`；`Max 675000 kHz` 經 `i915_cdclk_info` 實機驗證）：

* 308.57 MHz
* **337.50 MHz**（開機預設低功耗時鐘）
* **450.00 MHz**（滿足 361.31 MHz 像素時鐘之最低必要頻率）
* 540.00 MHz
* 617.14 MHz
* 675.00 MHz（GPU CDCLK 最大上限）

**顯示引擎物理限制準則**：  
$$\text{CDCLK} \ge \text{Pixel Clock}$$

若 $\text{CDCLK} < \text{Pixel Clock}$（$337.5\text{ MHz} < 361.31\text{ MHz}$），顯示管線硬體 FIFO 的消耗速度大於記憶體控制器填充速度，立即引發 **CPU pipe A FIFO underrun** 欠載錯誤，導致硬體顯示管線當鎖而無輸出（黑屏）。

---

## 3. 根因剖析：GOP Fastboot 無縫接管陷阱 (Root Cause Analysis)

### 3.1 韌體初始化階段

1. MrChromebox UEFI / Coreboot GOP 韌體在開機通電時，將 eDP 顯示初始化在 **`CDCLK = 337.5 MHz`**（推斷的 Skylake 預設低功耗階梯；`drm.debug=0` 下無直接 337.5 MHz 日誌，以 `min cdclk 361310 → 450000` 重算與 FIFO 現象間接推斷）。
2. GOP 韌體透過基礎幀緩衝（`simple-framebuffer` / `simpledrm`）顯示開機標誌與 GRUB 選單。

### 3.2 核心 Fastboot 無縫接管

1. 當 Linux 核心啟動並載入 `i915` 驅動時，驅動偵測到 GOP 已建立顯示管線。
2. 為了避免開機閃爍，`i915` 預設啟用 *fastboot*（無縫接管）機制，直接沿用現有硬體狀態，**不主動觸發完整的 CRTC Modeset 重設**。
3. 因此，驅動在模組載入當下並未重新計算與調整 CDCLK，**CDCLK 仍舊鎖定在推斷的 337.5 MHz**（Skylake 預設低功耗階梯，無直接日誌；以 `min cdclk 361310 → 450000` 重算與 FIFO 現象間接推斷）。
4. 當面板進入完整的 $3200 \times 1800$ @ 60Hz 輸出（$361.31\text{ MHz}$）時，頻寬瞬間不足（範例日誌，實際時間戳依開機而異）：

    ```text
    [    7.587274] i915 0000:00:02.0: [drm] *ERROR* CPU pipe A FIFO underrun
   [    8.082974] i915 0000:00:02.0: [drm] *ERROR* CPU pipe A FIFO underrun
   ```

---

## 4. 電源管理參數調校 (`enable_psr=0 enable_fbc=0 enable_dc=0`)

為了在 CDCLK 提升至 450 MHz 後保持長期穩定運作，必須在 `/etc/modprobe.d/99-hp-chell-power.conf` 與 `/etc/default/grub` 關閉具衝突特性的省電機制：

```ini
options i915 enable_psr=0 enable_fbc=0 enable_dc=0
```

* **`enable_psr=0`（螢幕自刷新）**：停用 PSR1/PSR2。MrChromebox 韌體使用通用 Skylake VBT，缺乏針對 SDC415A 面板特製的時序表，開啟 PSR 易導致睡眠喚醒後同步訊號丟失。
* **`enable_fbc=0`（影格緩衝壓縮）**：停用 FBC。在 $3200 \times 1800$ 超高解析度下，FBC 壓縮演算會佔用管線記憶體頻寬，加劇 FIFO 欠載後的重整失敗。
* **`enable_dc=0`（顯示 C-States）**：停用 DC5/DC6 深度省電狀態，避免運作期間電壓與 CDCLK 再次被節能機制自動降頻至 337.5 MHz。

---

## 5. 線上即時修復與持久化解法 (Fix & Verification)

### 5.1 即時觸發 Modeset（DPMS Cycle）

由於 `i915` 驅動會在真正的 CRTC 啟閉與 Modeset 流程中重新計算所需時鐘，只要對顯示介面發送一次極短的 DPMS 關閉/開啟訊號，即可迫使驅動自動將 CDCLK 提升至 **450.0 MHz**：

**透過 Mutter DBus（Wayland 環境）**：

```bash
# 取得 GDM 登入畫面 session UID
GDM_UID=$(id -u gdm 2>/dev/null || id -u gdm-greeter 2>/dev/null || id -u gdm-greeter-2 2>/dev/null || echo 60579)

# 觸發螢幕管線重設 (DPMS: 3 關閉 -> 0 開啟)
sudo -u $(id -nu $GDM_UID) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$GDM_UID/bus \
  gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
  --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<3>'

sleep 1

sudo -u $(id -nu $GDM_UID) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$GDM_UID/bus \
  gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
  --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<0>'
```

**透過虛擬終端切換 (VT Switch)**：

```bash
sudo chvt 2 && sleep 1 && sudo chvt 1
```

### 5.2 驗證方法

讀取 debugfs 核心時鐘狀態：

```bash
sudo cat /sys/kernel/debug/dri/1/i915_cdclk_info
```

預期正常輸出：

```text
Current CD clock frequency: 450000 kHz
Max CD clock frequency:     675000 kHz
Max pixel clock frequency:  675000 kHz
```

確認核心日誌不再產生 FIFO underrun：

```bash
sudo dmesg | grep -iE 'underrun|fifo'
```

### 5.3 自動化開機腳本

本專案提供強化後的 `scripts/fix-graphics.sh`，可自動檢查並設定相關參數，確保每次冷開機後皆能自動提升並維持 450 MHz CDCLK。
