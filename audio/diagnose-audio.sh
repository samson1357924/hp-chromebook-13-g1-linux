#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# audio/diagnose-audio.sh - AVS Audio Diagnostics for HP Chromebook 13 G1 (Chell)

OUTPUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o | --output)
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
    exec > >(tee -a "$OUTPUT") 2>&1
fi

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
lsmod | grep -E "snd_soc_avs|snd_sof" | sed 's/^/  /' || echo "  [WARN] No AVS/SOF modules found"
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
UCM_DST="/usr/share/alsa/ucm2"
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
for f in "$UCM_DST/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf" "$UCM_DST/Intel/avs/avs_nau8825/avs_nau8825-HiFi.conf"; do
    if [ -f "$f" ]; then
        if grep -q 'hw:${CardId},1' "$f" 2> /dev/null; then
            echo "    [WARN] $f contains hw:\${CardId},1"
        else
            echo "    [OK] $f"
        fi
    fi
done
if command -v alsaucm > /dev/null 2>&1; then
    echo "  alsaucm verb check:"
    for c in 4 3 0 2; do
        if alsaucm -c "hw:$c" dump text 2>&1 | grep -q "Verb.HiFi"; then
            echo "    [OK] hw:$c Verb.HiFi"
        else
            echo "    [FAIL] hw:$c no Verb.HiFi ($(alsaucm -c "hw:$c" dump text 2>&1 | head -n1 | cut -c1-80))"
        fi
    done
fi
echo ""

echo "--- [5/6] ALSA Mixers ---"
for card in 4 3 0; do
    if amixer -c"$card" info > /dev/null 2>&1; then
        echo "  Card $card ($(cat /proc/asound/card$card/id 2> /dev/null)):"
        amixer -c"$card" scontrols 2> /dev/null | sed 's/^/    /'
        amixer -c"$card" contents 2> /dev/null | grep -E "values=" | head -n 20 | sed 's/^/    /'
    fi
done
# Highlight DSP mute (use name= syntax)
if amixer -c4 cget name='DSP Volume' 2> /dev/null | grep -q "values=0"; then
    echo "  [WARN] Card 4 DSP Volume is 0 (muted) - run install-audio.sh to unmute"
fi
echo ""

echo "--- [6/6] PipeWire / WirePlumber ---"
if command -v wpctl > /dev/null 2>&1; then
    wpctl status 2> /dev/null | sed -n '/^Audio/,/^Video/p' | sed 's/^/  /' || echo "  [INFO] PipeWire not running"
fi
if command -v pw-dump > /dev/null 2>&1; then
    echo "  ALSA nodes (pw-dump):"
    pw-dump 2> /dev/null | grep -o '"node.name" : "alsa[^"]*"' | sort -u | sed 's/^/    /' || true
    echo "  Default sink: $(wpctl status 2> /dev/null | grep -E '\*.*alsa_output' | head -n1 | sed 's/^/    /')"
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
    if dmesg 2> /dev/null | grep -i -E "avs|ssm4567|nau8825" | tail -n 20 | sed 's/^/  /'; then
        :
    else
        echo "  [INFO] dmesg restricted; try: sudo dmesg | grep -i avs"
        sudo dmesg 2> /dev/null | grep -i -E "avs|ssm4567|nau8825" | tail -n 20 | sed 's/^/  /' || echo "  [INFO] No AVS dmesg lines"
    fi
fi
echo ""
echo "Diagnostic complete! For fix: sudo ./audio/install-audio.sh --install"
