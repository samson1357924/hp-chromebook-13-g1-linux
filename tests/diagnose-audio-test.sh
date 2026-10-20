#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Samson <https://github.com/samson1357924>
# tests/diagnose-audio-test.sh - Hermetic behavior tests for
# audio/diagnose-audio.sh (sink detection, numbering mode, -o handling).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIAG="$REPO_ROOT/audio/diagnose-audio.sh"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/diagnose-audio-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0
fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}
ok() { PASS=$((PASS + 1)); }
assert_contains() {
    if printf '%s' "$2" | grep -qF -- "$1"; then ok; else fail "$3 (missing: $1)"; fi
}
assert_not_contains() {
    if printf '%s' "$2" | grep -qF -- "$1"; then fail "$3 (unexpected: $1)"; else ok; fi
}

export SANDBOX
mkdir -p "$SANDBOX/bin" "$SANDBOX/minbin" "$SANDBOX/ucm"
for c in cat grep sed ls lsmod systemctl uname dmesg amixer aplay arecord alsaucm awk touch; do
    for base in /usr/bin /bin /sbin /usr/sbin; do
        if [ -x "$base/$c" ] && [ ! -e "$SANDBOX/minbin/$c" ]; then
            ln -s "$base/$c" "$SANDBOX/minbin/$c"
        fi
    done
done
cat > "$SANDBOX/bin/sudo" << 'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in -n|-E|-H) shift ;; -u) shift 2 ;; --) shift; break ;; *) break ;; esac
done
exec "$@"
EOF
cat > "$SANDBOX/bin/wpctl" << 'EOF'
#!/bin/sh
case "$1" in
    status)
        if [ "${2:-}" = "-n" ]; then cat "${WPCTL_NAMES_FILE:-/dev/null}" 2>/dev/null || true
        else cat "${WPCTL_STATUS_FILE:-/dev/null}" 2>/dev/null || true; fi
        ;;
    get-volume) printf '%s\n' "${WPCTL_VOLUME:-}" ;;
esac
EOF
cat > "$SANDBOX/bin/pw-dump" << 'EOF'
#!/bin/sh
if [ -n "${PWP_DUMP_FILE:-}" ] && [ -f "$PWP_DUMP_FILE" ]; then cat "$PWP_DUMP_FILE"; else exit 1; fi
EOF
cat > "$SANDBOX/bin/pw-link" << 'EOF'
#!/bin/sh
if [ -n "${PW_LINK_FILE:-}" ] && [ -f "$PW_LINK_FILE" ]; then cat "$PW_LINK_FILE"; else exit 1; fi
EOF
cat > "$SANDBOX/bin/aplay" << 'EOF'
#!/bin/sh
[ "$1" = "-l" ] && printf 'card 0: SSM4567 [AVS I2S SSM4567]\n'
EOF
cat > "$SANDBOX/bin/arecord" << 'EOF'
#!/bin/sh
[ "$1" = "-l" ] && printf 'card 0: DMIC [AVS DMIC]\n'
EOF
cat > "$SANDBOX/bin/amixer" << 'EOF'
#!/bin/sh
case "$*" in
    *info) exit 0 ;;
    *scontrols) printf 'Simple mixer control "DSP",0\n' ;;
    *contents) printf 'values=1500000000\n' ;;
    *"cget name='DSP Volume'"*) printf 'values=%s\n' "${AMIXER_DSP_VALUE:-1500000000}" ;;
    *) exit 0 ;;
esac
EOF
cat > "$SANDBOX/bin/alsaucm" << 'EOF'
#!/bin/sh
echo "  Verb.HiFi"
EOF
cat > "$SANDBOX/bin/lsmod" << 'EOF'
#!/bin/sh
echo "snd_soc_avs 12345 0"
EOF
cat > "$SANDBOX/bin/systemctl" << 'EOF'
#!/bin/sh
echo "active active"
EOF
cat > "$SANDBOX/bin/dmesg" << 'EOF'
#!/bin/sh
exit 0
EOF
cat > "$SANDBOX/bin/uname" << 'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_KERNEL:-7.0.0-38-generic}"
EOF
chmod +x "$SANDBOX/bin"/*
export PATH="$SANDBOX/bin:$PATH"

# Common fixture: a stale UCM tree for new numbering.
mkdir -p "$SANDBOX/ucm/Intel/avs/avs_ssm4567" "$SANDBOX/ucm/Intel/avs/avs_dmic"
printf 'PlaybackPCM "hw:${CardId},1"\n' > "$SANDBOX/ucm/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf"
printf 'CapturePCM "hw:${CardId},2"\n' > "$SANDBOX/ucm/Intel/avs/avs_dmic/DMIC-2ch-HiFi.conf"

run_diag() {
    env \
        CROS_UCM_DIR="$SANDBOX/ucm" \
        CROS_AVS_OBSOLETE_PARAM_FILE="$SANDBOX/obsolete" \
        CROS_AVS_KERNEL_RELEASE="${FAKE_KERNEL:-7.0.0-38-generic}" \
        CROS_AVS_MODPROBE_DIR="$SANDBOX/modprobe" \
        CROS_AVS_CMDLINE_FILE="$SANDBOX/cmdline" \
        WPCTL_STATUS_FILE="$SANDBOX/wp-status" \
        WPCTL_NAMES_FILE="$SANDBOX/wp-names" \
        WPCTL_VOLUME="$(cat "$SANDBOX/wp-volume" 2> /dev/null || true)" \
        AMIXER_DSP_VALUE="$(cat "$SANDBOX/amixer-dsp" 2> /dev/null || true)" \
        FAKE_KERNEL="${FAKE_KERNEL:-7.0.0-38-generic}" \
        PATH="$PATH" \
        bash "$DIAG" 2>&1
}

# ---------------------------------------------------------------------------
# 1. New numbering: stale PCM index is reported
# ---------------------------------------------------------------------------
rm -f "$SANDBOX/obsolete"
mkdir -p "$SANDBOX/modprobe"
: > "$SANDBOX/cmdline"
out="$(run_diag)"
assert_contains "contains hw:\${CardId},1" "$out" "stale ,1 should be reported on new numbering"
assert_contains "contains hw:\${CardId},2" "$out" "stale ,2 should be reported on new numbering"

# ---------------------------------------------------------------------------
# 2. Fixed UCM + real sink node: OK, low volume and muted warnings
# ---------------------------------------------------------------------------
printf 'PlaybackPCM "hw:${CardId},0"\n' > "$SANDBOX/ucm/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf"
printf 'CapturePCM "hw:${CardId},0"\n' > "$SANDBOX/ucm/Intel/avs/avs_dmic/DMIC-2ch-HiFi.conf"
cat > "$SANDBOX/wp-status" << 'EOF'
Audio
 ├─ Sinks:
 │  *   64. Built-in Speakers (SSM4567) [vol: 0.02]
 │  
 ├─ Sources:
 │  *   61. Internal Mic (DMIC) [vol: 0.55]
EOF
cat > "$SANDBOX/wp-names" << 'EOF'
Audio
 ├─ Sinks:
 │  *   64. alsa_output.platform-avs_ssm4567.7.auto.HiFi__Speaker__sink [vol: 0.02]
 │  
 ├─ Sources:
 │  *   61. alsa_input.platform-avs_dmic.5.auto.HiFi__Mic__source [vol: 0.55]
EOF
printf 'Volume: 0.02 [MUTED]\n' > "$SANDBOX/wp-volume"
printf '0\n' > "$SANDBOX/amixer-dsp"
out="$(run_diag)"
assert_contains "PipeWire exposes the AVS speaker sink (SSM4567)" "$out" "real sink node should be reported"
assert_contains "Default sink volume is very low" "$out" "low volume should warn"
assert_contains "Default sink is muted" "$out" "muted sink should warn"

# ---------------------------------------------------------------------------
# 3. Missing sink (only Dummy Output): WARN, no false OK
# ---------------------------------------------------------------------------
cat > "$SANDBOX/wp-status" << 'EOF'
Audio
 ├─ Sinks:
 │  *   42. Dummy Output [vol: 1.00]
 │  
 ├─ Sources:
EOF
cat > "$SANDBOX/wp-names" << 'EOF'
Audio
 ├─ Sinks:
 │  *   42. auto_null [vol: 1.00]
 │  
 ├─ Sources:
EOF
printf 'Volume: 1.00\n' > "$SANDBOX/wp-volume"
out="$(run_diag)"
assert_contains "No SSM4567 speaker sink in PipeWire" "$out" "missing sink should warn"
assert_not_contains "PipeWire exposes the AVS speaker sink (SSM4567)" "$out" "missing sink must not be reported as OK"

# ---------------------------------------------------------------------------
# 4. Description lacks SSM4567 but node name has it: still OK
# ---------------------------------------------------------------------------
cat > "$SANDBOX/wp-status" << 'EOF'
Audio
 ├─ Sinks:
 │  *   64. Built-in Speakers [vol: 0.50]
 │  
 ├─ Sources:
EOF
cat > "$SANDBOX/wp-names" << 'EOF'
Audio
 ├─ Sinks:
 │  *   64. alsa_output.platform-avs_ssm4567.7.auto.HiFi__Speaker__sink [vol: 0.50]
 │  
 ├─ Sources:
EOF
printf 'Volume: 0.50\n' > "$SANDBOX/wp-volume"
out="$(run_diag)"
assert_contains "PipeWire exposes the AVS speaker sink (SSM4567)" "$out" "node-name detection should win over description"

# ---------------------------------------------------------------------------
# 5. Legacy numbering: ,1/,2 accepted, ,0 flagged
# ---------------------------------------------------------------------------
printf 'Y\n' > "$SANDBOX/obsolete"
printf 'PlaybackPCM "hw:${CardId},1"\n' > "$SANDBOX/ucm/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf"
printf 'CapturePCM "hw:${CardId},2"\n' > "$SANDBOX/ucm/Intel/avs/avs_dmic/DMIC-2ch-HiFi.conf"
out="$(FAKE_KERNEL=6.15.0 run_diag)"
assert_contains "legacy hw:\${CardId},1/,2" "$out" "legacy ,1 should be accepted"
assert_contains "legacy hw:\${CardId},1/,2" "$out" "legacy ,2 should be accepted"

# ---------------------------------------------------------------------------
# 6. -o missing argument
# ---------------------------------------------------------------------------
set +e
bash "$DIAG" -o > "$SANDBOX/o-missing.out" 2>&1
rc=$?
set -e
assert_eq_rc() { if [ "$1" = "$2" ]; then ok; else fail "$3 (expected $1, got $2)"; fi; }
assert_eq_rc 2 "$rc" "-o without an argument should exit 2"

# ---------------------------------------------------------------------------
# 7. -o unwritable path
# ---------------------------------------------------------------------------
set +e
bash "$DIAG" -o /proc/nonexistent/report.txt > "$SANDBOX/o-bad.out" 2>&1
rc=$?
set -e
assert_eq_rc 1 "$rc" "unwritable -o path should exit 1"

# ---------------------------------------------------------------------------
# 8. No wpctl/pw tools: unknown/info, not crash
# ---------------------------------------------------------------------------
PATH="$SANDBOX/minbin" \
    CROS_UCM_DIR="$SANDBOX/ucm" \
    CROS_AVS_OBSOLETE_PARAM_FILE="$SANDBOX/obsolete" \
    CROS_AVS_KERNEL_RELEASE="7.0.0-38-generic" \
    /bin/bash "$DIAG" > "$SANDBOX/no-tools.out" 2>&1 || true
assert_contains "Cannot read the PipeWire Sinks section" "$(cat "$SANDBOX/no-tools.out")" "missing tools should be reported as unknown"

echo ""
echo "diagnose audio tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
