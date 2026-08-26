# PITFALL-01: 安裝時必須使用 Safe Graphics / nomodeset 才能進入安裝界面

> **紀錄時間**: 2026-08-27 | **裝置**: HP Chromebook 13 G1 (Google `chell`, Skylake-Y HD515) | **回報**: samson1357924 | **系統**: Ubuntu 26.04.1 LTS USB 安裝碟

## 現象

從隨身碟 (USB) 開機安裝 Ubuntu 時，**若直接選擇 `Try or Install Ubuntu` 會黑畫面 / 卡在 logo，無法進入安裝界面**。

## 必要操作 (二選一)

### 選項 A: 選 Safe Graphics

在 GRUB 開機選單選擇 **`Ubuntu (safe graphics)`** (Ubuntu 26.04 安裝碟的第二個選項)，即可正常進入 Live 環境並完成安裝。

### 選項 B: 手動加 nomodeset

1. 在 GRUB 選單反白 `Try or Install Ubuntu` 按 `e` 進入編輯
2. 找到 `linux` 開頭的那一行，行尾加入 ` nomodeset` (與前面的 `quiet splash` 空格隔開)
3. 按 `Ctrl+x` 或 `F10` 開機，即可進入安裝界面

```text
linux   /casper/vmlinuz ... quiet splash nomodeset ---
                                     ^^^^^^^^^^^ 手動加上
```

## 為何會這樣

* `chell` 的 Intel HD Graphics 515 (Skylake-Y GT2) 在 Ubuntu 26.04 預設核心 `7.0.0-14` 的 `i915` KMS 模式與此機的 GOP/VBT 時序不完全相容，直接 KMS 會導致顯示初始化失敗。
* `nomodeset` 會讓核心停用所有 DRM KMS 驅動，改用 `simpledrm` / `simple-framebuffer`，雖然無硬加速但能保證進入安裝界面。
* 安裝完成後系統會把 `nomodeset` 寫入 `/etc/default/grub` (`GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nomodeset"`) 並殘留，導致後續仍以 `simple-framebuffer` 運行 (`/sys/class/drm/card0/device/driver -> simple-framebuffer`, `lsmod` 無 `i915`)，需事後修復。

## 安裝後修復 (啟用 i915 硬加速)

安裝完成首次進入系統後，執行本專案提供的修復腳本：

```bash
cd ~/projects/hp-chromebook-13-g1-linux
chmod +x scripts/fix-graphics.sh
./scripts/fix-graphics.sh
# 或
sudo sed -i 's/ *nomodeset//g' /etc/default/grub
grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub  # 確認已移除
sudo update-grub
sudo update-initramfs -u
sudo reboot
```

重啟後驗證：

```bash
cat /proc/cmdline | grep -q nomodeset && echo "仍有 nomodeset!" || echo "OK 已移除"
lsmod | grep i915 && echo "i915 已載入"
readlink /sys/class/drm/card0/device/driver | grep -q i915 && echo "DRM 為 i915"
glxinfo | grep "renderer string"  # 應為 Mesa Intel HD Graphics 515
```

> 若移除 `nomodeset` 後黑畫面，開機在 GRUB 按 `e` 臨時加回 `nomodeset` 即可恢復，再回報 `journalctl -k | grep drm`。

## 相關文件

* `scripts/fix-graphics.sh` - 一鍵移除 `nomodeset`
* `docs/TROUBLESHOOTING.md#nomodeset` - 常見問題速查
* 參考: 本機 `ubuntu-13g1` 實測 (BIOS MrChromebox 2606.1, kernel 7.0.0-14, Wayland)
