#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# audio/install-audio.sh - AVS Audio Enablement for HP Chromebook 13 G1 (Chell)
# Fixes: UCM fallback symlinks, PCM index, mixer unmute, WirePlumber priority & suspend
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
source "$ROOT_DIR/lib/syscheck.sh" || true

UCM_DST="/usr/share/alsa/ucm2"
WP_DST="/etc/wireplumber/wireplumber.conf.d"
WP_SRC_DISABLE="$ROOT_DIR/power/wireplumber/50-disable-suspend.conf"
WP_SRC_AVS="$SCRIPT_DIR/wireplumber/50-avs-chell.conf"

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --install, -i      Fix UCM/mixer/WirePlumber for Chell AVS (default)"
    echo "  --check, -c        Check audio driver and hardware status"
    echo "  --uninstall, -u    Rollback audio changes via manifest"
    echo "  --dry-run, -n      Preview changes without modifying the system"
    echo "  --help, -h         Show this help message"
}

# ---- AVS preflight helpers (independent of lib/syscheck) ----
check_avs_modules_local() {
    local mods=(snd_soc_avs snd_soc_avs_ssm4567 snd_soc_avs_nau8825 snd_soc_avs_dmic snd_soc_avs_hdaudio)
    local missing=0
    for m in "${mods[@]}"; do
        if lsmod | grep -q "$m"; then
            log_success "  Module loaded: $m"
        else
            log_warn "  Module NOT loaded: $m"
            missing=1
        fi
    done
    return $missing
}

check_avs_firmware_local() {
    local fw
    fw=$(ls /lib/firmware/intel/avs/*.bin* /lib/firmware/intel/avs/skl/*.bin* 2> /dev/null | head -n1 || true)
    if [ -n "$fw" ]; then
        log_success "  AVS firmware present: $(ls /lib/firmware/intel/avs/ 2> /dev/null | tr '\n' ' ' | cut -c1-120)"
        return 0
    else
        log_warn "  AVS firmware not found in /lib/firmware/intel/avs/ (install linux-firmware)"
        return 1
    fi
}

check_audio_status() {
    log_section "HP Chromebook 13 G1 (Chell) AVS Audio Status"
    check_dmi_board || true
    log_info "AVS Kernel Modules:"
    check_avs_modules_local || true
    log_info "AVS Firmware:"
    check_avs_firmware_local || true

    log_info "ALSA Sound Cards:"
    if command -v aplay > /dev/null 2>&1; then
        LC_ALL=C aplay -l 2> /dev/null | grep -E "^card [0-9]+:" | while read -r line; do log_info "  $line"; done || log_warn "No sound cards detected."
    fi
    if command -v arecord > /dev/null 2>&1; then
        LC_ALL=C arecord -l 2> /dev/null | grep -E "^card [0-9]+:" | while read -r line; do log_info "  $line"; done || true
    fi

    log_info "UCM Fallback Symlinks ($UCM_DST/conf.d):"
    local checks=(
        "avs_ssm4567/AVS I2S SSM4567.conf"
        "avs_ssm4567/avs_ssm4567.conf"
        "avs_nau8825/AVS I2S NAU8825.conf"
        "avs_nau8825/avs_nau8825.conf"
        "avs_dmic/AVS DMIC.conf"
        "avs_dmic/avs_dmic.conf"
        "avs_hdaudio/AVS HDMI.conf"
        "avs_hdaudio/avs_hdaudio.conf"
    )
    local miss=0
    for rel in "${checks[@]}"; do
        if [ -e "$UCM_DST/conf.d/$rel" ]; then
            log_success "  Found: conf.d/$rel -> $(readlink "$UCM_DST/conf.d/$rel" 2> /dev/null || echo file)"
        else
            log_warn "  Missing: conf.d/$rel"
            miss=1
        fi
    done

    log_info "UCM PCM Index (should be hw:\${CardId},0):"
    for f in "$UCM_DST/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf" "$UCM_DST/Intel/avs/avs_nau8825/avs_nau8825-HiFi.conf"; do
        if [ -f "$f" ]; then
            if grep -q 'hw:${CardId},1' "$f" 2> /dev/null; then
                log_warn "  $f still contains hw:\${CardId},1 (needs fix)"
            else
                log_success "  $f PCM index OK"
            fi
        fi
    done

    log_info "ALSA Mixers:"
    for c in 4 3 0; do
        if amixer -c"$c" info > /dev/null 2>&1; then
            log_info "  Card $c: $(cat /proc/asound/card$c/id 2> /dev/null) - $(amixer -c"$c" scontrols 2> /dev/null | head -n 3 | tr '\n' ';')"
        fi
    done
    if amixer -c4 cget name='DSP Volume' 2> /dev/null | grep -q "values=0"; then
        log_warn "  Card 4 DSP Volume is 0 (muted)!"
    else
        log_success "  Card 4 DSP Volume non-zero"
    fi

    log_info "WirePlumber Configs:"
    for f in "$WP_DST/50-avs-chell.conf" "$WP_DST/50-disable-suspend.conf"; do
        if [ -f "$f" ]; then log_success "  Found: $f"; else log_warn "  Missing: $f"; fi
    done

    if command -v wpctl > /dev/null 2>&1; then
        log_info "PipeWire Sinks/Sources:"
        wpctl status 2> /dev/null | sed -n '/Audio/,/Video/p' | head -n 40 | while read -r line; do log_info "  $line"; done || true
        if wpctl status 2> /dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -qi "ssm4567"; then
            log_success "  PipeWire Speaker sink (SSM4567) active"
        else
            log_warn "  Speaker sink (SSM4567) not found - check UCM/WirePlumber"
        fi
    fi

    if command -v alsaucm > /dev/null 2>&1; then
        log_info "UCM verb check:"
        for card in 4 3 0 2; do
            if alsaucm -c "hw:$card" dump text 2>&1 | grep -q "Verb.HiFi"; then
                log_success "  hw:$card Verb.HiFi OK"
            else
                log_warn "  hw:$card Verb.HiFi missing (UCM not loaded)"
            fi
        done
    fi
    return $miss
}

uninstall_audio() {
    log_section "Uninstalling Chell AVS Audio Configs"
    rollback_component "audio"
    # Extra cleanup for empty conf.d dirs that were never tracked (if user manually created)
    if [ "${DRY_RUN:-0}" != "1" ]; then
        for d in avs_ssm4567 avs_nau8825 avs_dmic avs_hdaudio; do
            sudo rmdir --ignore-fail-on-non-empty "$UCM_DST/conf.d/$d" 2> /dev/null || true
        done
        sudo rmdir --ignore-fail-on-non-empty "$UCM_DST/conf.d" 2> /dev/null || true
    else
        log_dryrun "Would prune empty $UCM_DST/conf.d/avs_* if empty"
    fi
    log_success "Audio configs rolled back. Restarting PipeWire/WirePlumber..."
    local real_user real_uid
    real_user="$(get_real_user)"
    real_uid="$(get_real_user_uid)"
    if [ -n "$real_user" ] && [ -d "/run/user/$real_uid" ]; then
        sudo -u "$real_user" XDG_RUNTIME_DIR="/run/user/$real_uid" systemctl --user restart pipewire wireplumber 2> /dev/null || true
    fi
    log_success "Rollback complete."
}

fix_ucm_fallbacks() {
    log_info "Creating UCM fallback symlinks (conf.d) ..."
    # Map: conf.d subdir -> target Intel file
    declare -A MAP=(
        ["avs_ssm4567/Hewlett_Packard-Chell-1.0.conf"]="Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0.conf"
        ["avs_ssm4567/AVS I2S SSM4567.conf"]="Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0.conf"
        ["avs_ssm4567/avs_ssm4567.conf"]="Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0.conf"
        ["avs_nau8825/Hewlett_Packard-Chell-1.0.conf"]="Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0.conf"
        ["avs_nau8825/AVS I2S NAU8825.conf"]="Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0.conf"
        ["avs_nau8825/avs_nau8825.conf"]="Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0.conf"
        ["avs_dmic/AVS DMIC.conf"]="Intel/avs/avs_dmic/DMIC-2ch.conf"
        ["avs_dmic/avs_dmic.conf"]="Intel/avs/avs_dmic/DMIC-2ch.conf"
        ["avs_dmic/Hewlett_Packard-Chell-1.0.conf"]="Intel/avs/avs_dmic/DMIC-2ch.conf"
    )
    # hdaudio is special: directory may not exist
    local hda_target="Intel/avs/hdaudioB0D2/hdaudioB0D2.conf"
    MAP["avs_hdaudio/AVS HDMI.conf"]="$hda_target"
    MAP["avs_hdaudio/avs_hdaudio.conf"]="$hda_target"
    MAP["avs_hdaudio/Hewlett_Packard-Chell-1.0.conf"]="$hda_target"

    for rel in "${!MAP[@]}"; do
        local target_rel="${MAP[$rel]}"
        local dst="$UCM_DST/conf.d/$rel"
        local src="../../$target_rel"
        local src_abs="$UCM_DST/$target_rel"
        if [ ! -f "$src_abs" ]; then
            log_warn "  Skipping $rel: source $src_abs not found in distro package"
            continue
        fi
        backup_file_manifest_aware "$dst" "audio"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_dryrun "ln -sf $src -> $dst"
        else
            sudo mkdir -p "$(dirname "$dst")"
            # Use ln -sf to create/update symlink
            sudo ln -sf "$src" "$dst"
            log_success "  Linked: conf.d/$rel -> $src"
        fi
    done
}

fix_ucm_pcm_index() {
    log_info "Fixing UCM PCM indices (hw:\${CardId},1 -> hw:\${CardId},0) ..."
    local files=(
        "$UCM_DST/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf"
        "$UCM_DST/Intel/avs/avs_nau8825/avs_nau8825-HiFi.conf"
        "$UCM_DST/Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0-HiFi.conf"
        "$UCM_DST/Intel/avs/avs_dmic/DMIC-2ch-HiFi.conf"
        "$UCM_DST/Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf"
    )
    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        if grep -q 'hw:${CardId},1' "$f" 2> /dev/null; then
            backup_file_manifest_aware "$f" "audio"
            if [ "${DRY_RUN:-0}" = "1" ]; then
                log_dryrun "sed -i 's/hw:\${CardId},1/hw:\${CardId},0/g' $f"
            else
                sudo sed -i 's/hw:${CardId},1/hw:${CardId},0/g' "$f"
                log_success "  Fixed PCM index: $f"
            fi
        else
            log_info "  PCM index already correct: $f"
        fi
    done
}

fix_mixers() {
    log_info "Unmuting & setting ALSA mixers ..."
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "amixer -c4 cset name='DSP Volume' 120 / name='Left Master Playback Volume' 191"
        log_dryrun "amixer -c3 cset name='Headphone Volume' 63,63"
        return 0
    fi
    # SSM4567 - speakers (use name= syntax; sset fallback for locale)
    # Note: DSP Volume range is 0..2147483647 (need large value, 120 would be mute)
    if amixer -c4 info > /dev/null 2>&1; then
        sudo -u "$(get_real_user)" amixer -c4 cset name='DSP Volume' 1500000000 2> /dev/null || amixer -c4 cset name='DSP Volume' 1500000000 2> /dev/null || amixer -c4 sset 'DSP' 80% 2> /dev/null || true
        if amixer -c4 cget name='DSP Volume' 2> /dev/null | grep -q "values=0"; then
            amixer -c4 cset name='DSP Volume' 2147483647 2> /dev/null || true
        fi
        amixer -c4 cset name='Left Master Playback Volume' 191 2> /dev/null || amixer -c4 sset 'Left Master' 80% 2> /dev/null || true
        amixer -c4 cset name='Right Master Playback Volume' 191 2> /dev/null || amixer -c4 sset 'Right Master' 80% 2> /dev/null || true
        amixer -c4 cset name='Left Speaker Switch' on 2> /dev/null || true
        amixer -c4 cset name='Right Speaker Switch' on 2> /dev/null || true
        amixer -c4 cset name='Left Amplifier Boost Switch' on 2> /dev/null || true
        amixer -c4 cset name='Right Amplifier Boost Switch' on 2> /dev/null || true
        log_success "  Card 4 (SSM4567) mixer unmuted"
    fi
    # NAU8825 - headphones
    if amixer -c3 info > /dev/null 2>&1; then
        amixer -c3 cset name='Headphone Volume' 63,63 2> /dev/null || amixer -c3 sset 'Headphone' 100% 2> /dev/null || true
        amixer -c3 cset name='Mic Volume' 255 2> /dev/null || amixer -c3 sset 'Mic' 100% 2> /dev/null || true
        log_success "  Card 3 (NAU8825) mixer set"
    fi
    # DMIC (range 0..2147483647, needs large value)
    if amixer -c0 info > /dev/null 2>&1; then
        amixer -c0 cset name='DMIC Volume' 1500000000 2> /dev/null || amixer -c0 sset 'DMIC' 80% 2> /dev/null || amixer -c0 cset name='DMIC Volume' 2147483647 2> /dev/null || true
        log_success "  Card 0 (DMIC) mixer set"
    fi
    sudo alsactl store 2> /dev/null || true
}

deploy_wireplumber() {
    log_info "Deploying WirePlumber configs ..."
    for src in "$WP_SRC_AVS" "$WP_SRC_DISABLE"; do
        [ -f "$src" ] || {
            log_warn "  Source missing: $src"
            continue
        }
        local dst
        dst="$WP_DST/$(basename "$src")"
        backup_file_manifest_aware "$dst" "audio"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_dryrun "install -D -m 0644 $src -> $dst"
        else
            sudo install -D -m 0644 "$src" "$dst"
            log_success "  Installed: $dst"
        fi
    done
    # Clean up legacy per-user WirePlumber override that shadows /etc (review finding)
    local real_user real_uid
    real_user="$(get_real_user)"
    real_uid="$(get_real_user_uid)"
    if [ -n "$real_user" ] && [ "$real_user" != "root" ]; then
        local home_dir
        home_dir=$(getent passwd "$real_user" | cut -d: -f6)
        [ -z "$home_dir" ] && home_dir="/home/$real_user"
        for legacy in "$home_dir/.config/wireplumber/wireplumber.conf.d/50-avs-rules.conf" \
            "$home_dir/.config/wireplumber/wireplumber.conf.d/50-avs-chell.conf"; do
            if [ -f "$legacy" ]; then
                log_warn "  Found legacy per-user WirePlumber config shadowing /etc: $legacy"
                if [ "${DRY_RUN:-0}" = "1" ]; then
                    log_dryrun "Would backup & remove $legacy (shadowing /etc)"
                else
                    local ts
                    ts=$(date '+%Y%m%d_%H%M%S')
                    local backup_path="/var/backups/cros-enablement/${ts}${legacy}"
                    sudo mkdir -p "$(dirname "$backup_path")"
                    sudo cp -a "$legacy" "$backup_path" 2> /dev/null || true
                    # Remove as the owning user to avoid root-owned leftover
                    sudo -u "$real_user" rm -f "$legacy" 2> /dev/null || sudo rm -f "$legacy" 2> /dev/null || true
                    log_success "  Removed legacy per-user config (backed up to $backup_path)"
                fi
            fi
        done
    fi
}

install_audio() {
    log_section "Installing AVS Audio for HP Chromebook 13 G1 (Chell)"

    check_dmi_board || true
    log_info "Preflight: AVS modules & firmware"
    check_avs_modules_local || log_warn "Some AVS modules not loaded - will attempt to continue"
    check_avs_firmware_local || log_warn "AVS firmware check failed - will attempt to continue"

    log_step 1 5 "Fixing UCM fallbacks & PCM indices..."
    fix_ucm_fallbacks
    fix_ucm_pcm_index

    log_step 2 5 "Deploying WirePlumber configs..."
    deploy_wireplumber

    log_step 3 5 "Initializing ALSA controls..."
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "sudo alsactl init"
    else
        sudo alsactl init 2>&1 | head -n 20 || true
        fix_mixers
    fi

    log_step 4 5 "Restarting PipeWire & WirePlumber..."
    local real_user real_uid
    real_user="$(get_real_user)"
    real_uid="$(get_real_user_uid)"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Restart PipeWire & WirePlumber for user $real_user (UID: $real_uid)"
    else
        if [ -n "$real_user" ] && [ -d "/run/user/$real_uid" ]; then
            sudo -u "$real_user" XDG_RUNTIME_DIR="/run/user/$real_uid" systemctl --user restart pipewire wireplumber 2> /dev/null || true
            # Poll for graph rebuild (WirePlumber needs 2-5s)
            for _ in 1 2 3 4 5 6 7 8; do
                if sudo -u "$real_user" XDG_RUNTIME_DIR="/run/user/$real_uid" wpctl status 2> /dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -qi "ssm4567"; then
                    break
                fi
                sleep 1
            done
            log_success "PipeWire & WirePlumber restarted for '$real_user'."
        elif systemctl --user restart wireplumber 2> /dev/null; then
            for _ in 1 2 3 4 5 6 7 8; do
                if wpctl status 2> /dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -qi "ssm4567"; then break; fi
                sleep 1
            done
            log_success "WirePlumber restarted."
        else
            log_info "No active user session; changes will take effect after next login/reboot."
        fi
    fi

    log_step 5 5 "Verifying..."
    if [ "${DRY_RUN:-0}" != "1" ]; then
        if LC_ALL=C aplay -l 2> /dev/null | grep -q "SSM4567"; then
            log_success "ALSA card 'SSM4567' present."
        fi
        if command -v wpctl > /dev/null 2>&1 && wpctl status 2> /dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -qi "ssm4567"; then
            log_success "PipeWire Speaker sink (SSM4567) verified!"
        else
            log_warn "Speaker sink not yet visible - check 'wpctl status' after re-login"
        fi
        # Show default sink from Sinks section only
        local default_sink
        default_sink=$(wpctl status 2> /dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -E '\*.*alsa_output' | head -n1 | sed 's/^[[:space:]]*//')
        if [ -n "$default_sink" ]; then
            log_info "Default sink (Sinks section): $default_sink"
        else
            log_info "Default sink: $(wpctl status 2> /dev/null | grep -E '\*.*alsa_output' | head -n1 | sed 's/^[[:space:]]*//')"
        fi
        log_info "Test: speaker-test -D plughw:4,0 -c2 -l1  (or pw-play /usr/share/sounds/alsa/Front_Left.wav)"
    fi

    log_success "AVS audio configuration complete! 🔊"
}

ACTION="install"
while [ $# -gt 0 ]; do
    case "$1" in
        --install | -i)
            ACTION="install"
            shift
            ;;
        --check | -c)
            ACTION="check"
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

case "$ACTION" in
    install) install_audio ;;
    check) check_audio_status ;;
    uninstall) uninstall_audio ;;
esac
