#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Fix nomodeset trap for HP Chromebook 13 G1 (chell / Skylake HD515)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logger.sh" 2>/dev/null || true

log_section() { echo "=== $* ==="; }
log_info() { echo "[INFO] $*"; }
log_success() { echo "[OK] $*"; }

log_section "Graphics Fix for chell (HD515 i915)"
echo "Current: $(cat /proc/cmdline | tr ' ' '\n' | grep -E 'nomodeset|quiet' || true)"
echo "GRUB: $(grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub 2>&1 | head -1)"
echo "Driver now: $(readlink /sys/class/drm/card0/device/driver 2>&1 | xargs basename 2>/dev/null || echo none)"
lsmod | grep -E "i915|simpledrm" || echo "no i915/simpledrm in lsmod"

if grep -q "nomodeset" /proc/cmdline; then
  log_info "nomodeset detected - removing from /etc/default/grub"
  sudo cp /etc/default/grub /etc/default/grub.bak.$(date +%Y%m%d)
  sudo sed -i 's/ *nomodeset//g' /etc/default/grub
  grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
  sudo update-grub
  sudo update-initramfs -u
  log_success "Removed nomodeset, please reboot: sudo reboot"
  echo "Post-reboot verify: lsmod | grep i915 && glxinfo | grep renderer"
else
  log_success "nomodeset not present, i915 should load. If still simpledrm, check kernel: 7.0.0-14 should support Skylake."
fi
