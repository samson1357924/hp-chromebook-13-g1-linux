#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/detect-hardware.sh - Comprehensive Hardware Diagnostic for HP Chromebook 13 G1 (Chell / AVS)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/logger.sh
source "$ROOT_DIR/lib/logger.sh"
# shellcheck source=lib/distro.sh
source "$ROOT_DIR/lib/distro.sh"
# shellcheck source=lib/syscheck.sh
source "$ROOT_DIR/lib/syscheck.sh"

run_diagnostic() {
    log_section "HP Chromebook 13 G1 (Google Chell) Full Diagnostic Report"

    # 1. System & Firmware
    log_step 1 6 "System & OS Identification"
    log_info "OS / Distro  : $DISTRO_NAME ($DISTRO_FAMILY, ID: $DISTRO_ID)"
    log_info "Kernel       : $(uname -r)"
    log_info "Cmdline      : $(cat /proc/cmdline 2> /dev/null | cut -c1-180)"
    check_dmi_board || true
    if grep -q "nomodeset" /proc/cmdline 2> /dev/null; then
        log_warn "nomodeset present - i915 disabled, HDMI audio may fail"
    fi
    if lsmod | grep -q "i915"; then log_success "i915 loaded"; else log_warn "i915 not loaded"; fi

    # 2. Audio Subsystem (AVS)
    log_step 2 6 "Audio Subsystem (AVS SSM4567/NAU8825/DMIC/HDA + UCM + PipeWire)"
    check_avs_audio_modules || true
    check_avs_firmware_files || true

    if command -v aplay > /dev/null 2>&1; then
        log_info "ALSA Playback Cards:"
        if LC_ALL=C aplay -l 2> /dev/null | grep -E "^card [0-9]+:"; then
            LC_ALL=C aplay -l 2> /dev/null | grep -E "^card [0-9]+:" | while read -r line; do log_success "  $line"; done
        else
            log_warn "  No ALSA playback cards"
        fi
    fi
    if command -v arecord > /dev/null 2>&1; then
        log_info "ALSA Capture Cards:"
        LC_ALL=C arecord -l 2> /dev/null | grep -E "^card [0-9]+:" | while read -r line; do log_success "  $line"; done || true
    fi

    local ucm_checks=(
        "conf.d/avs_ssm4567/AVS I2S SSM4567.conf"
        "conf.d/avs_ssm4567/avs_ssm4567.conf"
        "conf.d/avs_nau8825/AVS I2S NAU8825.conf"
        "conf.d/avs_nau8825/avs_nau8825.conf"
        "conf.d/avs_dmic/AVS DMIC.conf"
        "conf.d/avs_dmic/avs_dmic.conf"
        "conf.d/avs_hdaudio/AVS HDMI.conf"
        "conf.d/avs_hdaudio/avs_hdaudio.conf"
    )
    log_info "ALSA UCM2 Fallback Status (/usr/share/alsa/ucm2/):"
    local missing_ucm=0
    for rel in "${ucm_checks[@]}"; do
        if [ -e "/usr/share/alsa/ucm2/$rel" ]; then
            log_success "  [OK] $rel -> $(readlink "/usr/share/alsa/ucm2/$rel" 2> /dev/null || echo file)"
        else
            log_warn "  [MISSING] $rel"
            missing_ucm=1
        fi
    done
    [ "$missing_ucm" = 0 ] || log_info "  Tip: Run 'sudo ./audio/install-audio.sh --install' to fix UCM fallbacks."

    if command -v wpctl > /dev/null 2>&1; then
        log_info "PipeWire Routing (Sinks section):"
        if wpctl status 2> /dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -qi "ssm4567"; then
            log_success "  PipeWire Speaker sink (SSM4567) active in Sinks section"
        else
            log_warn "  Speaker sink (SSM4567) not found in Sinks section"
        fi
        log_info "  Default sink: $(wpctl status 2> /dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -E '\*.*alsa' | head -n1 | sed 's/^[[:space:]]*//')"
    fi
    if command -v alsaucm > /dev/null 2>&1; then
        log_info "UCM verbs:"
        for c in 4 3 0 2; do
            if alsaucm -c "hw:$c" dump text 2>&1 | grep -q "Verb.HiFi"; then
                log_success "  hw:$c Verb.HiFi OK"
            else
                log_warn "  hw:$c Verb.HiFi missing"
            fi
        done
    fi
    check_avs_mixer || true

    # 3. EC & Battery (no fingerprint on Chell)
    log_step 3 6 "ChromeOS EC & Battery"
    check_cros_ec_device || true
    if [ -d /sys/class/power_supply/BAT0 ]; then
        local bat_status bat_cap
        bat_status="$(cat /sys/class/power_supply/BAT0/status 2> /dev/null || echo Unknown)"
        bat_cap="$(cat /sys/class/power_supply/BAT0/capacity 2> /dev/null || echo Unknown)"
        log_success "Battery BAT0: ${bat_cap}% ($bat_status)"
    fi
    ls -la /dev/cros_* 2> /dev/null | while read -r line; do log_info "  $line"; done || true

    # 4. Keyboard
    log_step 4 6 "Keyboard Top-Row Mapping"
    if [ -f /etc/udev/hwdb.d/90-chromebook-keyboard.hwdb ]; then
        log_success "  90-chromebook-keyboard.hwdb installed"
        if grep -qi "chell" /etc/udev/hwdb.d/90-chromebook-keyboard.hwdb 2> /dev/null; then
            log_success "  hwdb contains Chell DMI match"
        else
            log_warn "  hwdb missing Chell DMI match - update needed"
        fi
    else
        log_warn "  Custom keyboard hwdb not deployed. Run './setup.sh --keyboard'"
    fi
    if systemctl is-active --quiet keyd 2> /dev/null; then
        log_success "  keyd daemon running"
    fi

    # 5. Power & Battery Management
    log_step 5 6 "Power Management & Suspend"
    if [ -f /sys/power/mem_sleep ]; then
        log_info "mem_sleep: $(cat /sys/power/mem_sleep)"
    fi
    if [ -f /etc/wireplumber/wireplumber.conf.d/50-disable-suspend.conf ]; then
        log_success "  WirePlumber anti-pop config present"
    fi
    if [ -f /etc/wireplumber/wireplumber.conf.d/50-avs-chell.conf ]; then
        log_success "  WirePlumber AVS priority config present"
    fi

    # 6. Summary
    log_step 6 6 "Diagnostic Summary"
    log_info "Diagnostic complete! Log: $LOG_FILE"
    log_info "For audio fix: sudo ./audio/install-audio.sh --install"
    log_info "For report: ./audio/diagnose-audio.sh -o /tmp/audio-report.txt"
}

run_diagnostic
