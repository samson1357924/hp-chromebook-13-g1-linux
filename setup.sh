#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# HP Chromebook 13 G1 (Google Chell) Linux Master Setup Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

# shellcheck source=lib/logger.sh
source "$SCRIPT_DIR/lib/logger.sh"
# shellcheck source=lib/distro.sh
source "$SCRIPT_DIR/lib/distro.sh"
# shellcheck source=lib/backup.sh
source "$ROOT_DIR/lib/backup.sh"
# shellcheck source=lib/syscheck.sh
source "$SCRIPT_DIR/lib/syscheck.sh"

show_banner() {
    echo -e "${CLR_CYAN}${CLR_BOLD}"
    echo "==========================================================="
    echo "   HP Chromebook 13 G1 (Google Chell) Linux Setup          "
    echo "   Skylake-Y Enablement & Pitfall-Avoidance for chell      "
    echo "==========================================================="
    echo -e "${CLR_RESET}"
}

show_menu() {
    show_banner
    echo "Detected Environment:"
    echo "  - OS:      $DISTRO_NAME ($DISTRO_FAMILY)"
    echo "  - Kernel:  $(uname -r)"
    echo "  - Board:   $(cat /sys/class/dmi/id/board_name 2> /dev/null || echo chell)"
    echo "  - User:    $(get_real_user)"
    echo ""
    echo "Select action to perform:"
    echo "  [1] Complete Setup (Keyboard + Audio + Power + EC + Graphics Fix)"
    echo "  [2] Audio Diagnostics Only (AVS SSM4567/NAU8825/DMIC + PipeWire)"
    echo "  [3] Keyboard Top-Row Mapping Only (systemd-hwdb)"
    echo "  [4] Power Management & EC Control (Battery 90% + S3)"
    echo "  [5] Graphics Fix Only (remove nomodeset, enable i915)"
    echo "  [6] Full Hardware & Diagnostics Check"
    echo "  [7] Generate Diagnostic Bundle (sysreport.tar.gz)"
    echo "  [8] Uninstall / Rollback All Components"
    echo "  [0] Exit"
    echo ""
}

show_help() {
    show_banner
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --all, -a            Run complete setup (Keyboard + Audio + Power + EC)"
    echo "  --audio, -u          Diagnose/fix AVS audio (SSM4567/NAU8825)"
    echo "  --keyboard, -k       Install Chromebook top-row mapping"
    echo "  --power, -p          Install power & EC tuning"
    echo "  --ec                 Install ChromeOS EC control utility"
    echo "  --graphics, -g       Fix i915 graphics (remove nomodeset)"
    echo "  --check, -c          Run hardware diagnostic check"
    echo "  --sysreport          Generate sysreport archive"
    echo "  --uninstall          Uninstall and restore configs"
    echo "  --dry-run, -n        Preview without modifying system"
    echo "  --help, -h           Show help"
    echo ""
}

make_executable() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "chmod +x $*"
        return 0
    fi
    chmod +x "$@"
}

run_keyboard() {
    make_executable "$SCRIPT_DIR/keyboard/install-keyboard.sh"
    "$SCRIPT_DIR/keyboard/install-keyboard.sh" --install
}

run_audio() {
    make_executable "$SCRIPT_DIR/audio/install-audio.sh"
    "$SCRIPT_DIR/audio/install-audio.sh" --install
}

run_power() {
    make_executable "$SCRIPT_DIR/power/install-power.sh"
    "$SCRIPT_DIR/power/install-power.sh" --install
}

run_ec() {
    make_executable "$SCRIPT_DIR/ec/install-ec.sh"
    "$SCRIPT_DIR/ec/install-ec.sh" --install
}

run_graphics() {
    make_executable "$SCRIPT_DIR/scripts/fix-graphics.sh"
    "$SCRIPT_DIR/scripts/fix-graphics.sh"
}

run_check() {
    make_executable "$SCRIPT_DIR/scripts/detect-hardware.sh"
    "$SCRIPT_DIR/scripts/detect-hardware.sh"
}

run_sysreport() {
    make_executable "$SCRIPT_DIR/scripts/sysreport.sh"
    "$SCRIPT_DIR/scripts/sysreport.sh"
}

run_uninstall() {
    log_section "Uninstalling All HP Chromebook 13 G1 Components"
    make_executable "$SCRIPT_DIR/keyboard/install-keyboard.sh" \
        "$SCRIPT_DIR/audio/install-audio.sh" \
        "$SCRIPT_DIR/power/install-power.sh" \
        "$SCRIPT_DIR/ec/install-ec.sh" || true
    local failed=0
    "$SCRIPT_DIR/keyboard/install-keyboard.sh" --uninstall || failed=1
    "$SCRIPT_DIR/audio/install-audio.sh" --uninstall || failed=1
    "$SCRIPT_DIR/power/install-power.sh" --uninstall || failed=1
    "$SCRIPT_DIR/ec/install-ec.sh" --uninstall || failed=1
    if [ "$failed" -ne 0 ]; then
        log_error "One or more components failed to uninstall; check log."
        return 1
    fi
    log_success "All components uninstalled."
}

MODE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --all | -a | 1)
            MODE="all"
            shift
            ;;
        --audio | -u | 2)
            MODE="audio"
            shift
            ;;
        --keyboard | -k | --kbd | 3)
            MODE="keyboard"
            shift
            ;;
        --power | -p | 4)
            MODE="power"
            shift
            ;;
        --graphics | -g | 5)
            MODE="graphics"
            shift
            ;;
        --ec)
            MODE="ec"
            shift
            ;;
        --check | -c | --status | 6)
            MODE="check"
            shift
            ;;
        --sysreport | 7)
            MODE="sysreport"
            shift
            ;;
        --uninstall | --rollback | 8)
            MODE="uninstall"
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

if [ -z "$MODE" ]; then
    show_menu
    read -rp "Enter choice [0-8] (default: 1): " choice
    choice="${choice:-1}"
    case "$choice" in
        1) MODE="all" ;;
        2) MODE="audio" ;;
        3) MODE="keyboard" ;;
        4) MODE="power" ;;
        5) MODE="graphics" ;;
        6) MODE="check" ;;
        7) MODE="sysreport" ;;
        8) MODE="uninstall" ;;
        0)
            echo "Exiting."
            exit 0
            ;;
        *)
            log_error "Invalid choice: $choice"
            exit 1
            ;;
    esac
fi

case "$MODE" in
    all)
        log_section "Starting Complete HP Chromebook 13 G1 Enablement"
        run_keyboard
        run_audio
        run_power
        run_ec
        run_graphics
        run_check
        log_success "Complete setup finished! 🎉"
        ;;
    keyboard) run_keyboard ;;
    audio) run_audio ;;
    power) run_power ;;
    ec) run_ec ;;
    graphics) run_graphics ;;
    check) run_check ;;
    sysreport) run_sysreport ;;
    uninstall) run_uninstall ;;
esac
