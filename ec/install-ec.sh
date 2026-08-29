#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# ec/install-ec.sh - ChromeOS EC Tool & Battery Protection Installer for HP Chromebook 13 G1
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=lib/distro.sh
source "$ROOT_DIR/lib/distro.sh"
# shellcheck source=lib/backup.sh
source "$ROOT_DIR/lib/backup.sh"
# shellcheck source=lib/syscheck.sh
source "$ROOT_DIR/lib/syscheck.sh"

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --install, -i                Install c640-ec-control utility (default)"
    echo "  --enable-battery-limit [PCT] Enable automatic battery protection service and sleep hook (default 90, range 20-95)"
    echo "  --battery-limit PCT          Set battery limit for next enable (implies --enable-battery-limit if service not yet enabled)"
    echo "  --enable-kbd-follow-idle     Enable optional keyboard backlight follow-screen-dim (user service, opt-in)"
    echo "  --uninstall, -u              Uninstall EC tools and services"
    echo "  --dry-run, -n                Preview steps without execution"
    echo "  --help, -h                   Show this help message"
}

install_ec_tools() {
    log_section "Installing ChromeOS EC Utilities for HP Chromebook 13 G1 ($DISTRO_NAME)"
    check_dmi_board || true

    local bin_dst="/usr/local/bin/c640-ec-control"
    local bin_src="$ROOT_DIR/scripts/c640-ec-control.sh"

    log_step 1 3 "Installing c640-ec-control to $bin_dst..."
    backup_file_manifest_aware "$bin_dst" "ec"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Install -D -m 0755 $bin_src -> $bin_dst"
    else
        sudo install -D -m 0755 "$bin_src" "$bin_dst"
        log_success "Installed $bin_dst"
    fi

    # Install runtime libraries required by c640-ec-control (logger + syscheck).
    # Without these the installed binary fails on every boot (missing libs).
    local lib_dst_dir="/usr/local/lib/c640-ec"
    log_step 2 3 "Installing runtime libraries to $lib_dst_dir..."
    local lib_files=("logger.sh" "syscheck.sh")
    for lib in "${lib_files[@]}"; do
        local lib_dst="$lib_dst_dir/$lib"
        backup_file_manifest_aware "$lib_dst" "ec"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_dryrun "Install -D -m 0644 $ROOT_DIR/lib/$lib -> $lib_dst"
        else
            sudo install -D -m 0644 "$ROOT_DIR/lib/$lib" "$lib_dst"
            log_success "Installed $lib_dst"
        fi
    done

    # Deploy bundled ectool if the user placed one in ec/bin/ (optional)
    if [ -f "$ROOT_DIR/ec/bin/ectool" ]; then
        local ectool_dst="/usr/local/bin/ectool"
        backup_file_manifest_aware "$ectool_dst" "ec"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_dryrun "Install -D -m 0755 $ROOT_DIR/ec/bin/ectool -> $ectool_dst"
        else
            sudo install -D -m 0755 "$ROOT_DIR/ec/bin/ectool" "$ectool_dst"
            log_success "Installed $ectool_dst"
        fi
    fi

    # Install udev rules for /dev/cros_ec and keyboard backlight
    local udev_dst="/etc/udev/rules.d/60-cros-ec.rules"
    local udev_kbd_dst="/etc/udev/rules.d/61-chromeos-kbd-backlight.rules"
    local udev_kbd_src="$SCRIPT_DIR/61-chromeos-kbd-backlight.rules"
    backup_file_manifest_aware "$udev_dst" "ec"
    backup_file_manifest_aware "$udev_kbd_dst" "ec"
    log_step 3 3 "Installing udev rules for /dev/cros_ec and kbd_backlight..."
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Install 60-cros-ec.rules and 61-chromeos-kbd-backlight.rules"
    else
        sudo mkdir -p "$(dirname "$udev_dst")"
        echo 'KERNEL=="cros_ec", SUBSYSTEM=="misc", GROUP="plugdev", MODE="0660", TAG+="uaccess"' | sudo tee "$udev_dst" > /dev/null
        if [ -f "$udev_kbd_src" ]; then
            sudo install -D -m 0644 "$udev_kbd_src" "$udev_kbd_dst"
        else
            # Fallback inline if source missing (manual install)
            sudo mkdir -p "$(dirname "$udev_kbd_dst")"
            echo 'SUBSYSTEM=="leds", KERNEL=="chromeos::kbd_backlight", TAG+="uaccess", TAG+="seat"' | sudo tee "$udev_kbd_dst" > /dev/null
            echo 'SUBSYSTEM=="leds", KERNEL=="chromeos::kbd_backlight", GROUP="plugdev", MODE="0660"' | sudo tee -a "$udev_kbd_dst" > /dev/null
        fi

        # Ensure plugdev group exists and add user
        if ! getent group plugdev > /dev/null 2>&1; then
            sudo groupadd plugdev 2> /dev/null || true
        fi
        local real_user
        real_user="$(get_real_user)"
        if [ -n "$real_user" ] && [ "$real_user" != "root" ]; then
            if id -u "$real_user" > /dev/null 2>&1; then
                local was_member=0
                id -nG "$real_user" 2> /dev/null | tr ' ' '\n' | grep -qx "plugdev" && was_member=1
                sudo usermod -aG plugdev "$real_user" || true
                manifest_add_group "plugdev" "$real_user" "ec" "$was_member"
            else
                log_warn "User '$real_user' does not exist; skipping plugdev membership."
            fi
        fi

        sudo udevadm control --reload-rules 2> /dev/null || true
        sudo udevadm trigger --subsystem-match=misc 2> /dev/null || true
        sudo udevadm trigger --subsystem-match=leds 2> /dev/null || true
        [ -e /dev/cros_ec ] && sudo chmod 0660 /dev/cros_ec 2> /dev/null || true
        # 0660 via plugdev + uaccess for leds; persistent after reboot via udev,
        # transient chmod for immediate use. Requires re-login for new group.
        log_success "Configured udev access for /dev/cros_ec and chromeos::kbd_backlight."
        if [ -n "${real_user:-}" ] && [ "${was_member:-1}" = "0" ] 2> /dev/null; then
            log_warn "User '$real_user' added to plugdev; re-login or 'newgrp plugdev' required for kbd_backlight without sudo."
        fi
    fi

    log_section "c640-ec-control installed successfully! 🔋"
    echo "You can now run:"
    echo "    c640-ec-control status            # (legacy name, kept for compatibility)"
    echo "    c640-ec-control battery-limit 90  # binary retains c640 prefix for backward compat"
}

enable_battery_service() {
    local pct="${1:-90}"
    if ! [[ "$pct" =~ ^[0-9]+$ ]] || [ "$pct" -lt 20 ] || [ "$pct" -gt 95 ]; then
        log_error "Battery limit must be 20-95 (got: $pct)."
        exit 1
    fi
    log_section "Enabling ${pct}% Battery Protection Service & Sleep Hook"
    local srv_dst="/etc/systemd/system/c640-battery-limit.service"
    local srv_src="$SCRIPT_DIR/systemd/c640-battery-limit.service"
    local sleep_dst="/usr/lib/systemd/system-sleep/c640-ec-sleep.sh"
    local sleep_src="$SCRIPT_DIR/systemd/c640-ec-sleep.sh"
    local default_file="/etc/default/c640-battery-limit"

    # Deploy system-sleep hook for instant resume protection
    if [ -f "$sleep_src" ]; then
        backup_file_manifest_aware "$sleep_dst" "ec"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_dryrun "Install -D -m 0755 $sleep_src -> $sleep_dst"
        else
            sudo install -D -m 0755 "$sleep_src" "$sleep_dst"
            log_success "Installed $sleep_dst (resume hook)"
        fi
    fi

    if [ -f "$srv_src" ]; then
        backup_file_manifest_aware "$srv_dst" "ec"
        backup_file_manifest_aware "$default_file" "ec"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_dryrun "Deploy and enable $srv_dst with BATTERY_LIMIT=$pct"
            log_dryrun "Write BATTERY_LIMIT=$pct to $default_file"
        else
            sudo install -D -m 0644 "$srv_src" "$srv_dst"
            # Preserve existing comments; update or add BATTERY_LIMIT
            if [ -f "$default_file" ] && grep -q "^BATTERY_LIMIT=" "$default_file" 2> /dev/null; then
                sudo sed -i "s/^BATTERY_LIMIT=.*/BATTERY_LIMIT=$pct/" "$default_file"
            else
                echo "BATTERY_LIMIT=$pct" | sudo tee -a "$default_file" > /dev/null
            fi
            # Ensure service reads the new limit
            manifest_add_service "c640-battery-limit.service" "ec"
            sudo systemctl daemon-reload
            sudo systemctl enable --now c640-battery-limit.service
            # One-shot eval to apply immediately without waiting 30s
            sudo /usr/local/bin/c640-ec-control battery-eval "$pct" 2> /dev/null || true
            log_success "${pct}% Battery protection service and resume hook enabled! (BATTERY_LIMIT=$pct in $default_file)"
            log_info "Check: cat /sys/class/power_supply/BAT0/charge_behaviour (expect [inhibit-charge] when >=${pct}%)"
            log_info "If charging past ${pct}%, discharge below ${pct}% then re-plug to test inhibit."
        fi
    fi
}

uninstall_ec_tools() {
    log_section "Uninstalling ChromeOS EC Utilities"
    if [ "${DRY_RUN:-0}" != "1" ]; then
        if [ -x "/usr/local/bin/c640-ec-control" ]; then
            /usr/local/bin/c640-ec-control battery-full 2> /dev/null || true
            /usr/local/bin/c640-ec-control fan-auto 2> /dev/null || true
        fi
        sudo systemctl disable --now c640-battery-limit.service 2> /dev/null || true
        # Optional kbd follow idle cleanup (user service, not tracked in manifest)
        local real_user
        real_user="$(get_real_user)"
        if [ -n "$real_user" ]; then
            sudo -u "$real_user" systemctl --user disable --now kbd-backlight-follow-idle.service 2> /dev/null || true
            local user_sd
            user_sd="$(getent passwd "$real_user" | cut -d: -f6)/.config/systemd/user/kbd-backlight-follow-idle.service"
            [ -f "$user_sd" ] && rm -f "$user_sd" 2> /dev/null || true
            sudo rm -f /usr/local/bin/kbd-follow-idle.sh 2> /dev/null || true
        fi
    fi

    rollback_component "ec"
    remove_group_membership "plugdev" "$(get_real_user)" "ec"

    if [ "${DRY_RUN:-0}" != "1" ]; then
        sudo systemctl daemon-reload
        # Reload user daemon if kbd follow was enabled
        sudo -u "$(get_real_user)" systemctl --user daemon-reload 2> /dev/null || true
    fi
    log_success "EC utilities removed."
}

ACTION="install"
ENABLE_BATTERY=0
BATTERY_PCT="90"
ENABLE_KBD_FOLLOW=0

while [ $# -gt 0 ]; do
    case "$1" in
        --install | -i)
            ACTION="install"
            shift
            ;;
        --enable-battery-limit)
            ENABLE_BATTERY=1
            # Optional numeric argument 20-95
            if [ -n "${2:-}" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                if [ "$2" -lt 20 ] || [ "$2" -gt 95 ]; then
                    log_error "--enable-battery-limit argument must be 20-95 (got: $2)"
                    exit 1
                fi
                BATTERY_PCT="$2"
                shift
            fi
            shift
            ;;
        --battery-limit)
            if [ -z "${2:-}" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "--battery-limit requires a numeric argument 20-95"
                exit 1
            fi
            if [ "$2" -lt 20 ] || [ "$2" -gt 95 ]; then
                log_error "--battery-limit must be 20-95 (got: $2)"
                exit 1
            fi
            BATTERY_PCT="$2"
            ENABLE_BATTERY=1
            shift 2
            ;;
        --enable-kbd-follow-idle)
            ENABLE_KBD_FOLLOW=1
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
        --help | -h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

enable_kbd_follow_idle() {
    local src_dir="$SCRIPT_DIR/systemd/user"
    # Fallback to power/systemd/user if ec copy missing (canonical is power/)
    if [ ! -f "$src_dir/kbd-backlight-follow-idle.service" ] && [ -f "$ROOT_DIR/power/systemd/user/kbd-backlight-follow-idle.service" ]; then
        src_dir="$ROOT_DIR/power/systemd/user"
    fi
    local script_src="$SCRIPT_DIR/../power/kbd-follow-idle.sh"
    # Fallback to power/ if not in ec/systemd/user
    if [ ! -f "$script_src" ]; then
        script_src="$ROOT_DIR/power/kbd-follow-idle.sh"
    fi
    if [ ! -f "$script_src" ]; then
        log_warn "kbd-follow-idle.sh not found; skip."
        return 0
    fi
    log_section "Enabling optional keyboard backlight follow-screen-dim (user service)"
    local real_user
    real_user="$(get_real_user)"
    if [ -z "$real_user" ] || [ "$real_user" = "root" ]; then
        log_warn "Unable to detect non-root user for kbd-follow-idle user service; skipping (run via sudo from your user)."
        return 0
    fi
    if ! id -u "$real_user" > /dev/null 2>&1; then
        log_warn "User '$real_user' does not exist; skipping kbd-follow-idle."
        return 0
    fi
    local user_home
    user_home="$(getent passwd "$real_user" | cut -d: -f6)"
    if [ -z "$user_home" ] || [ ! -d "$user_home" ]; then
        log_warn "Home for '$real_user' not found; skipping."
        return 0
    fi
    local user_systemd_dir="$user_home/.config/systemd/user"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Install kbd-follow-idle.sh and enable user service"
        return 0
    fi
    sudo -u "$real_user" mkdir -p "$user_systemd_dir" 2> /dev/null || mkdir -p "$user_systemd_dir" 2> /dev/null || true
    # Install script to /usr/local/bin (track backup/manifest)
    backup_file_manifest_aware "/usr/local/bin/kbd-follow-idle.sh" "ec"
    sudo install -D -m 0755 "$script_src" /usr/local/bin/kbd-follow-idle.sh
    # Install user service if present
    if [ -f "$src_dir/kbd-backlight-follow-idle.service" ]; then
        sudo -u "$real_user" mkdir -p "$user_systemd_dir"
        # Use manual cp to user dir (systemd --user)
        if [ -w "$user_systemd_dir" ]; then
            cp "$src_dir/kbd-backlight-follow-idle.service" "$user_systemd_dir/" 2> /dev/null || sudo cp "$src_dir/kbd-backlight-follow-idle.service" "$user_systemd_dir/"
        else
            sudo -u "$real_user" cp "$src_dir/kbd-backlight-follow-idle.service" "$user_systemd_dir/" 2> /dev/null || true
        fi
        sudo -u "$real_user" systemctl --user daemon-reload 2> /dev/null || true
        sudo -u "$real_user" systemctl --user enable --now kbd-backlight-follow-idle.service 2> /dev/null || log_warn "Enable user service requires re-login: systemctl --user enable --now kbd-backlight-follow-idle.service"
        log_success "Keyboard follow-idle enabled (opt-in). Disable: systemctl --user disable --now kbd-backlight-follow-idle.service"
    fi
}

case "$ACTION" in
    install)
        install_ec_tools
        if [ "$ENABLE_BATTERY" = "1" ]; then
            enable_battery_service "$BATTERY_PCT"
        fi
        if [ "$ENABLE_KBD_FOLLOW" = "1" ]; then
            enable_kbd_follow_idle
        fi
        ;;
    uninstall)
        uninstall_ec_tools
        ;;
esac
