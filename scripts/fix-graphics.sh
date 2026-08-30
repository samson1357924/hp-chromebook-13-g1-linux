#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Samson <https://github.com/samson1357924>
# Fix nomodeset trap and CDCLK / FIFO underrun for HP Chromebook 13 G1 (chell / Skylake HD515)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logger.sh" 2> /dev/null || true

log_section() { echo -e "\n=== $* ==="; }
log_info() { echo "[INFO] $*"; }
log_success() { echo "[OK] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[FAIL] $*"; }
# Note: log helpers intentionally use $* (not "$@") for single-line messages; caller passes one string.

get_cdclk_khz() {
    local f val
    for f in /sys/kernel/debug/dri/0/i915_cdclk_info /sys/kernel/debug/dri/1/i915_cdclk_info /sys/kernel/debug/dri/*/i915_cdclk_info; do
        [ -e "$f" ] || continue
        # Try direct cat first (works when running as root via sudo/service), fallback to sudo cat
        val="$(cat "$f" 2>/dev/null | awk '/Current CD clock frequency/ {print $5}')"
        if [ -z "$val" ] || [ "$val" = "0" ]; then
            val="$(sudo -n cat "$f" 2>/dev/null | awk '/Current CD clock frequency/ {print $5}')"
        fi
        if [ -n "$val" ] && [ "$val" -gt 0 ] 2>/dev/null; then
            echo "$val"
            return 0
        fi
    done
    echo "0"
}

cycle_dpms() {
    log_info "Attempting DPMS display cycle to trigger CDCLK elevation..."
    local gdm_bus=""
    local gdm_uid=""
    local gdm_pid=""
    # Robust GDM UID detection: try id(1) for known gdm accounts, then pgrep fallback
    gdm_uid="$(id -u gdm 2>/dev/null || id -u gdm-greeter 2>/dev/null || id -u gdm-greeter-2 2>/dev/null || echo "")"
    if [ -z "$gdm_uid" ]; then
        gdm_pid="$(pgrep -f 'gnome-shell --mode=gdm' 2>/dev/null | head -1 || true)"
        if [ -n "$gdm_pid" ]; then
            gdm_uid="$(ps -o uid= -p "$gdm_pid" 2>/dev/null | tr -d ' ' || echo "")"
        fi
    else
        gdm_pid="$(pgrep -u "$gdm_uid" gnome-shell 2>/dev/null | head -1 || true)"
    fi
    if [ -n "$gdm_uid" ]; then
        gdm_bus="unix:path=/run/user/${gdm_uid}/bus"
        
        if [ -e "/run/user/${gdm_uid}/bus" ]; then
            sudo -u "#${gdm_uid}" DBUS_SESSION_BUS_ADDRESS="$gdm_bus" \
                gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
                --object-path /org/gnome/Mutter/DisplayConfig \
                --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<3>' > /dev/null 2>&1 || true
            sleep 1
            sudo -u "#${gdm_uid}" DBUS_SESSION_BUS_ADDRESS="$gdm_bus" \
                gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
                --object-path /org/gnome/Mutter/DisplayConfig \
                --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<0>' > /dev/null 2>&1 || true
        fi
    fi

    # Fallback to VT toggle if DBus method wasn't available or CDCLK didn't change
    local cur_clk cur_vt
    cur_clk="$(get_cdclk_khz)"
    if [ -n "$cur_clk" ] && [ "$cur_clk" -lt 400000 ] 2>/dev/null; then
        log_info "DBus toggle not sufficient; using VT toggle fallback..."
        cur_vt="$(fgconsole 2>/dev/null || echo 1)"
        sudo chvt 2 2>/dev/null || true
        sleep 1
        sudo chvt "$cur_vt" 2>/dev/null || sudo chvt 1 2>/dev/null || true
    fi

    cur_clk="$(get_cdclk_khz)"
    if [ -n "$cur_clk" ] && [ "$cur_clk" -ge 400000 ] 2>/dev/null; then
        log_success "CDCLK successfully raised to ${cur_clk} kHz (>= 450 MHz required for 3200x1800)."
    else
        log_warn "CDCLK is currently ${cur_clk} kHz."
    fi
}

install_autofix_service() {
    log_section "Installing Chell CDCLK Auto-Fix Service"
    local service_file="/etc/systemd/system/chell-cdclk-fix.service"
    local installed_script="/usr/local/bin/chell-cdclk-fix.sh"

    # Install a portable copy so the service does not depend on the git checkout path
    sudo install -Dm755 "$SCRIPT_DIR/fix-graphics.sh" "$installed_script"

    sudo bash -c "cat > '$service_file'" << SERVICE_EOF
[Unit]
Description=HP Chromebook 13 G1 CDCLK Fastboot Fix
After=gdm.service display-manager.service graphical.target
Wants=gdm.service display-manager.service
ConditionPathExists=/sys/kernel/debug

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 3
ExecStart=$installed_script --cycle-dpms-if-needed
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
SERVICE_EOF

    sudo chmod 644 "$service_file"
    sudo systemctl daemon-reload
    sudo systemctl enable chell-cdclk-fix.service
    log_success "Enabled chell-cdclk-fix.service to automate CDCLK elevation on boot (installed to $installed_script)."
}

# Parse CLI arguments
case "${1:-}" in
    --cycle-dpms)
        cycle_dpms
        exit 0
        ;;
    --cycle-dpms-if-needed)
        cur_clk="$(get_cdclk_khz)"
        if [ -n "$cur_clk" ] && [ "$cur_clk" -lt 400000 ] 2>/dev/null; then
            log_info "Detected CDCLK ($cur_clk kHz) < 400000 kHz. Running DPMS cycle..."
            cycle_dpms
        else
            log_info "CDCLK is already optimal ($cur_clk kHz). No action needed."
        fi
        exit 0
        ;;
    --install-service)
        install_autofix_service
        exit 0
        ;;
    -h|--help)
        echo "Usage: $0 [--cycle-dpms|--cycle-dpms-if-needed|--install-service]"
        exit 0
        ;;
    --*)
        log_error "Unknown option: $1"
        echo "Usage: $0 [--cycle-dpms|--cycle-dpms-if-needed|--install-service]" >&2
        exit 2
        ;;
esac

log_section "Graphics & Display Pipeline Diagnosis for Chell (HD515 i915)"
echo "Current cmdline: $(cat /proc/cmdline | tr ' ' '\n' | grep -E 'nomodeset|quiet|i915' || true)"
echo "GRUB file: $(grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub 2>&1 | head -1)"
echo "Driver now: $(readlink /sys/class/drm/card*/device/driver 2>&1 | head -1 | xargs basename 2> /dev/null || echo none)"

cdclk_khz="$(get_cdclk_khz)"
if [ -n "$cdclk_khz" ] && [ "$cdclk_khz" -gt 0 ] 2>/dev/null; then
    echo "Current CDCLK: ${cdclk_khz} kHz (Required: >= 361310 kHz / 450 MHz)"
fi

# 1. Check and fix nomodeset
if grep -q "nomodeset" /proc/cmdline || grep -q "nomodeset" /etc/default/grub; then
    log_info "nomodeset detected - removing from /etc/default/grub"
    sudo cp /etc/default/grub "/etc/default/grub.bak.$(date '+%Y%m%d')"
    sudo sed -i 's/ *nomodeset//g' /etc/default/grub
    grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
    sudo update-grub
    sudo update-initramfs -u
    log_success "Removed nomodeset from GRUB."
fi

# 2. Check and configure modprobe parameters
MODPROBE_CONF="/etc/modprobe.d/99-hp-chell-power.conf"
if [ ! -f "$MODPROBE_CONF" ] || ! grep -q "enable_psr=0" "$MODPROBE_CONF"; then
    log_info "Configuring i915 tuning in $MODPROBE_CONF..."
    sudo bash -c "cat > '$MODPROBE_CONF'" << 'CONF_EOF'
# HP Chromebook 13 G1 (Chell) Graphics & Wireless Tuning
options i915 enable_psr=0 enable_fbc=0 enable_dc=0
options iwlwifi power_save=1 uapsd_disable=0
CONF_EOF
    sudo chmod 644 "$MODPROBE_CONF"
    log_success "Installed $MODPROBE_CONF"
fi

# 3. Check CDCLK frequency status
if [ -n "$cdclk_khz" ] && [ "$cdclk_khz" -lt 400000 ] 2>/dev/null; then
    log_warn "CDCLK is ${cdclk_khz} kHz (< 450 MHz target). Triggering DPMS cycle..."
    cycle_dpms
else
    log_success "CDCLK is optimal (${cdclk_khz} kHz)."
fi

# 4. Prompt / enable persistent service
if [ ! -f "/etc/systemd/system/chell-cdclk-fix.service" ]; then
    install_autofix_service
fi

log_success "Graphics configuration and verification completed."
