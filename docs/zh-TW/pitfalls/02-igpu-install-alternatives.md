<!-- markdownlint-disable MD013 -->
<!-- SPDX-License-Identifier: MIT -->
<!-- SPDX-FileCopyrightText: 2026 Samson <https://github.com/samson1357924> -->

# PITFALL-02: 安裝階段 iGPU 替代方案（不走 `nomodeset`）

> **紀錄時間**: 2026-08-29 | **裝置**: HP Chromebook 13 G1 (Google `chell`,
> Skylake-Y HD515 `[8086:191e]`) | **作者**: samson1357924 |
> **核心**: 7.0.0-30-generic (Ubuntu 26.04.1 LTS) |
> **韌體**: MrChromebox 2606.1

## 摘要

PITFALL-01 (`01-safe-graphics-nomodeset.md`) 用 `nomodeset` 禁用**全部**
DRM KMS 退回 `simpledrm`。本文記載**在 USB 安裝階段就保留 `i915`
啟用**的已驗證替代方案，適合想在 Live 即有硬加速、或想避開
`curtin` 持久化陷阱的使用者。

根本原因回顧（見 `../../../README.md` §3）：面板需 `361.31 MHz`
（`xrandr --verbose` `361310`、`i915_display_info` `port_clock 540000 x4`），
預設 `CDCLK 337.5 MHz` 不足 → `CPU pipe A FIFO underrun` → 背光亮但黑屏。
修正後 `CDCLK 450 MHz` 並關閉衝突的省電時序。

## 決策矩陣

| 編號 | 方案 | 保留 `i915`？ | Live 有硬解？ | 狀態 | 殘留風險 | 複雜度 | 適用情境 |
|---|--------|:-------------:|:-----------------:|------|:--------------:|------------|------------------|
| A | GRUB 加 `i915.enable_psr=0 fbc=0 dc=0`（主替代） | ✅ | ✅ | ✅ 已驗證 2026-08-29 | 低（自行控制） | 低 | 想 Live 即有 `i915`、單一隨身碟 |
| B | `video=eDP-1:1920x1080@60` 降解析 | ✅ | ✅（較低解析） | ⚠️ 理論（未驗證） | 低 | 低 | 懷疑面板時序、快速對比 |
| C | `i915.modeset=0` / `modprobe.blacklist=i915` | ❌（僅禁 i915） | ❌ | ⚠️ 理論 | 低 | 低 | 釐清是否 `i915` 造成 |
| D | `nomodeset`（PITFALL-01 基準） | ❌（禁全部 DRM） | ❌ | ✅ 已驗證 | **高**（Ubuntu `curtin` 寫入 `/etc/default/grub`） | 最低 | 保底開機、新手 |
| E | 自訂 EDID / `drm.edid_firmware` | ✅ | ✅ | ⚠️ 理論 | 高 | 高 | 進階 EDID 覆寫 |
| F | 重編核心/VBT（CDCLK 下限 patch） | ✅ | ✅ | ⚠️ 理論 | 極高 | 極高 | 上游貢獻 |

> **專案預設仍為 D → `scripts/fix-graphics.sh` 事後修復**。若在安裝當下
> 就想正確點亮，A 是取代 D 的最佳方案；B/E/F 為理論，待 Live 驗證。

---

## A. GRUB 加 `i915` 穩定參數（推薦替代）

**效果**：`i915` 保持綁定 `card*`
（`/sys/class/drm/card*/device/driver -> i915`），`glxinfo`
`Mesa HD 515` `direct rendering: Yes`，CDCLK 升至 450MHz 消除 FIFO。

**安裝碟 GRUB 步驟**：

1. 反白 `Try or Install Ubuntu` 按 `e`。
2. 找到 `linux /casper/vmlinuz ... quiet splash ---`。
3. 在 `quiet splash` 後、`---` 前空格加入：

   ```text
   i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0
   ```

   結果：

   ```text
   linux /casper/vmlinuz ... quiet splash i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0 ---
   ```

4. 按 `Ctrl+x` / `F10` 開機。
5. 安裝後持久化（同 `fix-graphics.sh` + 手動 GRUB）：

   ```bash
   sudo cp /etc/default/grub /etc/default/grub.bak.$(date +%Y%m%d)
   sudo sed -i 's/ *nomodeset//g' /etc/default/grub
   if ! grep -q "i915.enable_psr=0" /etc/default/grub; then
     sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0/' /etc/default/grub
   fi
   grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
   # 應為：GRUB_CMDLINE_LINUX_DEFAULT="quiet splash i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0"
   sudo update-grub
   sudo update-initramfs -u
   ```

   或 `sudo nano /etc/default/grub` 手動編輯。
   `power/modprobe.d/99-hp-chell-power.conf` 提供
   `options i915 enable_psr=0 enable_fbc=0 enable_dc=0` modprobe 備援，
   但 GRUB 為早期 KMS 主路徑。

**驗證**（同 PITFALL-01 §5）：

```bash
cat /proc/cmdline | grep -E "i915.enable_psr=0|i915.enable_fbc=0|i915.enable_dc=0" && echo "參數 OK"
lsmod | grep i915 && echo "i915 已載入"
readlink /sys/class/drm/card*/device/driver | grep -q i915 && echo "DRM 為 i915"
glxinfo | grep "OpenGL renderer"  # Mesa Intel(R) HD Graphics 515
sudo cat /sys/kernel/debug/dri/*/i915_display_info | grep -E "port_clock|lane_count"
journalctl -k -b | grep -ci "FIFO underrun"  # 應為 0
cat /sys/class/backlight/intel_backlight/max_brightness  # 187，確認 i915 背光
```

注意：`xrandr` 邏輯解析度可能顯示 `3840x2160`（GNOME 縮放），以
`i915_display_info` `mode "3200x1800":60 361310` 為準。

**取捨**：

* 優：Live 即有 `intel_backlight` 與 `snd_soc_avs: i915 init`，無 `curtin` 殘留。
* 缺：需手動輸入，打錯（`enable_psr =0` 空格）會被靜默忽略。

**證據**：2026-08-29, kernel 7.0.0-30,
`i915_display_info` `mode "3200x1800": 60 361310 ... port_clock=540000
lane_count=4`, `i915_dmc_info` `DC3->DC5 count: 0`,
`journalctl -k` FIFO 0（未修前 6/6 boots 皆有 FIFO）。

---

## B. `video=` 降解析（頻寬繞過）

```text
video=eDP-1:1920x1080@60
# 或 2048x1536@60
```

同 A 在 GRUB `linux` 行、`---` 前附加。`1920x1080@60` CVT-RB 時鐘
`~148 MHz` < 337.5，無需動 PSR/FBC/DC 即可避 FIFO；自訂高刷新需自行估
clock。安裝後移除 `video=` 改用 A 回原生 3200x1800。狀態：理論。

**適用**：快速二分確認是否純 CDCLK 問題。

---

## C. `i915.modeset=0` vs `modprobe.blacklist=i915`

```text
i915.modeset=0          # 僅關 KMS，模組仍載入（deprecated）
modprobe.blacklist=i915 # 完全不載入
```

兩者皆退 `simpledrm`（`journalctl -k` `simpledrm 1.0.0 on minor 0`），但
範圍不同。對 `curtin` 是否持久化此二參數**未驗證**（僅 `nomodeset`
有 `curtin-install.log` 證據），理論上亦會被複製，需事後清理。僅用於
除錯。

---

## D. `nomodeset`（基準，見 PITFALL-01）

禁全部 DRM（`drm_core_init() return -ENODEV`），必能開機
（`BOOT_IMAGE=... quiet splash nomodeset` 見 `installer-journal.txt`），
但 `curtin` 持久寫入 `/target/etc/default/grub` →
`/boot/grub/grub.cfg` 且 `GRUB_TIMEOUT_STYLE=hidden` `TIMEOUT=0`，導致
`lsmod | grep i915` 空、`xrandr` `None-1`。事後需 `scripts/fix-graphics.sh`。
新手保底用。

---

## E. 自訂 EDID

```text
drm.edid_firmware=eDP-1:edid/1920x1080.bin
```

需在 `/lib/firmware/edid/` 放韌體並重建 `initramfs`，USB Live 需手動重
打包；`video=eDP-1:e` 為 `video=` 的強制啟用，非 EDID 覆寫。高複雜度，
僅 EDID 玩家。狀態：理論。

---

## F. 重編核心/VBT

Patch `intel_cdclk.c` 將 Skylake-Y CDCLK 下限改 450MHz，或重編 VBT
（`$VBT SKYLAKE 1000 PC 14.34 1/21/2015` 補 `SDC415A` `port_clock`）。追蹤
上游 `drm/i915#16791`/`#16825`（見 `../TROUBLESHOOTING.md`）。

---

## 建議流程

1. **新手**：用 D（`Ubuntu (safe graphics)`）→ 安裝 → `scripts/fix-graphics.sh`。
2. **進階/重裝**：直接用 A 在 GRUB 帶三參數進 Live，`glxinfo`/`i915_display_info` 驗後再安裝。
3. **除錯**：B 二分、C 隔離、F 上游。

## 相關檔案

* `../../../scripts/fix-graphics.sh`、`../../../power/modprobe.d/99-hp-chell-power.conf`
* `../deep-dive/i915-graphics-cdclk.md`、`01-safe-graphics-nomodeset.md`
* `../TROUBLESHOOTING.md`

## 覆現步驟（供審查）

1. HP Chromebook 13 G1, MrChromebox 2606.1, Ubuntu 26.04.1 USB，GRUB 套用 A 開機。
2. Live 執行 `lsmod | grep i915`、`glxinfo | grep renderer`、
   `journalctl -k | grep -i "FIFO\|underrun"`（應 0）、
   `cat /sys/class/backlight/intel_backlight/max_brightness`。
3. 安裝重啟，確認 `cat /proc/cmdline` 保留三參數且無 `nomodeset`。
4. 與 D 路徑對比：`nomodeset` Live → `fix-graphics.sh` → 同驗證。
