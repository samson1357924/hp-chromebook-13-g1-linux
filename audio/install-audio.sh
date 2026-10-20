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

# Kernel module parameter that selects the pre-6.16 AVS card names/PCM
# numbering. It exists only on kernels carrying the AVS board-name rework.
# Both variables can be pointed at fixtures by the hermetic tests.
AVS_OBSOLETE_PARAM="${CROS_AVS_OBSOLETE_PARAM_FILE:-/sys/module/snd_soc_avs/parameters/obsolete_card_names}"
AVS_KERNEL_RELEASE="${CROS_AVS_KERNEL_RELEASE:-}"
AVS_MODPROBE_DIR="${CROS_AVS_MODPROBE_DIR:-/etc/modprobe.d}"
AVS_CMDLINE_FILE="${CROS_AVS_CMDLINE_FILE:-/proc/cmdline}"

# UCM files that may carry the front-end PCM index for the Chell AVS cards.
# Printed as a function so tests can override UCM_DST after sourcing.
ucm_pcm_files() {
    printf '%s\n' \
        "$UCM_DST/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf" \
        "$UCM_DST/Intel/avs/avs_nau8825/avs_nau8825-HiFi.conf" \
        "$UCM_DST/Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0-HiFi.conf" \
        "$UCM_DST/Intel/avs/avs_dmic/DMIC-2ch-HiFi.conf" \
        "$UCM_DST/Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf"
}

# Legacy templates ship hw:${CardId},1 (SSM4567/NAU8825 playback and NAU8825
# capture) and hw:${CardId},2 (DMIC capture). The right boundary keeps
# multi-digit indices (,10/,12/,20) from matching.
UCM_STALE_INDEX_RE='hw:\$\{CardId\},[12]([^0-9]|$)'
UCM_ZERO_INDEX_RE='hw:\$\{CardId\},0([^0-9]|$)'

avs_obsolete_override() {
    # Print legacy/new for the LAST explicit obsolete_card_names= setting in
    # the kernel cmdline or modprobe.d, or nothing if absent. Only the AVS
    # module (or an unprefixed cmdline setting) is considered; values are
    # case-insensitive. The kernel cmdline wins over modprobe.d, matching the
    # kernel's module-parameter precedence.
    local token val f line module rest found=""
    local -a tokens rest_tokens
    if [ -r "$AVS_CMDLINE_FILE" ]; then
        read -r -a tokens <<< "$(tr '\n' ' ' < "$AVS_CMDLINE_FILE" 2> /dev/null)"
        for token in "${tokens[@]}"; do
            case "$token" in
                obsolete_card_names=* | snd-soc-avs.obsolete_card_names=* | snd_soc_avs.obsolete_card_names=*)
                    val="${token#*=}"
                    val="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
                    case "$val" in
                        1 | y | yes | on | true) found=legacy ;;
                        0 | n | no | off | false) found=new ;;
                    esac
                    ;;
            esac
        done
    fi
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi
    for f in "$AVS_MODPROBE_DIR"/*.conf; do
        [ -f "$f" ] || continue
        while IFS= read -r line; do
            line="${line%%#*}"
            [[ "$line" =~ ^[[:space:]]*options[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$ ]] || continue
            module="${BASH_REMATCH[1]}"
            rest="${BASH_REMATCH[2]}"
            case "$module" in snd-soc-avs | snd_soc_avs) ;; *) continue ;; esac
            read -r -a rest_tokens <<< "$rest"
            for token in "${rest_tokens[@]}"; do
                case "$token" in
                    obsolete_card_names=*)
                        val="${token#*=}"
                        val="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
                        case "$val" in
                            1 | y | yes | on | true) found=legacy ;;
                            0 | n | no | off | false) found=new ;;
                        esac
                        ;;
                esac
            done
        done < "$f"
    done
    if [ -n "$found" ]; then
        echo "$found"
    fi
    return 0
}

avs_numbering_mode() {
    # Print "legacy" for the pre-6.16 numbering (device 1/2 still valid) or
    # "new" for the 6.16+ renumbering (every AVS FE PCM is device 0).
    # Prefer the module parameter (also covers backports and
    # obsolete_card_names=1); fall back to the kernel release.
    local val rel major minor
    if [ -r "$AVS_OBSOLETE_PARAM" ]; then
        val="$(tr '[:upper:]' '[:lower:]' < "$AVS_OBSOLETE_PARAM" 2> /dev/null | tr -d '[:space:]' || true)"
        case "$val" in
            1 | y | yes | on | true)
                echo legacy
                return 0
                ;;
            0 | n | no | off | false)
                echo new
                return 0
                ;;
        esac
    fi
    # The module may not be loaded yet, so sysfs is unavailable. Honor an
    # explicit modprobe/cmdline override before falling back to the release.
    val="$(avs_obsolete_override)"
    if [ -n "$val" ]; then
        echo "$val"
        return 0
    fi
    rel="${AVS_KERNEL_RELEASE:-$(uname -r 2> /dev/null || true)}"
    major="${rel%%.*}"
    minor="${rel#*.}"
    minor="${minor%%.*}"
    case "$major" in '' | *[!0-9]*) major=0 ;; esac
    case "$minor" in '' | *[!0-9]*) minor=0 ;; esac
    if [ "$major" -gt 6 ] || { [ "$major" -eq 6 ] && [ "$minor" -ge 16 ]; }; then
        echo new
    else
        echo legacy
    fi
}

ucm_pcm_index_of() {
    # First stale index in a file, with the same right boundary as the guard.
    grep -oE "$UCM_STALE_INDEX_RE" "$1" 2> /dev/null \
        | head -n 1 | sed -E 's/.*,([12]).*/\1/' || true
}

wpctl_as_real_user() {
    # $1 = 0 (interactive sudo) or 1 (non-interactive); remaining args go to
    # wpctl. Falls back to the current session when there is no login session.
    local noninteractive="$1"
    shift
    local real_user real_uid me
    local sudo_args=()
    real_user="$(get_real_user 2> /dev/null || true)"
    real_uid="$(get_real_user_uid 2> /dev/null || true)"
    me="$(id -un 2> /dev/null || true)"
    if [ -n "$real_user" ] && [ "$real_user" != "root" ] && [ -d "/run/user/$real_uid" ]; then
        if [ "$real_user" = "$me" ]; then
            XDG_RUNTIME_DIR="/run/user/$real_uid" wpctl "$@" 2> /dev/null || true
        else
            [ "$noninteractive" = "1" ] && sudo_args=(-n)
            sudo "${sudo_args[@]}" -u "$real_user" XDG_RUNTIME_DIR="/run/user/$real_uid" wpctl "$@" 2> /dev/null || true
        fi
    else
        wpctl "$@" 2> /dev/null || true
    fi
}

wpctl_set_default() {
    # Preserve wpctl's exit status so the caller can report a failed pin.
    local id="$1" real_user real_uid me
    real_user="$(get_real_user 2> /dev/null || true)"
    real_uid="$(get_real_user_uid 2> /dev/null || true)"
    me="$(id -un 2> /dev/null || true)"
    if [ -n "$real_user" ] && [ "$real_user" != "root" ] && [ -d "/run/user/$real_uid" ]; then
        if [ "$real_user" = "$me" ]; then
            XDG_RUNTIME_DIR="/run/user/$real_uid" wpctl set-default "$id" 2> /dev/null
        else
            sudo -u "$real_user" XDG_RUNTIME_DIR="/run/user/$real_uid" wpctl set-default "$id" 2> /dev/null
        fi
    else
        wpctl set-default "$id" 2> /dev/null
    fi
}

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
    local cards
    if command -v aplay > /dev/null 2>&1; then
        cards="$(LC_ALL=C aplay -l 2> /dev/null | grep -E "^card [0-9]+:" || true)"
        if [ -n "$cards" ]; then
            while IFS= read -r line; do log_info "  $line"; done <<< "$cards"
        else
            log_warn "  No playback sound cards detected."
        fi
    fi
    if command -v arecord > /dev/null 2>&1; then
        cards="$(LC_ALL=C arecord -l 2> /dev/null | grep -E "^card [0-9]+:" || true)"
        if [ -n "$cards" ]; then
            while IFS= read -r line; do log_info "  $line"; done <<< "$cards"
        else
            log_warn "  No capture sound cards detected."
        fi
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

    log_info "UCM PCM Index:"
    check_ucm_pcm_index || miss=1

    log_info "ALSA Mixers (using ALSA IDs - card numbers are dynamic):"
    for id in SSM4567 NAU8825 DMIC HDMI; do
        if amixer -c"$id" info > /dev/null 2>&1; then
            log_info "  Card $id: $(amixer -c"$id" info 2> /dev/null | head -n1) - $(amixer -c"$id" scontrols 2> /dev/null | head -n 3 | tr '\n' ';')"
        fi
    done
    local dsp_volume
    dsp_volume="$(amixer -cSSM4567 cget name='DSP Volume' 2> /dev/null || true)"
    if ! amixer -cSSM4567 info > /dev/null 2>&1; then
        log_warn "  Card SSM4567 not present; cannot verify DSP Volume"
    elif [ -z "$dsp_volume" ]; then
        log_warn "  Cannot verify DSP Volume on SSM4567 (control missing)"
    elif printf '%s\n' "$dsp_volume" | grep -q "values=0"; then
        log_warn "  SSM4567 DSP Volume is 0 (muted)!"
    else
        log_success "  SSM4567 DSP Volume non-zero"
    fi

    log_info "WirePlumber Configs:"
    for f in "$WP_DST/50-avs-chell.conf" "$WP_DST/50-disable-suspend.conf"; do
        if [ -f "$f" ]; then log_success "  Found: $f"; else log_warn "  Missing: $f"; fi
    done

    if command -v wpctl > /dev/null 2>&1; then
        # Same root-session pitfall as install verification: prefer the real
        # user's session. Node names (wpctl status -n) are authoritative;
        # descriptions are only a fallback because the WirePlumber config
        # that adds "(SSM4567)" may not be loaded yet.
        local _wp_check _wp_names _sink_section
        _wp_check="$(wpctl_as_real_user 1 status)"
        _wp_names="$(wpctl_as_real_user 1 status -n)"
        log_info "PipeWire Sinks/Sources:"
        if [ -n "$_wp_check" ]; then
            printf '%s\n' "$_wp_check" | sed -n '/Audio/,/Video/{/^Video/d;p}' | head -n 40 | while IFS= read -r line; do log_info "  $line"; done
        fi
        _sink_section=""
        if [ -n "$_wp_names" ]; then
            _sink_section="$(printf '%s\n' "$_wp_names" | sed -n '/Sinks:/,/Sources:/p')"
        fi
        if [ -z "$_sink_section" ] && [ -n "$_wp_check" ]; then
            _sink_section="$(printf '%s\n' "$_wp_check" | sed -n '/Sinks:/,/Sources:/p')"
        fi
        if printf '%s\n' "$_sink_section" | grep -qi "ssm4567"; then
            log_success "  PipeWire Speaker sink (SSM4567) active"
        elif [ -n "$_sink_section" ]; then
            log_warn "  Speaker sink (SSM4567) not found - check UCM/WirePlumber"
        else
            log_warn "  Cannot read the PipeWire Sinks section - check PipeWire/WirePlumber"
        fi
    fi

    if command -v alsaucm > /dev/null 2>&1; then
        log_info "UCM verb check (using ALSA IDs):"
        for card in SSM4567 NAU8825 HDMI DMIC; do
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
    if [ ! -f "$MANIFEST_FILE" ]; then
        # Idempotent no-op, matching the other components: a clean system has
        # nothing to roll back and `setup.sh --uninstall --dry-run` must pass.
        log_warn "No install manifest found at $MANIFEST_FILE; nothing to roll back."
        return 0
    fi
    local rc=0
    rollback_component "audio" || rc=1
    if [ "$rc" -ne 0 ]; then
        log_error "Audio rollback failed; not pruning directories or restarting services."
        return "$rc"
    fi
    # Extra cleanup for empty conf.d dirs that were never tracked (if user
    # manually created). Never remove the package-owned conf.d parent: only
    # the avs_* directories that this installer may have created.
    if [ "${DRY_RUN:-0}" != "1" ]; then
        for d in avs_ssm4567 avs_nau8825 avs_dmic avs_hdaudio; do
            sudo rmdir --ignore-fail-on-non-empty "$UCM_DST/conf.d/$d" 2> /dev/null || true
        done
    else
        log_dryrun "Would prune empty $UCM_DST/conf.d/avs_* if empty"
    fi
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Would restart PipeWire/WirePlumber for the real user session"
    else
        log_success "Audio configs rolled back. Restarting PipeWire/WirePlumber..."
        local real_user real_uid
        real_user="$(get_real_user)"
        real_uid="$(get_real_user_uid)"
        if [ -n "$real_user" ] && [ -d "/run/user/$real_uid" ]; then
            sudo -u "$real_user" XDG_RUNTIME_DIR="/run/user/$real_uid" systemctl --user restart pipewire wireplumber 2> /dev/null || true
        fi
        log_success "Rollback complete."
    fi
}

fix_ucm_fallbacks() {
    log_info "Creating UCM fallback symlinks (conf.d) ..."
    local fail=0
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
        if ! backup_file_manifest_aware "$dst" "audio"; then
            log_error "  Failed to back up $dst; not overwriting it"
            fail=1
            continue
        fi
        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_dryrun "ln -sf $src -> $dst"
        elif sudo mkdir -p "$(dirname "$dst")" && sudo ln -sf "$src" "$dst"; then
            log_success "  Linked: conf.d/$rel -> $src"
        else
            log_error "  Failed to link conf.d/$rel -> $src"
            fail=1
        fi
    done

    # Speaker/headset/mic fallbacks are required; HDMI is optional because
    # some AVS variants do not expose hdaudioB0D2.
    local required
    for required in \
        "Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0.conf" \
        "Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0.conf" \
        "Intel/avs/avs_dmic/DMIC-2ch.conf"; do
        if [ ! -f "$UCM_DST/$required" ]; then
            log_error "  Required UCM source missing: $UCM_DST/$required"
            fail=1
        fi
    done
    return "$fail"
}

ucm_file_is_include_only() {
    # A legitimate Include-only UCM fragment has no PCM index. Empty or
    # truncated files are not legitimate and must fail --check.
    [ -s "$1" ] && grep -qE '^[[:space:]]*Include([.[:space:]]|$)' "$1" 2> /dev/null
}

check_ucm_pcm_index() {
    # Returns 0 only when every relevant UCM file matches the active kernel
    # numbering. Missing/unreadable/empty files and unexpected indices are
    # failures: a stale index is exactly the silent-speaker/missing-mic
    # regression.
    local mode f idx miss=0
    mode="$(avs_numbering_mode)"
    log_info "  AVS PCM numbering: $mode"
    while IFS= read -r f; do
        if [ ! -f "$f" ]; then
            log_warn "  Missing UCM file: $f"
            miss=1
            continue
        fi
        if [ ! -r "$f" ]; then
            log_warn "  Cannot read UCM file: $f"
            miss=1
            continue
        fi
        if [ ! -s "$f" ]; then
            log_warn "  Empty UCM file: $f"
            miss=1
            continue
        fi
        if ! grep -qE 'hw:\$\{CardId\},[0-9]+([^0-9]|$)' "$f" 2> /dev/null; then
            if ucm_file_is_include_only "$f"; then
                log_info "  Include-only UCM file (no literal PCM index): $f"
            else
                log_warn "  $f has no PCM index and is not a valid Include-only file"
                miss=1
            fi
            continue
        fi
        if [ "$mode" = "legacy" ]; then
            if grep -qE "$UCM_ZERO_INDEX_RE" "$f" 2> /dev/null; then
                log_warn "  $f uses hw:\${CardId},0 but legacy AVS numbering needs ,1/,2"
                log_warn "  Reinstall alsa-ucm-conf or disable obsolete_card_names before running --install"
                miss=1
            elif grep -qE "$UCM_STALE_INDEX_RE" "$f" 2> /dev/null; then
                log_success "  Legacy PCM index OK: $f"
            else
                log_warn "  $f has a PCM index but none is hw:\${CardId},1|,2"
                miss=1
            fi
            continue
        fi
        if grep -qE "$UCM_STALE_INDEX_RE" "$f" 2> /dev/null; then
            idx="$(ucm_pcm_index_of "$f")"
            log_warn "  $f still contains hw:\${CardId},${idx:-1|2} (needs fix - run with --install)"
            miss=1
        elif grep -qE "$UCM_ZERO_INDEX_RE" "$f" 2> /dev/null; then
            log_success "  PCM index OK (hw:\${CardId},0): $f"
        else
            log_warn "  $f has a PCM index but none is hw:\${CardId},0"
            miss=1
        fi
    done < <(ucm_pcm_files)
    return "$miss"
}

fix_ucm_pcm_index() {
    local mode f fail=0
    mode="$(avs_numbering_mode)"
    if [ "$mode" = "legacy" ]; then
        log_info "Legacy AVS PCM numbering detected; keeping ,1/,2 UCM indices (no rewrite)."
        while IFS= read -r f; do
            if [ ! -f "$f" ]; then
                log_warn "  Missing UCM file: $f"
                fail=1
                continue
            fi
            if [ ! -r "$f" ]; then
                log_warn "  Cannot read UCM file: $f"
                fail=1
                continue
            fi
            if [ ! -s "$f" ]; then
                log_warn "  Empty UCM file: $f"
                fail=1
                continue
            fi
            if ! grep -qE 'hw:\$\{CardId\},[0-9]+([^0-9]|$)' "$f" 2> /dev/null; then
                if ucm_file_is_include_only "$f"; then
                    log_info "  Include-only UCM file (no rewrite): $f"
                else
                    log_warn "  $f has no PCM index and is not a valid Include-only file"
                    fail=1
                fi
                continue
            fi
            if grep -qE "$UCM_ZERO_INDEX_RE" "$f" 2> /dev/null; then
                log_warn "  $f is patched to hw:\${CardId},0 but legacy numbering is active"
                log_warn "  Reinstall alsa-ucm-conf (or disable obsolete_card_names) before using this installer"
                fail=1
            elif grep -qE "$UCM_STALE_INDEX_RE" "$f" 2> /dev/null; then
                log_success "  Legacy PCM index OK: $f"
            else
                log_warn "  $f has a PCM index but none is hw:\${CardId},1|,2"
                fail=1
            fi
        done < <(ucm_pcm_files)
        return "$fail"
    fi
    log_info "Fixing UCM PCM indices (hw:\${CardId},1|,2 -> hw:\${CardId},0) ..."
    while IFS= read -r f; do
        if [ ! -f "$f" ]; then
            log_warn "  Missing UCM file: $f"
            fail=1
            continue
        fi
        if [ ! -r "$f" ]; then
            log_warn "  Cannot read UCM file: $f"
            fail=1
            continue
        fi
        if [ ! -s "$f" ]; then
            log_warn "  Empty UCM file: $f"
            fail=1
            continue
        fi
        if ! grep -qE 'hw:\$\{CardId\},[0-9]+([^0-9]|$)' "$f" 2> /dev/null; then
            if ucm_file_is_include_only "$f"; then
                log_info "  Include-only UCM file (no rewrite): $f"
            else
                log_warn "  $f has no PCM index and is not a valid Include-only file"
                fail=1
            fi
            continue
        fi
        # Boundary required: ,10/,12/,20 are multi-digit indices, not ,1/,2.
        if grep -qE "$UCM_STALE_INDEX_RE" "$f" 2> /dev/null; then
            if ! backup_file_manifest_aware "$f" "audio"; then
                log_error "  Failed to back up $f; not modifying it"
                fail=1
                continue
            fi
            if [ "${DRY_RUN:-0}" = "1" ]; then
                log_dryrun "sed -i -e 's/hw:\${CardId},\([12]\)\([^0-9]\)/hw:\${CardId},0\2/g' -e 's/hw:\${CardId},\([12]\)\$/hw:\${CardId},0/' $(printf '%q' "$f")"
            elif sudo sed -i \
                -e 's/hw:${CardId},\([12]\)\([^0-9]\)/hw:${CardId},0\2/g' \
                -e 's/hw:${CardId},\([12]\)$/hw:${CardId},0/' "$f"; then
                log_success "  Fixed PCM index: $f"
            else
                log_error "  Failed to rewrite PCM index in $f"
                fail=1
            fi
        elif grep -qE "$UCM_ZERO_INDEX_RE" "$f" 2> /dev/null; then
            log_info "  PCM index already correct: $f"
        else
            log_warn "  $f has a PCM index but none is hw:\${CardId},0"
            fail=1
        fi
    done < <(ucm_pcm_files)
    return "$fail"
}

fix_mixers() {
    log_info "Unmuting & setting ALSA mixers (using ALSA IDs) ..."
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "amixer -cSSM4567 cset name='DSP Volume' 1500000000 / name='Left Master Playback Volume' 191"
        log_dryrun "amixer -cNAU8825 cset name='Headphone Volume' 63,63"
        return 0
    fi
    # SSM4567 - speakers (use name= syntax; sset fallback for locale)
    # Note: DSP Volume range is 0..2147483647 (need large value, 120 would be mute)
    if amixer -cSSM4567 info > /dev/null 2>&1; then
        sudo -u "$(get_real_user)" amixer -cSSM4567 cset name='DSP Volume' 1500000000 2> /dev/null || amixer -cSSM4567 cset name='DSP Volume' 1500000000 2> /dev/null || amixer -cSSM4567 sset 'DSP' 80% 2> /dev/null || true
        if amixer -cSSM4567 cget name='DSP Volume' 2> /dev/null | grep -q "values=0"; then
            amixer -cSSM4567 cset name='DSP Volume' 2147483647 2> /dev/null || true
        fi
        amixer -cSSM4567 cset name='Left Master Playback Volume' 191 2> /dev/null || amixer -cSSM4567 sset 'Left Master' 80% 2> /dev/null || true
        amixer -cSSM4567 cset name='Right Master Playback Volume' 191 2> /dev/null || amixer -cSSM4567 sset 'Right Master' 80% 2> /dev/null || true
        amixer -cSSM4567 cset name='Left Speaker Switch' on 2> /dev/null || true
        amixer -cSSM4567 cset name='Right Speaker Switch' on 2> /dev/null || true
        amixer -cSSM4567 cset name='Left Amplifier Boost Switch' on 2> /dev/null || true
        amixer -cSSM4567 cset name='Right Amplifier Boost Switch' on 2> /dev/null || true
        log_success "  SSM4567 mixer unmuted"
    fi
    # NAU8825 - headphones
    if amixer -cNAU8825 info > /dev/null 2>&1; then
        amixer -cNAU8825 cset name='Headphone Volume' 63,63 2> /dev/null || amixer -cNAU8825 sset 'Headphone' 100% 2> /dev/null || true
        amixer -cNAU8825 cset name='Mic Volume' 255 2> /dev/null || amixer -cNAU8825 sset 'Mic' 100% 2> /dev/null || true
        log_success "  NAU8825 mixer set"
    fi
    # DMIC (range 0..2147483647, needs large value)
    if amixer -cDMIC info > /dev/null 2>&1; then
        amixer -cDMIC cset name='DMIC Volume' 1500000000 2> /dev/null || amixer -cDMIC sset 'DMIC' 80% 2> /dev/null || amixer -cDMIC cset name='DMIC Volume' 2147483647 2> /dev/null || true
        log_success "  DMIC mixer set"
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
                    local backup_path="$BACKUP_BASE_DIR/${ts}${legacy}"
                    if sudo mkdir -p "$(dirname "$backup_path")" \
                        && sudo cp -a "$legacy" "$backup_path" 2> /dev/null; then
                        # Remove as the owning user to avoid root-owned leftover
                        if sudo -u "$real_user" rm -f "$legacy" 2> /dev/null || sudo rm -f "$legacy" 2> /dev/null; then
                            log_success "  Removed legacy per-user config (backed up to $backup_path)"
                        else
                            log_warn "  Backed up but could not remove $legacy"
                        fi
                    else
                        log_warn "  Backup failed; leaving $legacy in place"
                    fi
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
    if ! fix_ucm_fallbacks; then
        log_error "UCM fallback symlinks could not be created; aborting install."
        return 1
    fi
    if ! fix_ucm_pcm_index; then
        log_error "UCM PCM indices are not usable for this kernel; aborting install (run --check)."
        return 1
    fi

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
    local real_user real_uid ssm_sink wp_status wp_names sink_section restarted=0
    real_user="$(get_real_user)"
    real_uid="$(get_real_user_uid)"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        log_dryrun "Restart PipeWire & WirePlumber for user $real_user (UID: $real_uid)"
    else
        if [ -n "$real_user" ] && [ "$real_user" != "root" ] && [ -d "/run/user/$real_uid" ]; then
            sudo -u "$real_user" XDG_RUNTIME_DIR="/run/user/$real_uid" systemctl --user restart pipewire wireplumber 2> /dev/null || true
            restarted=1
        elif systemctl --user restart wireplumber 2> /dev/null; then
            restarted=1
        fi
        if [ "$restarted" = "1" ]; then
            # WirePlumber needs 2-5s to rebuild the graph; wait before first poll
            log_info "Waiting for PipeWire graph rebuild..."
            sleep 2
            # Poll the Sinks section only (a Device: entry must not satisfy
            # the check and skip the default-sink pin below).
            for _ in $(seq 1 15); do
                wp_names="$(wpctl_as_real_user 1 status -n)"
                if printf '%s\n' "$wp_names" | sed -n '/Sinks:/,/Sources:/p' | grep -qi "ssm4567"; then
                    break
                fi
                sleep 1
            done
            wp_names="$(wpctl_as_real_user 1 status -n)"
            wp_status="$(wpctl_as_real_user 1 status)"
            sink_section="$(printf '%s\n' "$wp_names" | sed -n '/Sinks:/,/Sources:/p')"
            if [ -z "$sink_section" ]; then
                sink_section="$(printf '%s\n' "$wp_status" | sed -n '/Sinks:/,/Sources:/p')"
            fi
            # Best-effort: lock default sink to SSM4567 HiFi to clear stale
            # stereo-fallback. Takes the first sink in the Sinks section.
            ssm_sink="$(printf '%s\n' "$sink_section" | grep -i "ssm4567" | head -n1 | sed -E 's/^[^0-9]*([0-9]+)\..*/\1/')"
            case "$ssm_sink" in '' | *[!0-9]*) ssm_sink="" ;; esac
            if [ -n "$ssm_sink" ]; then
                if wpctl_set_default "$ssm_sink"; then
                    log_info "Pinned default sink to SSM4567 ($ssm_sink)."
                else
                    log_info "SSM4567 sink $ssm_sink found, but set-default failed; leaving default unchanged."
                fi
            else
                log_info "SSM4567 sink not found, leaving default unchanged."
            fi
            log_success "PipeWire & WirePlumber restarted."
        else
            log_info "No active user session; changes will take effect after next login/reboot."
        fi
    fi

    log_step 5 5 "Verifying..."
    if [ "${DRY_RUN:-0}" != "1" ]; then
        if LC_ALL=C aplay -l 2> /dev/null | grep -q "SSM4567"; then
            log_success "ALSA card 'SSM4567' present."
        fi
        # NOTE: when run via sudo, bare `wpctl status` sees root's (empty)
        # session; wpctl_as_real_user queries the real user's session.
        wp_status="$(wpctl_as_real_user 1 status)"
        wp_names="$(wpctl_as_real_user 1 status -n)"
        sink_section="$(printf '%s\n' "$wp_names" | sed -n '/Sinks:/,/Sources:/p')"
        if [ -z "$sink_section" ]; then
            sink_section="$(printf '%s\n' "$wp_status" | sed -n '/Sinks:/,/Sources:/p')"
        fi
        if printf '%s\n' "$sink_section" | grep -qi "ssm4567"; then
            log_success "PipeWire Speaker sink (SSM4567) verified!"
        else
            log_warn "Speaker sink not yet visible - check 'wpctl status' after re-login"
        fi
        # Show default sink (first '*' line of the Sinks section; friendly names, not alsa_output)
        local default_sink
        default_sink=$(printf '%s\n' "$wp_status" | sed -n '/Sinks:/,/Sources:/p' | grep -E '\*' | head -n1 | sed -E 's/^[^0-9]*//')
        if [ -n "$default_sink" ]; then
            log_info "Default sink: $default_sink"
        fi
        log_info "Test: speaker-test -D plughw:SSM4567,0 -c2 -l1  (or pw-play /usr/share/sounds/alsa/Front_Left.wav)"
    fi

    log_success "AVS audio configuration complete! 🔊"
}

main() {
    local action="install"
    while [ $# -gt 0 ]; do
        case "$1" in
            --install | -i)
                action="install"
                shift
                ;;
            --check | -c)
                action="check"
                shift
                ;;
            --uninstall | -u)
                action="uninstall"
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

    case "$action" in
        install) install_audio ;;
        check) check_audio_status ;;
        uninstall) uninstall_audio ;;
    esac
}

# Allow the hermetic tests to source the functions without running the CLI.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
