#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Samson <https://github.com/samson1357924>
# Fix nomodeset trap and CDCLK / FIFO underrun for HP Chromebook 13 G1 (chell / Skylake HD515)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/logger.sh
source "$ROOT_DIR/lib/logger.sh" 2> /dev/null || true
# shellcheck source=../lib/backup.sh
source "$ROOT_DIR/lib/backup.sh" 2> /dev/null || true

get_cdclk_khz() {
    local f val
    for f in /sys/kernel/debug/dri/0/i915_cdclk_info /sys/kernel/debug/dri/1/i915_cdclk_info /sys/kernel/debug/dri/*/i915_cdclk_info; do
        [ -e "$f" ] || continue
        # Try direct cat first (works when running as root via sudo/service), fallback to sudo cat
        val="$(cat "$f" 2> /dev/null | awk '/Current CD clock frequency/ {print $5}')"
        if [ -z "$val" ] || [ "$val" = "0" ]; then
            val="$(sudo -n cat "$f" 2> /dev/null | awk '/Current CD clock frequency/ {print $5}')"
        fi
        if [ -n "$val" ] && [ "$val" -gt 0 ] 2> /dev/null; then
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
    gdm_uid="$(id -u gdm 2> /dev/null || id -u gdm-greeter 2> /dev/null || id -u gdm-greeter-2 2> /dev/null || echo "")"
    if [ -z "$gdm_uid" ]; then
        gdm_pid="$(pgrep -f 'gnome-shell --mode=gdm' 2> /dev/null | head -1 || true)"
        if [ -n "$gdm_pid" ]; then
            gdm_uid="$(ps -o uid= -p "$gdm_pid" 2> /dev/null | tr -d ' ' || echo "")"
        fi
    else
        gdm_pid="$(pgrep -u "$gdm_uid" gnome-shell 2> /dev/null | head -1 || true)"
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
    if [ -n "$cur_clk" ] && [ "$cur_clk" -lt 400000 ] 2> /dev/null; then
        log_info "DBus toggle not sufficient; using VT toggle fallback..."
        cur_vt="$(fgconsole 2> /dev/null || echo 1)"
        sudo chvt 2 2> /dev/null || true
        sleep 1
        sudo chvt "$cur_vt" 2> /dev/null || sudo chvt 1 2> /dev/null || true
    fi

    cur_clk="$(get_cdclk_khz)"
    if [ -n "$cur_clk" ] && [ "$cur_clk" -ge 400000 ] 2> /dev/null; then
        log_success "CDCLK successfully raised to ${cur_clk} kHz (>= 450 MHz required for 3200x1800)."
    else
        log_warn "CDCLK is currently ${cur_clk} kHz."
    fi
}

install_autofix_service() {
    log_section "Installing Chell CDCLK Auto-Fix Service"
    local service_file="/etc/systemd/system/chell-cdclk-fix.service"
    local installed_script="/usr/local/bin/chell-cdclk-fix.sh"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Would backup file: $installed_script (if exists)"
        log_dryrun "Would record in manifest: [graphics] $installed_script"
        log_dryrun "Would install portable copy $SCRIPT_DIR/fix-graphics.sh -> $installed_script"
        log_dryrun "Would backup file: $service_file (if exists)"
        log_dryrun "Would record in manifest: [graphics] $service_file"
        log_dryrun "Would install $service_file and enable chell-cdclk-fix.service"
        return 0
    fi

    # Install a portable copy so the service does not depend on the git checkout path
    local existed_script=0
    [ -e "$installed_script" ] && existed_script=1
    backup_file_manifest_aware "$installed_script" "graphics"
    sudo install -Dm755 "$SCRIPT_DIR/fix-graphics.sh" "$installed_script"
    # Ensure manifest records it (backup_file_manifest_aware may have already added, but ensure idempotent)
    if ! manifest_has_target "$installed_script" 2> /dev/null; then
        manifest_add_entry "$installed_script" "graphics" "$existed_script"
    fi

    backup_file_manifest_aware "$service_file" "graphics"
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
    if ! manifest_has_target "$service_file" 2> /dev/null; then
        manifest_add_entry "$service_file" "graphics" "0"
    fi
    # Record service state before enabling
    manifest_add_service "chell-cdclk-fix.service" "graphics" 2> /dev/null || true
    sudo systemctl daemon-reload 2> /dev/null || true
    sudo systemctl enable chell-cdclk-fix.service 2> /dev/null || true
    log_success "Enabled chell-cdclk-fix.service to automate CDCLK elevation on boot (installed to $installed_script)."
}

uninstall_graphics() {
    log_section "Uninstalling Graphics Fix (graphics)"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Would disable chell-cdclk-fix.service and rollback graphics component"
        log_dryrun "Would remove /usr/local/bin/chell-cdclk-fix.sh and /etc/systemd/system/chell-cdclk-fix.service if untracked"
        return 0
    fi

    # Disable service before rollback so manifest service state can be restored
    if systemctl is-enabled chell-cdclk-fix.service 2> /dev/null; then
        sudo systemctl disable --now chell-cdclk-fix.service 2> /dev/null || true
    else
        sudo systemctl stop chell-cdclk-fix.service 2> /dev/null || true
    fi

    # Rollback tracked files via manifest (grub, modprobe, service, script)
    if command -v rollback_component > /dev/null 2>&1; then
        rollback_component "graphics" 2> /dev/null || true
    fi

    # Fallback cleanup for files not tracked by old manifests
    sudo rm -f /usr/local/bin/chell-cdclk-fix.sh 2> /dev/null || true
    sudo rm -f /etc/systemd/system/chell-cdclk-fix.service 2> /dev/null || true
    sudo systemctl daemon-reload 2> /dev/null || true
    log_success "Graphics fix uninstalled."
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --cycle-dpms               Trigger DPMS cycle to elevate CDCLK"
    echo "  --cycle-dpms-if-needed     Trigger DPMS cycle only if CDCLK < 400 MHz"
    echo "  --install-service          Install persistent CDCLK auto-fix service"
    echo "  --uninstall, -u            Uninstall graphics fix and rollback configs"
    echo "  --dry-run, -n              Preview without modifying system"
    echo "  --help, -h                 Show help"
}

# Parse CLI arguments (support --dry-run as global flag)
ACTION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --cycle-dpms)
            ACTION="cycle-dpms"
            shift
            ;;
        --cycle-dpms-if-needed)
            ACTION="cycle-dpms-if-needed"
            shift
            ;;
        --install-service)
            ACTION="install-service"
            shift
            ;;
        --uninstall | -u)
            ACTION="uninstall"
            shift
            ;;
        --dry-run | -n)
            export DRY_RUN=1
            shift
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        --*)
            log_error "Unknown option: $1"
            show_help >&2
            exit 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help >&2
            exit 2
            ;;
    esac
done

case "$ACTION" in
    cycle-dpms)
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_dryrun "Would trigger DPMS cycle (cycle-dpms)"
            exit 0
        fi
        cycle_dpms
        exit 0
        ;;
    cycle-dpms-if-needed)
        cur_clk="$(get_cdclk_khz)"
        if [ -n "$cur_clk" ] && [ "$cur_clk" -lt 400000 ] 2> /dev/null; then
            log_info "Detected CDCLK ($cur_clk kHz) < 400000 kHz. Running DPMS cycle..."
            if [ "${DRY_RUN:-0}" = "1" ]; then
                log_dryrun "Would trigger DPMS cycle (cycle-dpms-if-needed)"
            else
                cycle_dpms
            fi
        else
            log_info "CDCLK is already optimal ($cur_clk kHz). No action needed."
        fi
        exit 0
        ;;
    install-service)
        install_autofix_service
        exit 0
        ;;
    uninstall)
        uninstall_graphics
        exit 0
        ;;
esac

log_section "Graphics & Display Pipeline Diagnosis for Chell (HD515 i915)"
echo "Current cmdline: $(cat /proc/cmdline 2> /dev/null | tr ' ' '\n' | grep -E 'nomodeset|quiet|i915' || true)"
if [ -f /etc/default/grub ]; then
    echo "GRUB file: $(grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub 2>&1 | head -1)"
else
    echo "GRUB file: (not found - /etc/default/grub missing)"
fi
echo "Driver now: $(readlink /sys/class/drm/card*/device/driver 2>&1 | head -1 | xargs basename 2> /dev/null || echo none)"

cdclk_khz="$(get_cdclk_khz)"
if [ -n "$cdclk_khz" ] && [ "$cdclk_khz" -gt 0 ] 2> /dev/null; then
    echo "Current CDCLK: ${cdclk_khz} kHz (Required: >= 361310 kHz / 450 MHz)"
fi

# 1. Check and fix nomodeset
GRUB_FILE="/etc/default/grub"
has_nomodeset=0
if grep -q "nomodeset" /proc/cmdline 2> /dev/null; then
    has_nomodeset=1
elif [ -f "$GRUB_FILE" ] && grep -q "nomodeset" "$GRUB_FILE" 2> /dev/null; then
    has_nomodeset=1
fi
if [ "$has_nomodeset" = "1" ]; then
    log_info "nomodeset detected - removing from $GRUB_FILE"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Would backup file: $GRUB_FILE"
        log_dryrun "Would sed -i 's/ *nomodeset//g' $GRUB_FILE && update-grub && update-initramfs -u"
    else
        if [ -f "$GRUB_FILE" ]; then
            backup_file_manifest_aware "$GRUB_FILE" "graphics"
            sudo sed -i 's/ *nomodeset//g' "$GRUB_FILE"
            grep GRUB_CMDLINE_LINUX_DEFAULT "$GRUB_FILE" || true
            sudo update-grub 2> /dev/null || sudo grub-mkconfig -o /boot/grub/grub.cfg 2> /dev/null || true
            sudo update-initramfs -u 2> /dev/null || true
            log_success "Removed nomodeset from GRUB."
        else
            log_warn "GRUB file not found; cannot remove nomodeset from $GRUB_FILE"
        fi
    fi
fi

# 2. Check and configure modprobe parameters
MODPROBE_CONF="/etc/modprobe.d/99-hp-chell-power.conf"
if [ ! -f "$MODPROBE_CONF" ] || ! grep -q "enable_psr=0" "$MODPROBE_CONF" 2> /dev/null; then
    log_info "Configuring i915 tuning in $MODPROBE_CONF..."
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Would backup file: $MODPROBE_CONF (if exists)"
        log_dryrun "Would record in manifest: [graphics] $MODPROBE_CONF"
        log_dryrun "Install -D -m 0644 $ROOT_DIR/power/modprobe.d/99-hp-chell-power.conf -> $MODPROBE_CONF (or embedded options)"
    else
        backup_file_manifest_aware "$MODPROBE_CONF" "graphics"
        sudo mkdir -p "$(dirname "$MODPROBE_CONF")"
        # Prefer source file if present, else embedded fallback
        if [ -f "$ROOT_DIR/power/modprobe.d/99-hp-chell-power.conf" ]; then
            sudo install -D -m 0644 "$ROOT_DIR/power/modprobe.d/99-hp-chell-power.conf" "$MODPROBE_CONF"
        else
            sudo bash -c "cat > '$MODPROBE_CONF'" << 'CONF_EOF'
# HP Chromebook 13 G1 (Chell) Graphics & Wireless Tuning
options i915 enable_psr=0 enable_fbc=0 enable_dc=0
options iwlwifi power_save=1 uapsd_disable=0
CONF_EOF
            sudo chmod 644 "$MODPROBE_CONF"
        fi
        log_success "Installed $MODPROBE_CONF"
    fi
fi

# 3. Check CDCLK frequency status
if [ -n "$cdclk_khz" ] && [ "$cdclk_khz" -lt 400000 ] 2> /dev/null; then
    log_warn "CDCLK is ${cdclk_khz} kHz (< 450 MHz target). Triggering DPMS cycle..."
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Would trigger DPMS cycle (skipped in dry-run)"
    else
        cycle_dpms
    fi
else
    log_success "CDCLK is optimal (${cdclk_khz} kHz)."
fi

# 4. Prompt / enable persistent service
if [ ! -f "/etc/systemd/system/chell-cdclk-fix.service" ]; then
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Would install chell-cdclk-fix.service (not present)"
    else
        install_autofix_service
    fi
fi

log_success "Graphics configuration and verification completed."
