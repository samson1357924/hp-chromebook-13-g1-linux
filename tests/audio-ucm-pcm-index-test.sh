#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Samson <https://github.com/samson1357924>
# tests/audio-ucm-pcm-index-test.sh - Hermetic regression test for the UCM PCM
# index fix in audio/install-audio.sh (hw:${CardId},1|,2 -> hw:${CardId},0).
#
# The real installer is sourced (its CLI is guarded by BASH_SOURCE) and its
# functions run against a sandboxed fake UCM tree, so no root, ALSA or
# PipeWire state is touched. The exact post-fix file content is compared, not
# just substrings: a sed expression that drops a closing quote must fail.
#
#   bash tests/audio-ucm-pcm-index-test.sh
set -euo pipefail

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

assert_eq() {
    # $1=expected $2=actual $3=message
    if [ "$1" = "$2" ]; then
        ok
    else
        fail "$3 (expected: '$1', got: '$2')"
    fi
}

assert_contains() {
    # $1=needle $2=file $3=message
    if grep -qF -- "$1" "$2"; then
        ok
    else
        fail "$3 (missing: $1)"
    fi
}

assert_files_equal() {
    # $1=expected file $2=actual file $3=message
    if diff -u "$1" "$2" > "$SANDBOX/diff.txt"; then
        ok
    else
        cat "$SANDBOX/diff.txt" >&2
        fail "$3"
    fi
}

assert_success() {
    # Run a command expected to succeed; a nonzero status becomes a FAIL with
    # context instead of aborting the whole test without a summary.
    if "$@"; then
        ok
    else
        fail "unexpected failure: $*"
    fi
}

# ---------------------------------------------------------------------------
# Sandbox: backup/manifest dirs and a sudo shim that really executes commands
# ---------------------------------------------------------------------------
export CROS_ENABLEMENT_BACKUP_DIR="$SANDBOX/backups"
export CROS_ENABLEMENT_MANIFEST_DIR="$SANDBOX/manifest"
export CROS_ENABLEMENT_ALLOWED_PREFIXES="$SANDBOX/ucm/ $SANDBOX/conf.d/"
export LOG_FILE="$SANDBOX/test.log"
mkdir -p "$SANDBOX/bin" "$SANDBOX/backups" "$SANDBOX/manifest"

cat > "$SANDBOX/bin/sudo" << 'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in
        -n | -E | -H) shift ;;
        -u) shift 2 ;;
        --user) shift 2 ;;
        --) shift; break ;;
        [A-Za-z_]*=*) export "$1"; shift ;;
        *) break ;;
    esac
done
exec "$@"
EOF
cat > "$SANDBOX/bin/systemctl" << 'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SANDBOX/systemctl.log"
exit 0
EOF
chmod +x "$SANDBOX/bin/sudo" "$SANDBOX/bin/systemctl"
export SANDBOX
export PATH="$SANDBOX/bin:$PATH"

# shellcheck source=../audio/install-audio.sh
source "$INSTALLER"

# Keep the test output readable; record warnings for assertions.
log_info() { :; }
log_success() { :; }
log_error() { echo "ERROR: $*" >&2; }
WARN_LOG="$SANDBOX/warn.log"
log_warn() { printf '%s\n' "$*" >> "$WARN_LOG"; }
DRYRUN_LOG="$SANDBOX/dryrun.log"
log_dryrun() { printf '%s\n' "$*" >> "$DRYRUN_LOG"; }

UCM_DST="$SANDBOX/ucm"
AVS_OBSOLETE_PARAM="$SANDBOX/obsolete_card_names"
AVS_KERNEL_RELEASE="7.0.0"
AVS_MODPROBE_DIR="$SANDBOX/modprobe.d"
AVS_CMDLINE_FILE="$SANDBOX/cmdline"
mkdir -p "$AVS_MODPROBE_DIR"
: > "$AVS_CMDLINE_FILE"
rm -f "$AVS_OBSOLETE_PARAM"

FILES=(
    "Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf"
    "Intel/avs/avs_nau8825/avs_nau8825-HiFi.conf"
    "Intel/avs/avs_dmic/DMIC-2ch-HiFi.conf"
    "Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf"
)
INCLUDE_FILE="Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0-HiFi.conf"

legacy_index() {
    case "$1" in
        *avs_dmic*) echo 2 ;;
        *) echo 1 ;;
    esac
}

write_fixture() {
    # $1=relative path $2=legacy index
    local rel="$1" idx="$2"
    mkdir -p "$UCM_DST/$(dirname "$rel")"
    {
        printf '%s\n' 'SectionDevice."Speaker" {'
        printf '\t%s\n' "PlaybackPCM \"hw:\${CardId},${idx}\""
        printf '\t%s\n' "CapturePCM \"hw:\${CardId},${idx}\""
        printf '\t%s\n' "Trailing hw:\${CardId},${idx}"
        printf '\t%s\n' "Two \"hw:\${CardId},${idx} hw:\${CardId},${idx}\""
        printf '\t%s\n' "Comma \"hw:\${CardId},${idx}, x\""
        printf '\t%s\n' 'KeepMe "hw:${CardId},3"'
        printf '\t%s\n' 'Keep10 "hw:${CardId},10"'
        printf '\t%s\n' 'Keep12 "hw:${CardId},12"'
        printf '\t%s\n' 'Keep20 "hw:${CardId},20"'
        printf '%s\n' '}'
    } > "$UCM_DST/$rel"
}

write_expected() {
    # $1=relative path — post-fix content with every ,1/,2 turned into ,0
    local rel="$1"
    mkdir -p "$SANDBOX/expected/$(dirname "$rel")"
    {
        printf '%s\n' 'SectionDevice."Speaker" {'
        printf '\t%s\n' 'PlaybackPCM "hw:${CardId},0"'
        printf '\t%s\n' 'CapturePCM "hw:${CardId},0"'
        printf '\t%s\n' 'Trailing hw:${CardId},0'
        printf '\t%s\n' 'Two "hw:${CardId},0 hw:${CardId},0"'
        printf '\t%s\n' 'Comma "hw:${CardId},0, x"'
        printf '\t%s\n' 'KeepMe "hw:${CardId},3"'
        printf '\t%s\n' 'Keep10 "hw:${CardId},10"'
        printf '\t%s\n' 'Keep12 "hw:${CardId},12"'
        printf '\t%s\n' 'Keep20 "hw:${CardId},20"'
        printf '%s\n' '}'
    } > "$SANDBOX/expected/$rel"
}

setup_tree() {
    # Every fixture starts with the legacy ,1/,2 indices; the active numbering
    # mode decides whether the functions rewrite or preserve them.
    rm -rf "$UCM_DST" "$SANDBOX/expected" "$SANDBOX/backups" "$SANDBOX/manifest"
    mkdir -p "$UCM_DST" "$SANDBOX/backups" "$SANDBOX/manifest"
    : > "$WARN_LOG"
    : > "$DRYRUN_LOG"
    local rel
    for rel in "${FILES[@]}"; do
        write_fixture "$rel" "$(legacy_index "$rel")"
    done
    mkdir -p "$UCM_DST/$(dirname "$INCLUDE_FILE")"
    printf 'Include.top.File "/Intel/avs/avs_nau8825/avs_nau8825-HiFi.conf"\n' > "$UCM_DST/$INCLUDE_FILE"
}

# ---------------------------------------------------------------------------
# 1. New numbering (kernel >= 6.16): --check detects stale files
# ---------------------------------------------------------------------------
setup_tree
assert_eq "new" "$(AVS_KERNEL_RELEASE=6.16.0 avs_numbering_mode)" "6.16 should select the new numbering"
if check_ucm_pcm_index; then
    fail "check_ucm_pcm_index should fail on stale ,1/,2 indices"
else
    ok
fi
assert_contains "still contains" "$WARN_LOG" "--check should report the stale index"
assert_eq "${#FILES[@]}" "$(grep -c 'still contains' "$WARN_LOG")" "--check should report every stale PCM file"

# ---------------------------------------------------------------------------
# 2. Dry run leaves files untouched and logs the boundary-aware sed commands
# ---------------------------------------------------------------------------
cp -a "$UCM_DST" "$SANDBOX/before-dry-run"
DRY_RUN=1 assert_success fix_ucm_pcm_index
assert_eq "${#FILES[@]}" "$(grep -c 'sed -i' "$DRYRUN_LOG" || true)" "dry-run should log one sed per stale file"
assert_contains 's/hw:${CardId},\([12]\)\([^0-9]\)/hw:${CardId},0\2/g' "$DRYRUN_LOG" "dry-run message missing left-boundary expression"
assert_contains 's/hw:${CardId},\([12]\)$/hw:${CardId},0/' "$DRYRUN_LOG" "dry-run message missing right-boundary expression"
for rel in "${FILES[@]}"; do
    assert_files_equal "$SANDBOX/before-dry-run/$rel" "$UCM_DST/$rel" "$rel was modified during DRY_RUN=1"
done
assert_eq "0" "$(find "$SANDBOX/backups" -type f | wc -l)" "DRY_RUN must not create backups"
if [ -f "$SANDBOX/manifest/install-manifest.json" ]; then
    fail "DRY_RUN must not write the install manifest"
else
    ok
fi

# ---------------------------------------------------------------------------
# 3. New numbering: exact content, pre-fix backups, manifest metadata
# ---------------------------------------------------------------------------
DRY_RUN=0 assert_success fix_ucm_pcm_index
for rel in "${FILES[@]}"; do
    write_expected "$rel"
    assert_files_equal "$SANDBOX/expected/$rel" "$UCM_DST/$rel" "$rel was not rewritten exactly"
done
assert_eq "${#FILES[@]}" "$(find "$SANDBOX/backups" -type f | wc -l)" "each patched file should be backed up once"
for rel in "${FILES[@]}"; do
    backup="$(find "$SANDBOX/backups" -type f -path "*$rel" | head -n 1)"
    assert_files_equal "$SANDBOX/before-dry-run/$rel" "$backup" "backup for $rel must hold the pre-fix bytes"
done
assert_eq "ok" "$(
    python3 - "$SANDBOX/manifest/install-manifest.json" "$UCM_DST" "${FILES[@]}" << 'PY'
import json, os, sys
manifest, ucm = sys.argv[1], sys.argv[2]
expected = {os.path.join(ucm, rel) for rel in sys.argv[3:]}
data = json.load(open(manifest))
records = data.get("records", [])
errors = []
if len(records) != len(expected):
    errors.append(f"record count {len(records)} != {len(expected)}")
if {r["target"] for r in records} != expected:
    errors.append("target set mismatch")
if not all(r["component"] == "audio" for r in records):
    errors.append("component mismatch")
if not all(r["was_existing"] is True for r in records):
    errors.append("was_existing mismatch")
if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
print("ok")
PY
)" "manifest records must list every patched file as component audio/existing"
assert_eq "0" "$(find "$UCM_DST" -name '*.bak' | wc -l)" "sed must not leave .bak files in the UCM tree"

if check_ucm_pcm_index; then
    ok
else
    fail "check_ucm_pcm_index should pass after the fix"
fi

# The install persisted files are now correct; deleting one must still be
# reported as a failure (and not masked by stale-index warnings).
mv "$UCM_DST/Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf" "$SANDBOX/missing.conf"
: > "$WARN_LOG"
if check_ucm_pcm_index; then
    fail "check_ucm_pcm_index should fail when a UCM file is missing"
else
    ok
fi
assert_contains "Missing UCM file" "$WARN_LOG" "--check should report a missing UCM file"
if grep -q "still contains" "$WARN_LOG"; then
    fail "the missing-file run must not be masked by stale-index warnings"
else
    ok
fi
mv "$SANDBOX/missing.conf" "$UCM_DST/Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf"

# A second run must be a no-op (same bytes, no new backups).
cp -a "$UCM_DST" "$SANDBOX/after-fix"
DRY_RUN=0 assert_success fix_ucm_pcm_index
for rel in "${FILES[@]}"; do
    assert_files_equal "$SANDBOX/after-fix/$rel" "$UCM_DST/$rel" "second run changed $rel"
done
assert_eq "${#FILES[@]}" "$(find "$SANDBOX/backups" -type f | wc -l)" "idempotent run must not create new backups"

# ---------------------------------------------------------------------------
# 4. Boundary: ,12 before ,2 must report the real stale index (2), not 1
# ---------------------------------------------------------------------------
printf 'A "hw:${CardId},12"\nB "hw:${CardId},2"\n' > "$SANDBOX/index.conf"
assert_eq "2" "$(ucm_pcm_index_of "$SANDBOX/index.conf")" "boundary-aware index extraction should ignore ,12"

# The real Chell Include-only fragment has no PCM index: it must be left
# untouched, not backed up, and accepted by --check.
setup_tree
DRY_RUN=0 assert_success fix_ucm_pcm_index
assert_eq 'Include.top.File "/Intel/avs/avs_nau8825/avs_nau8825-HiFi.conf"' "$(cat "$UCM_DST/$INCLUDE_FILE")" "Include-only UCM file was modified"
assert_eq "0" "$(find "$SANDBOX/backups" -type f -path "*$INCLUDE_FILE" | wc -l)" "Include-only UCM file must not be backed up"
if check_ucm_pcm_index; then
    ok
else
    fail "Include-only UCM files should not be treated as broken"
fi

# Empty/truncated UCM files are not valid Include-only fragments.
cp "$UCM_DST/$INCLUDE_FILE" "$SANDBOX/include-only.conf"
: > "$UCM_DST/$INCLUDE_FILE"
if check_ucm_pcm_index; then
    fail "empty UCM files must fail --check"
else
    ok
fi
cp "$SANDBOX/include-only.conf" "$UCM_DST/$INCLUDE_FILE"

# A literal but unexpected index (,3) must fail both --check and install.
printf 'CapturePCM "hw:${CardId},3"\n' > "$UCM_DST/Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf"
if check_ucm_pcm_index; then
    fail "unexpected PCM index ,3 must fail --check"
else
    ok
fi
if fix_ucm_pcm_index; then
    fail "fix_ucm_pcm_index should fail on an unexpected PCM index"
else
    ok
fi

# A missing required file must also fail fix (install must not claim success).
setup_tree
DRY_RUN=0 assert_success fix_ucm_pcm_index
rm "$UCM_DST/Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf"
if check_ucm_pcm_index; then
    fail "missing UCM file must fail --check"
else
    ok
fi
if fix_ucm_pcm_index; then
    fail "fix_ucm_pcm_index should fail when a required UCM file is missing"
else
    ok
fi

# ---------------------------------------------------------------------------
# 5. Legacy numbering (< 6.16 or obsolete_card_names=1): no rewrite
# ---------------------------------------------------------------------------
setup_tree
printf 'Y\n' > "$AVS_OBSOLETE_PARAM"
cp -a "$UCM_DST" "$SANDBOX/before-legacy"
if check_ucm_pcm_index; then
    ok
else
    fail "legacy ,1/,2 indices should be accepted when obsolete_card_names=1"
fi
DRY_RUN=0 assert_success fix_ucm_pcm_index
for rel in "${FILES[@]}"; do
    assert_files_equal "$SANDBOX/before-legacy/$rel" "$UCM_DST/$rel" "$rel must not be rewritten on legacy numbering"
done

# A patched file under legacy numbering is a mismatch and must be flagged by
# both --check and the installer (which cannot guess the right legacy index).
sed -i 's/,1"/,0"/' "$UCM_DST/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf"
if check_ucm_pcm_index; then
    fail "legacy numbering should flag a patched ,0 UCM file"
else
    ok
fi
if fix_ucm_pcm_index; then
    fail "fix_ucm_pcm_index should fail on a legacy/new mismatched UCM file"
else
    ok
fi

# Legacy numbering must also fail on missing files and unexpected indices.
setup_tree
printf 'Y\n' > "$AVS_OBSOLETE_PARAM"
rm "$UCM_DST/Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf"
if check_ucm_pcm_index; then
    fail "legacy --check should fail on a missing UCM file"
else
    ok
fi
if fix_ucm_pcm_index; then
    fail "legacy fix should fail on a missing UCM file"
else
    ok
fi
setup_tree
printf 'CapturePCM "hw:${CardId},3"\n' > "$UCM_DST/Intel/avs/avs_dmic/DMIC-4ch-HiFi.conf"
if check_ucm_pcm_index; then
    fail "legacy --check should fail on an unexpected PCM index"
else
    ok
fi
if fix_ucm_pcm_index; then
    fail "legacy fix should fail on an unexpected PCM index"
else
    ok
fi

# Kernel release fallback: 6.15 is legacy, 6.16 is new.
rm -f "$AVS_OBSOLETE_PARAM"
AVS_KERNEL_RELEASE="6.15.0"
setup_tree
if check_ucm_pcm_index; then
    ok
else
    fail "kernel 6.15 should use legacy numbering"
fi
AVS_KERNEL_RELEASE="6.16.0"
setup_tree
DRY_RUN=0 assert_success fix_ucm_pcm_index
for rel in "${FILES[@]}"; do
    write_expected "$rel"
    assert_files_equal "$SANDBOX/expected/$rel" "$UCM_DST/$rel" "kernel 6.16 must rewrite $rel to ,0 exactly"
done
if check_ucm_pcm_index; then
    ok
else
    fail "kernel 6.16 should use new numbering and the fix should pass --check"
fi

# ---------------------------------------------------------------------------
# 6. avs_numbering_mode() matrix: parameter wins, release fallback, overrides
# ---------------------------------------------------------------------------
rm -f "$AVS_OBSOLETE_PARAM"
: > "$AVS_CMDLINE_FILE"
rm -f "$AVS_MODPROBE_DIR"/*.conf 2> /dev/null || true
for rel in 5.15.0 6.9.0 6.15.0-38-generic; do
    assert_eq "legacy" "$(AVS_KERNEL_RELEASE="$rel" avs_numbering_mode)" "kernel $rel should be legacy"
done
for rel in 6.16.0 6.16.0-38-generic 6.17.2 7.0.0-38-generic 10.1.0; do
    assert_eq "new" "$(AVS_KERNEL_RELEASE="$rel" avs_numbering_mode)" "kernel $rel should be new"
done
assert_eq "legacy" "$(AVS_KERNEL_RELEASE="not-a-release" avs_numbering_mode)" "unparseable release should fall back to legacy"

for val in 1 Y yes on true; do
    printf '%s\n' "$val" > "$AVS_OBSOLETE_PARAM"
    assert_eq "legacy" "$(AVS_KERNEL_RELEASE=7.0.0 avs_numbering_mode)" "obsolete_card_names=$val should mean legacy"
done
for val in 0 N no off false; do
    printf '%s\n' "$val" > "$AVS_OBSOLETE_PARAM"
    assert_eq "new" "$(AVS_KERNEL_RELEASE=5.15.0 avs_numbering_mode)" "obsolete_card_names=$val should mean new"
done
rm -f "$AVS_OBSOLETE_PARAM"

# Module not loaded yet: honor modprobe.d / kernel cmdline overrides.
printf 'options snd-soc-avs obsolete_card_names=1\n' > "$AVS_MODPROBE_DIR/avs.conf"
assert_eq "legacy" "$(AVS_KERNEL_RELEASE=7.0.0 avs_numbering_mode)" "modprobe.d override should mean legacy"
printf 'options snd-soc-avs obsolete_card_names=YES\n' > "$AVS_MODPROBE_DIR/avs.conf"
assert_eq "legacy" "$(AVS_KERNEL_RELEASE=7.0.0 avs_numbering_mode)" "modprobe.d uppercase value should mean legacy"
printf 'options snd-soc-avs obsolete_card_names=1\noptions snd-soc-avs obsolete_card_names=0\n' > "$AVS_MODPROBE_DIR/avs.conf"
assert_eq "new" "$(AVS_KERNEL_RELEASE=7.0.0 avs_numbering_mode)" "last modprobe.d option should win (1 then 0)"
printf 'options snd-soc-avs obsolete_card_names=0\noptions snd-soc-avs obsolete_card_names=ON\n' > "$AVS_MODPROBE_DIR/avs.conf"
assert_eq "legacy" "$(AVS_KERNEL_RELEASE=7.0.0 avs_numbering_mode)" "last modprobe.d option should win (0 then ON)"
printf 'options unrelated obsolete_card_names=1\n' > "$AVS_MODPROBE_DIR/avs.conf"
assert_eq "new" "$(AVS_KERNEL_RELEASE=7.0.0 avs_numbering_mode)" "unrelated module option must be ignored"
printf '# options snd-soc-avs obsolete_card_names=1\n' > "$AVS_MODPROBE_DIR/avs.conf"
assert_eq "new" "$(AVS_KERNEL_RELEASE=7.0.0 avs_numbering_mode)" "commented modprobe.d line must be ignored"
rm -f "$AVS_MODPROBE_DIR/avs.conf"

printf 'quiet snd-soc-avs.obsolete_card_names=TRUE\n' > "$AVS_CMDLINE_FILE"
assert_eq "legacy" "$(AVS_KERNEL_RELEASE=7.0.0 avs_numbering_mode)" "kernel cmdline uppercase override should mean legacy"
printf 'snd-soc-avs.obsolete_card_names=0 snd-soc-avs.obsolete_card_names=1\n' > "$AVS_CMDLINE_FILE"
assert_eq "legacy" "$(AVS_KERNEL_RELEASE=7.0.0 avs_numbering_mode)" "last cmdline override should win"
rm -f "$AVS_MODPROBE_DIR/avs.conf"
printf 'options snd-soc-avs obsolete_card_names=1\n' > "$AVS_MODPROBE_DIR/avs.conf"
printf 'snd-soc-avs.obsolete_card_names=0\n' > "$AVS_CMDLINE_FILE"
assert_eq "new" "$(AVS_KERNEL_RELEASE=7.0.0 avs_numbering_mode)" "cmdline should win over modprobe.d"
: > "$AVS_CMDLINE_FILE"
rm -f "$AVS_MODPROBE_DIR/avs.conf"

# ---------------------------------------------------------------------------
# 9. Package upgrade refresh: rollback restores the upgraded file, not v1
# ---------------------------------------------------------------------------
setup_tree
DRY_RUN=0 assert_success fix_ucm_pcm_index
upgraded="$UCM_DST/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0-HiFi.conf"
printf 'PlaybackPCM "hw:${CardId},1"\nUpgraded stock content\n' > "$upgraded"
DRY_RUN=0 assert_success fix_ucm_pcm_index
assert_eq "5" "$(find "$SANDBOX/backups" -type f | wc -l)" "package upgrade should create one refreshed backup"
set +e
rollback_component "audio" > "$SANDBOX/rollback-upgrade.out" 2>&1
upgrade_rc=$?
set -e
assert_eq "0" "$upgrade_rc" "rollback after package upgrade should succeed"
assert_contains "Upgraded stock content" "$upgraded" "rollback should restore the upgraded stock file"

# ---------------------------------------------------------------------------
# 10. Fallback symlink refresh: a package-provided replacement is backed up
# ---------------------------------------------------------------------------
setup_tree
mkdir -p "$UCM_DST/Intel/avs/avs_ssm4567" "$UCM_DST/Intel/avs/avs_nau8825" "$UCM_DST/Intel/avs/avs_dmic"
printf 'src\n' > "$UCM_DST/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0.conf"
printf 'src\n' > "$UCM_DST/Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0.conf"
printf 'src\n' > "$UCM_DST/Intel/avs/avs_dmic/DMIC-2ch.conf"
DRY_RUN=0 assert_success fix_ucm_fallbacks
replaced="$UCM_DST/conf.d/avs_ssm4567/AVS I2S SSM4567.conf"
rm -f "$replaced"
printf 'PACKAGE PROVIDED FILE\n' > "$replaced"
DRY_RUN=0 assert_success fix_ucm_fallbacks
assert_eq "src" "$(cat "$replaced")" "fallback refresh should relink to the source"
if [ -L "$replaced" ]; then ok; else fail "fallback refresh should replace the package file with a symlink"; fi
set +e
rollback_component "audio" > "$SANDBOX/rollback-fallback.out" 2>&1
fallback_rc=$?
set -e
assert_eq "0" "$fallback_rc" "fallback rollback should succeed"
assert_contains "PACKAGE PROVIDED FILE" "$replaced" "fallback rollback should restore the package-provided file"

# ---------------------------------------------------------------------------
# 7. Uninstall without a manifest is an idempotent no-op (dry-run and real)
# ---------------------------------------------------------------------------
rm -f "$SANDBOX/manifest/install-manifest.json"
: > "$WARN_LOG"
: > "$DRYRUN_LOG"
DRY_RUN=1
if uninstall_audio > "$SANDBOX/uninstall.out" 2>&1; then
    ok
else
    fail "uninstall without a manifest should be a no-op success"
fi
assert_contains "No install manifest" "$WARN_LOG" "uninstall should warn about the missing manifest"
assert_eq "0" "$(grep -c 'Would restart' "$DRYRUN_LOG" || true)" "no restart should be scheduled without a manifest"

: > "$WARN_LOG"
: > "$SANDBOX/systemctl.log"
DRY_RUN=0
set +e
uninstall_audio > "$SANDBOX/uninstall-real.out" 2>&1
uninstall_rc=$?
set -e
assert_eq "0" "$uninstall_rc" "non-dry-run uninstall without a manifest should succeed"
if grep -q "Rollback complete" "$SANDBOX/uninstall-real.out"; then
    fail "non-dry-run uninstall must not claim success without a manifest"
else
    ok
fi
assert_eq "0" "$(wc -l < "$SANDBOX/systemctl.log")" "non-dry-run uninstall must not restart services without a manifest"

# A corrupt manifest must make rollback fail loudly, not print success.
printf '{invalid json\n' > "$SANDBOX/manifest/install-manifest.json"
set +e
rollback_component "audio" > "$SANDBOX/rollback-corrupt.out" 2>&1
corrupt_rc=$?
set -e
if [ "$corrupt_rc" -ne 0 ]; then
    ok
else
    fail "rollback_component should fail on a corrupt manifest"
fi
assert_contains "Rollback failed" "$SANDBOX/rollback-corrupt.out" "corrupt manifest should produce a rollback error"
rm -f "$SANDBOX/manifest/install-manifest.json"

# ---------------------------------------------------------------------------
# 8. Wiring: the fix and the check must stay reachable from the real CLI paths
# ---------------------------------------------------------------------------
if grep -qE '^[[:space:]]*if ! fix_ucm_pcm_index; then' "$INSTALLER"; then
    ok
else
    fail "install_audio no longer calls fix_ucm_pcm_index"
fi
if grep -qE '^[[:space:]]*check_ucm_pcm_index[[:space:]]*\|\|[[:space:]]*miss=1[[:space:]]*$' "$INSTALLER"; then
    ok
else
    fail "check_audio_status no longer fails on check_ucm_pcm_index"
fi
if grep -qE '^[[:space:]]*return "\$miss"[[:space:]]*$' "$INSTALLER"; then
    ok
else
    fail "check_audio_status no longer returns its accumulated miss status"
fi

# Functional install wiring: install_audio must call the fix (DRY_RUN keeps
# every other step inert; the real fix is replaced by a marker).
rm -f "$SANDBOX/install-fix-called"
(
    check_dmi_board() { :; }
    check_avs_modules_local() { :; }
    check_avs_firmware_local() { :; }
    fix_ucm_fallbacks() { :; }
    fix_ucm_pcm_index() { printf 'called\n' > "$SANDBOX/install-fix-called"; }
    deploy_wireplumber() { :; }
    get_real_user() { id -un; }
    get_real_user_uid() { id -u; }
    DRY_RUN=1 install_audio > /dev/null 2>&1
) || fail "DRY_RUN install_audio failed unexpectedly"
if [ -f "$SANDBOX/install-fix-called" ]; then
    ok
else
    fail "install_audio did not call fix_ucm_pcm_index"
fi

# A failed PCM index fix must abort install before deploying any config.
rm -f "$SANDBOX/deploy-after-pcm-fail"
if (
    check_dmi_board() { :; }
    check_avs_modules_local() { :; }
    check_avs_firmware_local() { :; }
    fix_ucm_fallbacks() { :; }
    fix_ucm_pcm_index() { return 1; }
    deploy_wireplumber() { : > "$SANDBOX/deploy-after-pcm-fail"; }
    get_real_user() { id -un; }
    get_real_user_uid() { id -u; }
    DRY_RUN=1 install_audio
) > /dev/null 2>&1; then
    fail "install_audio should abort when fix_ucm_pcm_index fails"
else
    ok
fi
if [ -e "$SANDBOX/deploy-after-pcm-fail" ]; then
    fail "install_audio continued after a PCM index failure"
else
    ok
fi

# A failed fallback fix must abort before the PCM step.
rm -f "$SANDBOX/pcm-after-fallback-fail"
if (
    check_dmi_board() { :; }
    check_avs_modules_local() { :; }
    check_avs_firmware_local() { :; }
    fix_ucm_fallbacks() { return 1; }
    fix_ucm_pcm_index() { : > "$SANDBOX/pcm-after-fallback-fail"; }
    deploy_wireplumber() { :; }
    get_real_user() { id -un; }
    get_real_user_uid() { id -u; }
    DRY_RUN=1 install_audio
) > /dev/null 2>&1; then
    fail "install_audio should abort when fix_ucm_fallbacks fails"
else
    ok
fi
if [ -e "$SANDBOX/pcm-after-fallback-fail" ]; then
    fail "install_audio continued after a fallback failure"
else
    ok
fi

# Functional --check wiring: a failed PCM check must make check_audio_status
# return nonzero, and a passing one must not.
make_check_tree() {
    UCM_DST="$SANDBOX/check-ucm"
    WP_DST="$SANDBOX/check-wp"
    rm -rf "$UCM_DST" "$WP_DST"
    mkdir -p "$UCM_DST/conf.d" "$WP_DST"
    touch "$WP_DST/50-avs-chell.conf" "$WP_DST/50-disable-suspend.conf"
    local rel
    for rel in \
        "avs_ssm4567/AVS I2S SSM4567.conf" \
        "avs_ssm4567/avs_ssm4567.conf" \
        "avs_nau8825/AVS I2S NAU8825.conf" \
        "avs_nau8825/avs_nau8825.conf" \
        "avs_dmic/AVS DMIC.conf" \
        "avs_dmic/avs_dmic.conf" \
        "avs_hdaudio/AVS HDMI.conf" \
        "avs_hdaudio/avs_hdaudio.conf"; do
        mkdir -p "$UCM_DST/conf.d/$(dirname "$rel")"
        : > "$UCM_DST/conf.d/$rel"
    done
}
if (
    make_check_tree
    check_dmi_board() { :; }
    check_avs_modules_local() { :; }
    check_avs_firmware_local() { :; }
    check_ucm_pcm_index() { return 1; }
    check_audio_status
) > /dev/null 2>&1; then
    fail "check_audio_status should fail when the PCM check fails"
else
    ok
fi
if (
    make_check_tree
    check_dmi_board() { :; }
    check_avs_modules_local() { :; }
    check_avs_firmware_local() { :; }
    check_ucm_pcm_index() { return 0; }
    check_audio_status
) > /dev/null 2>&1; then
    ok
else
    fail "check_audio_status should pass when all UCM checks pass"
fi

echo ""
echo "audio UCM PCM index tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
