#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# audio/diagnose-audio.sh - AVS Audio Diagnostics for HP Chromebook 13 G1 (Chell)

OUTPUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o | --output)
            if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
                echo "Usage: $0 [-o FILE]" >&2
                echo "  -o FILE  Also tee report to FILE" >&2
                exit 2
            fi
            OUTPUT="$2"
            shift 2
            ;;
        -h | --help)
            echo "Usage: $0 [-o FILE]"
            echo "  -o FILE  Also tee report to FILE"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done
if [ -n "$OUTPUT" ]; then
    if ! touch "$OUTPUT" 2> /dev/null; then
        echo "Cannot write report file: $OUTPUT" >&2
        exit 1
    fi
    echo "NOTE: report may contain hardware IDs; review before sharing." >&2
    exec > >(tee -a "$OUTPUT") 2>&1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Reuse the installer's kernel-numbering helper so diagnostics and install
# agree on whether ,1/,2 or ,0 is correct.
# shellcheck source=../audio/install-audio.sh
source "$REPO_ROOT/audio/install-audio.sh"

UCM_DST="${CROS_UCM_DIR:-/usr/share/alsa/ucm2}"
AVS_OBSOLETE_PARAM="${CROS_AVS_OBSOLETE_PARAM_FILE:-$AVS_OBSOLETE_PARAM}"
AVS_KERNEL_RELEASE="${CROS_AVS_KERNEL_RELEASE:-$AVS_KERNEL_RELEASE}"
AVS_MODPROBE_DIR="${CROS_AVS_MODPROBE_DIR:-$AVS_MODPROBE_DIR}"
AVS_CMDLINE_FILE="${CROS_AVS_CMDLINE_FILE:-$AVS_CMDLINE_FILE}"

echo "==========================================================="
echo "   HP Chromebook 13 G1 (Chell) AVS Audio Diagnostic        "
echo "==========================================================="
echo ""

echo "--- [1/6] System & DMI ---"
echo "Product Name : $(cat /sys/class/dmi/id/product_name 2> /dev/null || echo Unknown)"
echo "Sys Vendor   : $(cat /sys/class/dmi/id/sys_vendor 2> /dev/null || echo Unknown)"
echo "Board Name   : $(cat /sys/class/dmi/id/board_name 2> /dev/null || echo Unknown)"
echo "Product Fam. : $(cat /sys/class/dmi/id/product_family 2> /dev/null || echo Unknown)"
echo "BIOS Version : $(cat /sys/class/dmi/id/bios_version 2> /dev/null || echo Unknown)"
echo "Kernel       : $(uname -r)"
echo "Cmdline      : $(cat /proc/cmdline 2> /dev/null | cut -c1-200)"
echo ""

echo "--- [2/6] AVS Kernel Modules ---"
mod_lines="$(lsmod 2> /dev/null | grep -E "snd_soc_avs|snd_sof" || true)"
if [ -n "$mod_lines" ]; then
    printf '%s\n' "$mod_lines" | sed 's/^/  /'
else
    echo "  [WARN] No AVS/SOF modules found"
fi
echo ""
if [ -d /lib/firmware/intel/avs ]; then
    echo "AVS firmware dir: /lib/firmware/intel/avs/"
    ls /lib/firmware/intel/avs/ 2> /dev/null | sed 's/^/  /' | head -n 20
    ls /lib/firmware/intel/avs/skl/ 2> /dev/null | sed 's/^/  SKL: /' | head -n 20
else
    echo "  [WARN] /lib/firmware/intel/avs/ not found"
fi
echo ""

echo "--- [3/6] ALSA Cards & PCM Map ---"
if command -v aplay > /dev/null 2>&1; then
    LC_ALL=C aplay -l 2> /dev/null | grep -E "^card|^[[:space:]]*device" | sed 's/^/  /' || echo "  [INFO] No playback devices"
else
    echo "  [INFO] aplay not installed"
fi
if command -v arecord > /dev/null 2>&1; then
    LC_ALL=C arecord -l 2> /dev/null | grep -E "^card|^[[:space:]]*device" | sed 's/^/  /' || echo "  [INFO] No capture devices"
fi
echo "  /proc/asound/cards:"
cat /proc/asound/cards 2> /dev/null | sed 's/^/    /'
echo "  PCM info:"
for c in /proc/asound/card*/pcm*/info; do
    [ -f "$c" ] || continue
    echo "    $c: $(grep -E 'card:|device:|id:' "$c" 2> /dev/null | tr '\n' ' ' | cut -c1-120)"
done
echo ""

echo "--- [4/6] UCM Status ---"
for rel in \
    "conf.d/avs_ssm4567/AVS I2S SSM4567.conf" \
    "conf.d/avs_ssm4567/avs_ssm4567.conf" \
    "conf.d/avs_nau8825/AVS I2S NAU8825.conf" \
    "conf.d/avs_nau8825/avs_nau8825.conf" \
    "conf.d/avs_dmic/AVS DMIC.conf" \
    "conf.d/avs_dmic/avs_dmic.conf" \
    "conf.d/avs_hdaudio/AVS HDMI.conf" \
    "conf.d/avs_hdaudio/avs_hdaudio.conf"; do
    if [ -e "$UCM_DST/$rel" ]; then
        echo "  [OK] $rel -> $(readlink "$UCM_DST/$rel" 2> /dev/null || echo file)"
    else
        echo "  [MISSING] $rel"
    fi
done
echo "  PCM index check:"
pcm_mode="$(avs_numbering_mode)"
echo "    AVS PCM numbering: $pcm_mode"
for f in \
    "$UCM_DST/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf" \
    "$UCM_DST/Intel/avs/avs_nau8825/avs_nau8825-HiFi.conf" \
    "$UCM_DST/Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0-HiFi.conf" \
    "$UCM_DST/Intel/avs/avs_dmic/DMIC-2ch-HiFi.conf" \
    "$UCM_DST/Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf"; do
    [ -f "$f" ] || continue
    if [ ! -s "$f" ]; then
        echo "    [WARN] $f is empty or truncated"
        continue
    fi
    if ! grep -qE 'hw:\$\{CardId\},[0-9]+([^0-9]|$)' "$f" 2> /dev/null; then
        if [ -s "$f" ] && grep -qE '^[[:space:]]*Include([.[:space:]]|$)' "$f" 2> /dev/null; then
            echo "    [OK] $f (Include-only, no literal PCM index)"
        else
            echo "    [WARN] $f has no PCM index and is not a valid Include-only file"
        fi
        continue
    fi
    if [ "$pcm_mode" = "legacy" ]; then
        if grep -qE 'hw:\$\{CardId\},0([^0-9]|$)' "$f" 2> /dev/null; then
            echo "    [WARN] $f uses hw:\${CardId},0 but legacy AVS numbering needs ,1/,2"
        elif grep -qE 'hw:\$\{CardId\},[12]([^0-9]|$)' "$f" 2> /dev/null; then
            echo "    [OK] $f (legacy hw:\${CardId},1/,2)"
        else
            echo "    [WARN] $f has a PCM index but none is hw:\${CardId},1|,2"
        fi
    else
        if grep -qE 'hw:\$\{CardId\},[12]([^0-9]|$)' "$f" 2> /dev/null; then
            pcm_idx="$(grep -oE 'hw:\$\{CardId\},[12]([^0-9]|$)' "$f" | head -n 1 | sed -E 's/.*,([12]).*/\1/')"
            echo "    [WARN] $f contains hw:\${CardId},$pcm_idx (expected hw:\${CardId},0)"
        else
            echo "    [OK] $f (hw:\${CardId},0)"
        fi
    fi
done
if command -v alsaucm > /dev/null 2>&1; then
    echo "  alsaucm verb check (using ALSA IDs - card numbers are dynamic):"
    for c in SSM4567 NAU8825 HDMI DMIC; do
        if alsaucm -c "hw:$c" dump text 2>&1 | grep -q "Verb.HiFi"; then
            echo "    [OK] hw:$c Verb.HiFi"
        else
            echo "    [FAIL] hw:$c no Verb.HiFi ($(alsaucm -c "hw:$c" dump text 2>&1 | head -n1 | cut -c1-80))"
        fi
    done
fi
echo ""

echo "--- [5/6] ALSA Mixers (using ALSA IDs) ---"
for card in SSM4567 NAU8825 DMIC; do
    if amixer -c"$card" info > /dev/null 2>&1; then
        echo "  Card $card:"
        amixer -c"$card" scontrols 2> /dev/null | sed 's/^/    /'
        amixer -c"$card" contents 2> /dev/null | grep -E "values=" | head -n 20 | sed 's/^/    /'
    fi
done
# Highlight DSP mute (use name= syntax, ALSA ID)
if amixer -cSSM4567 cget name='DSP Volume' 2> /dev/null | grep -q "values=0"; then
    echo "  [WARN] SSM4567 DSP Volume is 0 (muted) - run install-audio.sh to unmute"
fi
echo ""

echo "--- [6/6] PipeWire / WirePlumber ---"
wp_status_out=""
wp_names_out=""
wp_audio_out=""
if command -v wpctl > /dev/null 2>&1; then
    wp_status_out="$(wpctl status 2> /dev/null || true)"
    wp_names_out="$(wpctl status -n 2> /dev/null || true)"
    if [ -n "$wp_status_out" ]; then
        wp_audio_out="$(printf '%s\n' "$wp_status_out" | sed -n '/^Audio/,/^Video/p')"
        if [ -n "$wp_audio_out" ]; then
            printf '%s\n' "$wp_audio_out" | sed 's/^/  /'
        fi
    else
        echo "  [INFO] PipeWire not running"
    fi
fi
# Speaker sink presence: with a stale UCM PCM index the AVS HiFi profile fails
# to build, cards keep profile "off" and PipeWire only offers the silent
# fallback "Dummy Output" (auto_null). Only a real sink node counts: it owns
# ports (pw-link) and an 'alsa_output...ssm4567...' node name, while a bare
# ALSA device node is called 'alsa_card...' and must never satisfy the check.
wp_sink="unknown"
sink_section=""
if [ -n "$wp_status_out" ]; then
    if [ -n "$wp_names_out" ]; then
        sink_section="$(printf '%s\n' "$wp_names_out" | sed -n '/Sinks:/,/Sources:/p')"
    fi
    if [ -z "$sink_section" ]; then
        sink_section="$(printf '%s\n' "$wp_status_out" | sed -n '/Sinks:/,/Sources:/p')"
    fi
    if printf '%s\n' "$sink_section" | grep -qi 'ssm4567'; then
        wp_sink="ok"
    elif [ -n "$sink_section" ]; then
        wp_sink="missing"
    else
        wp_sink="unknown"
    fi
elif command -v wpctl > /dev/null 2>&1; then
    wp_sink="nosession"
elif command -v pw-link > /dev/null 2>&1; then
    if pw-link -io 2> /dev/null | grep -qi 'ssm4567'; then
        wp_sink="ok"
    else
        wp_sink="missing"
    fi
elif command -v pw-dump > /dev/null 2>&1; then
    if pw-dump 2> /dev/null | grep -qE '"node.name"[[:space:]]*:[[:space:]]*"alsa_output[^"]*ssm4567'; then
        wp_sink="ok"
    else
        wp_sink="missing"
    fi
fi
case "$wp_sink" in
    ok)
        echo "  [OK] PipeWire exposes the AVS speaker sink (SSM4567)"
        ;;
    missing)
        echo "  [WARN] No SSM4567 speaker sink in PipeWire - audio likely plays to the silent 'Dummy Output' (auto_null)"
        echo "         The AVS card profile probably failed to build (cards show only {off, pro-audio}, active 'off')."
        echo "         On current kernels only 'hw:SSM4567,0' exists; 'aplay -D hw:SSM4567,1' fails with ENOENT."
        echo "         See audio/docs/root-cause.md - fix: sudo ./audio/install-audio.sh --install"
        ;;
    nosession)
        echo "  [WARN] Cannot list PipeWire sinks (PipeWire not running? under sudo, re-run as your desktop user)"
        ;;
    unknown)
        echo "  [INFO] Cannot read the PipeWire Sinks section - check PipeWire/WirePlumber"
        ;;
    *)
        echo "  [INFO] wpctl, pw-link and pw-dump all unavailable - cannot verify the PipeWire speaker sink"
        ;;
esac
if command -v pw-dump > /dev/null 2>&1; then
    echo "  ALSA nodes (pw-dump):"
    pw-dump 2> /dev/null | grep -oE '"node.name"[[:space:]]*:[[:space:]]*"alsa[^"]*"' | sort -u | sed 's/^/    /' || true
    echo "  Default sink: $(printf '%s\n' "$wp_status_out" | sed -n '/Sinks:/,/Sources:/p' | grep -E '\*' | head -n1 | sed -E 's/^[^0-9]*//')"
fi
# WirePlumber restores a saved node volume on login, which can override the
# installer's 'DSP Volume' mixer value and leave playback nearly silent.
if command -v wpctl > /dev/null 2>&1; then
    vol_out="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2> /dev/null || true)"
    if [ -z "$vol_out" ]; then
        echo "  [INFO] No default sink volume reported (no default sink, or wpctl cannot reach PipeWire)"
    else
        echo "  Default sink volume: $vol_out"
        if command -v awk > /dev/null 2>&1; then
            vol_num="$(printf '%s\n' "$vol_out" | awk '/^Volume:/ {print $2; exit}')"
            if [ -n "$vol_num" ] && awk -v v="$vol_num" 'BEGIN { exit !(v ~ /^[0-9]+(\.[0-9]+)?$/ && v < 0.2) }'; then
                echo "  [WARN] Default sink volume is very low (${vol_num} < 0.2) - output may be nearly inaudible"
                echo "         Hint: wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5"
            fi
        else
            echo "  [INFO] awk not available - skipping low-volume evaluation"
        fi
        case "$vol_out" in
            *"[MUTED]"*) echo "  [WARN] Default sink is muted - hint: wpctl set-mute @DEFAULT_AUDIO_SINK@ 0" ;;
        esac
    fi
else
    echo "  [INFO] wpctl not available - skipping default sink volume check"
fi
if command -v systemctl > /dev/null 2>&1; then
    echo "  User services: $(systemctl --user is-active pipewire wireplumber 2> /dev/null | tr '\n' ' ')"
fi
echo "  WirePlumber configs:"
ls -l /etc/wireplumber/wireplumber.conf.d/ 2> /dev/null | sed 's/^/    /' || echo "    (no /etc/wireplumber/wireplumber.conf.d/)"
echo ""

echo "--- Extra: i915 / nomodeset check ---"
if grep -q "nomodeset" /proc/cmdline 2> /dev/null; then
    echo "  [WARN] nomodeset present - i915 disabled, HDMI audio may fail with -19"
else
    echo "  [OK] nomodeset not present"
fi
if lsmod | grep -q "i915"; then echo "  [OK] i915 loaded"; else echo "  [WARN] i915 not loaded"; fi
echo ""

echo "--- Extra: dmesg (AVS) ---"
if command -v dmesg > /dev/null 2>&1; then
    dmesg_lines="$(dmesg 2> /dev/null | grep -i -E "avs|ssm4567|nau8825" | tail -n 20 || true)"
    if [ -n "$dmesg_lines" ]; then
        printf '%s\n' "$dmesg_lines" | sed 's/^/  /'
    else
        echo "  [INFO] dmesg restricted or no AVS lines; try: sudo dmesg | grep -i avs"
        if command -v sudo > /dev/null 2>&1; then
            sudo dmesg 2> /dev/null | grep -i -E "avs|ssm4567|nau8825" | tail -n 20 | sed 's/^/  /' || echo "  [INFO] No AVS dmesg lines"
        fi
    fi
fi
echo ""
echo "Diagnostic complete! For fix: sudo ./audio/install-audio.sh --install"
