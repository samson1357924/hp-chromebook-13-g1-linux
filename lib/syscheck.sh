#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# lib/syscheck.sh - Hardware & Firmware Compatibility Pre-flight Checks (Chell / AVS)

if [ -n "${_LIB_SYSCHECK_SH_LOADED:-}" ]; then
    return 0
fi
_LIB_SYSCHECK_SH_LOADED=1

SCRIPT_DIR_SYSCHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/logger.sh
source "$SCRIPT_DIR_SYSCHECK/logger.sh"

check_dmi_board() {
    local board_name="Unknown"
    local product_name="Unknown"
    local sys_vendor="Unknown"

    if [ -f /sys/class/dmi/id/board_name ]; then
        board_name="$(cat /sys/class/dmi/id/board_name 2> /dev/null || echo 'Unknown')"
    fi
    if [ -f /sys/class/dmi/id/product_name ]; then
        product_name="$(cat /sys/class/dmi/id/product_name 2> /dev/null || echo 'Unknown')"
    fi
    if [ -f /sys/class/dmi/id/sys_vendor ]; then
        sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2> /dev/null || echo 'Unknown')"
    fi

    log_info "Detected Hardware:"
    log_info "  - Vendor:  $sys_vendor"
    log_info "  - Product: $product_name"
    log_info "  - Board:   $board_name"

    # Chell / Glados / Lars family detection (case-insensitive)
    local board_lc product_lc
    board_lc=$(echo "$board_name" | tr '[:upper:]' '[:lower:]')
    product_lc=$(echo "$product_name" | tr '[:upper:]' '[:lower:]')
    case "$board_lc" in
        *dratini* | *chell* | *jinlon* | *hatch* | *glados* | *lars*)
            log_success "Target Chromebook board ($board_name) matches HP Chromebook 13 G1 / Chell platform."
            return 0
            ;;
        *)
            case "$product_lc" in
                *dratini* | *chell* | *hp*chromebook*13*g1* | *hp*pro*c640* | *hatch* | *glados* | *lars*)
                    log_success "Target device product ($product_name) matches HP Chromebook 13 G1."
                    return 0
                    ;;
                *)
                    log_warn "Board '$board_name' / Product '$product_name' is not Chell/Hatch. Generic Chromebook compatibility logic will be applied."
                    return 1
                    ;;
            esac
            ;;
    esac
}

# ---- AVS (Chell) checks ----

check_avs_audio_modules() {
    local mods=(snd_soc_avs snd_soc_avs_ssm4567 snd_soc_avs_nau8825 snd_soc_avs_dmic snd_soc_avs_hdaudio)
    local missing=0
    for m in "${mods[@]}"; do
        if lsmod | grep -qw "$m"; then
            log_success "AVS module loaded: $m"
        else
            log_warn "AVS module NOT loaded: $m"
            missing=1
        fi
    done
    if [ "$missing" -eq 0 ]; then
        return 0
    else
        log_warn "Some AVS modules not loaded. Check kernel config CONFIG_SND_SOC_INTEL_AVS."
        return 1
    fi
}

check_avs_firmware_files() {
    local found=0
    if ls /lib/firmware/intel/avs/*.zst 1> /dev/null 2>&1; then
        found=1
    fi
    if ls /lib/firmware/intel/avs/skl/*.zst 1> /dev/null 2>&1; then
        found=1
    fi
    if [ "$found" -eq 1 ]; then
        log_success "AVS firmware present in /lib/firmware/intel/avs/ (incl. skl/dsp_basefw.bin.zst)"
        return 0
    else
        log_warn "AVS firmware not found in /lib/firmware/intel/avs/. Install linux-firmware."
        return 1
    fi
}

check_avs_mixer() {
    if amixer -c4 cget name='DSP Volume' 2> /dev/null | grep -q "values=0"; then
        log_warn "Card 4 DSP Volume is 0 (muted) - run audio/install-audio.sh"
        return 1
    else
        log_success "Card 4 DSP Volume OK"
        return 0
    fi
}

check_cros_ec_device() {
    if [ -e /dev/cros_ec ] || [ -e /dev/cros-ec ]; then
        log_success "ChromeOS EC device node present."
        return 0
    else
        log_warn "ChromeOS EC device node not found (/dev/cros_ec). Is cros_ec_chardev loaded?"
        return 1
    fi
}

# ---- Deprecated wrappers for backward compatibility (Dratini/SOF era) ----

check_cros_fp_device() {
    log_warn "check_cros_fp_device is deprecated for Chell (no fingerprint hardware)."
    check_cros_ec_device
}

check_sof_audio_modules() {
    log_warn "check_sof_audio_modules is deprecated for Chell (uses AVS, not SOF)."
    check_avs_audio_modules
}

check_sof_firmware_files() {
    log_warn "check_sof_firmware_files is deprecated for Chell (uses AVS)."
    check_avs_firmware_files
}
