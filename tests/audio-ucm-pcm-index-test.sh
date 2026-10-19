#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Samson <https://github.com/samson1357924>
# tests/audio-ucm-pcm-index-test.sh - Hermetic regression test for the UCM PCM
# index fix in audio/install-audio.sh (hw:${CardId},1|,2 -> hw:${CardId},0).
#
# The real fix_ucm_pcm_index() function is extracted from the installer and
# run against a sandboxed fake UCM tree, so no root, ALSA or PipeWire state
# is touched. Run directly:
#
#   bash tests/audio-ucm-pcm-index-test.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_ROOT/audio/install-audio.sh"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/audio-ucm-pcm-index-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

ok() {
    PASS=$((PASS + 1))
}

assert_contains() {
    # $1=needle $2=file $3=message
    if grep -qF -- "$1" "$2"; then
        ok
    else
        fail "$3 (missing: $1)"
    fi
}

# Sandboxed UCM tree with the legacy (pre-kernel 6.16) PCM indices: speaker
# and headset profiles use ,1, DMIC capture uses ,2; every AVS card must end
# up at ,0. Each file also carries a target at end-of-line (right boundary)
# and non-target indices (,3 and the multi-digit ,10/,12/,20) that must
# remain untouched.
UCM_DST="$SANDBOX/ucm"
FILES=(
    "Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf"
    "Intel/avs/avs_nau8825/avs_nau8825-HiFi.conf"
    "Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0-HiFi.conf"
    "Intel/avs/avs_dmic/DMIC-2ch-HiFi.conf"
    "Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf"
)
for rel in "${FILES[@]}"; do
    mkdir -p "$UCM_DST/$(dirname "$rel")"
    legacy_idx=1
    case "$rel" in
        *avs_dmic*) legacy_idx=2 ;;
    esac
    printf 'SectionDevice."Speaker" {\n\tPlaybackPCM "hw:${CardId},%s"\n\tTrailing hw:${CardId},%s\n\tKeepMe "hw:${CardId},3"\n\tKeep10 "hw:${CardId},10"\n\tKeep12 "hw:${CardId},12"\n\tKeep20 "hw:${CardId},20"\n}\n' \
        "$legacy_idx" "$legacy_idx" > "$UCM_DST/$rel"
done

# Minimal environment for the extracted function (the real installer provides
# these via lib/logger.sh + lib/backup.sh, and calls sudo for in-place edits).
DRYRUN_LOG="$SANDBOX/dryrun.log"
log_info() { :; }
log_success() { :; }
log_dryrun() { printf '%s\n' "$*" >> "$DRYRUN_LOG"; }
backup_file_manifest_aware() { :; }

mkdir -p "$SANDBOX/bin"
printf '#!/bin/sh\nexec "$@"\n' > "$SANDBOX/bin/sudo"
chmod +x "$SANDBOX/bin/sudo"
PATH="$SANDBOX/bin:$PATH"

FUNC_SRC="$(sed -n '/^fix_ucm_pcm_index()/,/^}/p' "$INSTALLER")"
if [ -z "$FUNC_SRC" ]; then
    echo "ERROR: could not extract fix_ucm_pcm_index() from $INSTALLER" >&2
    exit 1
fi
eval "$FUNC_SRC"

# Dry run first: the logged sed command must carry the boundary-aware
# expressions and leave every fixture untouched.
DRY_RUN=1 fix_ucm_pcm_index
assert_contains 's/hw:${CardId},\([12]\)\([^0-9]\)/hw:${CardId},0\2/g' "$DRYRUN_LOG" "dry-run message missing left-boundary expression"
assert_contains 's/hw:${CardId},\([12]\)$/hw:${CardId},0/' "$DRYRUN_LOG" "dry-run message missing right-boundary expression"
dry_lines="$(wc -l < "$DRYRUN_LOG" 2> /dev/null || true)"
if [ "$dry_lines" = "${#FILES[@]}" ]; then
    ok
else
    fail "dry-run log should hold ${#FILES[@]} sed commands, got '${dry_lines:-0}'"
fi
for rel in "${FILES[@]}"; do
    if grep -qE 'hw:\$\{CardId\},[12]([^0-9]|$)' "$UCM_DST/$rel"; then
        ok
    else
        fail "$rel was modified during DRY_RUN=1"
    fi
done

# Run twice: the fix must apply ,1 and ,2 -> ,0 and stay idempotent.
DRY_RUN=0 fix_ucm_pcm_index
DRY_RUN=0 fix_ucm_pcm_index

for rel in "${FILES[@]}"; do
    f="$UCM_DST/$rel"
    if grep -qE 'hw:\$\{CardId\},[12]([^0-9]|$)' "$f"; then
        fail "$rel still has a stale single-digit PCM index: $(grep -oE 'hw:\$\{CardId\},[12]' "$f" | head -n 1)"
    else
        ok
    fi
    n0="$(grep -o 'hw:${CardId},0' "$f" | wc -l)"
    if [ "$n0" -eq 2 ]; then
        ok
    else
        fail "$rel: expected 2 rewritten hw:\${CardId},0 lines, got $n0"
    fi
    for keep in 3 10 12 20; do
        if grep -qF "hw:\${CardId},$keep" "$f"; then
            ok
        else
            fail "$rel: non-target PCM index ,$keep was modified"
        fi
    done
done

echo ""
echo "audio UCM PCM index tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
