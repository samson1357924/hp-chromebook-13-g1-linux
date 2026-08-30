<!-- markdownlint-disable MD013 -->
<!-- SPDX-License-Identifier: MIT -->
<!-- SPDX-FileCopyrightText: 2026 Samson <https://github.com/samson1357924> -->

# PITFALL-02: iGPU Alternatives During Installation (Beyond `nomodeset`)

> **Date**: 2026-08-29 | **Device**: HP Chromebook 13 G1 (Google `chell`,
> Skylake-Y HD515 `[8086:191e]`) | **Author**: samson1357924 |
> **Kernel**: 7.0.0-30-generic (Ubuntu 26.04.1 LTS) |
> **Firmware**: MrChromebox 2606.1

## Summary

PITFALL-01 (`01-safe-graphics-nomodeset.md`) uses `nomodeset` to disable
**all** DRM KMS drivers and fall back to `simpledrm`. This document
records alternatives that keep `i915` enabled during the USB installer
phase, for users who want hardware acceleration from the first boot or
want to avoid the `curtin` persistence trap.

Root cause recap (see `../../README.md` §3): panel requires `361.31 MHz`
(`xrandr --verbose` `361310`, `port_clock 540000 x4` from
`i915_display_info`), default `CDCLK 337.5 MHz` insufficient →
`CPU pipe A FIFO underrun` → black screen with backlight on but no
output. Fix raises CDCLK to `450 MHz` and disables conflicting
power-saving features.

## Decision Matrix

| # | Method | Keeps `i915`? | HW Accel in Live? | Status | Persistence Risk | Complexity | Recommended When |
|---|--------|:-------------:|:-----------------:|--------|:--------------:|------------|------------------|
| A | `i915.enable_psr=0 fbc=0 dc=0` via GRUB edit (primary alternative) | ✅ | ✅ | ✅ Verified 2026-08-29 | Low (you control) | Low | Want i915 from Live, single USB stick |
| B | `video=eDP-1:1920x1080@60` downscale | ✅ | ✅ (lower res) | ⚠️ Theory (unverified) | Low | Low | Panel timing suspected, quick test |
| C | `i915.modeset=0` / `modprobe.blacklist=i915` | ❌ (only i915) | ❌ | ⚠️ Theory | Low | Low | Need to isolate i915 vs other DRM |
| D | `nomodeset` (PITFALL-01 baseline) | ❌ (all DRM) | ❌ | ✅ Verified | **High** (Ubuntu `curtin` copies to `/etc/default/grub`) | Lowest | Guaranteed boot, novice |
| E | Custom EDID / `drm.edid_firmware` | ✅ | ✅ | ⚠️ Theory | High | High | Advanced, EDID override |
| F | Kernel/VBT rebuild (CDCLK floor patch) | ✅ | ✅ | ⚠️ Theory | Very High | Very High | Upstream contribution |

> **Project default remains D → `scripts/fix-graphics.sh` post-install**.
> A is the best *installer-phase* alternative to D if you understand
> GRUB editing. B/E/F are theoretical and need Live verification.

---

## A. `i915` Stable Parameters via GRUB Edit (Recommended Alternative)

**Effect**: Keeps `i915` bound to `card*`
(`/sys/class/drm/card*/device/driver -> i915`), enables `Mesa HD 515`
(`glxinfo` `direct rendering: Yes`), fixes FIFO by raising CDCLK.

**Steps at installer GRUB**:

1. Highlight `Try or Install Ubuntu`, press `e`.
2. Find line `linux /casper/vmlinuz ... quiet splash ---`.
3. Append **before** `---` (space-separated):

   ```text
   i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0
   ```

   Result:

   ```text
   linux /casper/vmlinuz ... quiet splash i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0 ---
   ```

4. Press `Ctrl+x` / `F10` to boot.
5. After installation, make persistent (same as `fix-graphics.sh` +
   manual GRUB edit):

   ```bash
   # Backup first (fix-graphics.sh does this)
   sudo cp /etc/default/grub /etc/default/grub.bak.$(date +%Y%m%d)
   sudo sed -i 's/ *nomodeset//g' /etc/default/grub
   # Add the three i915 params if not present
   if ! grep -q "i915.enable_psr=0" /etc/default/grub; then
     sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0/' /etc/default/grub
   fi
   grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
   # Expect: GRUB_CMDLINE_LINUX_DEFAULT="quiet splash i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0"
   sudo update-grub
   sudo update-initramfs -u
   ```

   Alternative: `sudo nano /etc/default/grub` and edit the same line
   manually. `power/modprobe.d/99-hp-chell-power.conf` provides
   `options i915 enable_psr=0 enable_fbc=0 enable_dc=0` via modprobe,
   but GRUB is the primary path for early KMS.

**Verification** (same as PITFALL-01 §5):

```bash
cat /proc/cmdline | grep -E "i915.enable_psr=0|i915.enable_fbc=0|i915.enable_dc=0" && echo "params OK"
lsmod | grep i915 && echo "i915 loaded"
# card1 when i915 is active, card0 when simpledrm; use wildcard
readlink /sys/class/drm/card*/device/driver | grep -q i915 && echo "DRM is i915"
glxinfo | grep "OpenGL renderer"  # Mesa Intel(R) HD Graphics 515
# port_clock from i915_display_info; CDCLK is inferred via FIFO near-zero + 450 MHz fix
sudo cat /sys/kernel/debug/dri/*/i915_display_info | grep -E "port_clock|lane_count"
# Expect: port_clock=540000 lane_count=4, mode "3200x1800": 60 361310
journalctl -k -b | grep -E "FIFO underrun|Atomic update failure"  # expect near-zero: 0 in last 3 boots, occasional single in 9 boots
cat /sys/class/backlight/intel_backlight/max_brightness  # 187, confirms i915 backlight
```

Note: `xrandr` logical resolution may show `3840x2160` due to GNOME
`scale-monitor-framebuffer`; trust `i915_display_info` `mode "3200x1800":60 361310`
for native timing.

**Trade-offs**:

* Pro: No `simpledrm` fallback, backlight (`intel_backlight`) and
  `snd_soc_avs: i915 init` work in Live.
* Con: Requires manual typing; typo (`enable_psr =0` with space)
  silently ignored.

**Evidence**: 2026-08-29, kernel 7.0.0-30,
`i915_display_info` shows `mode "3200x1800": 60 361310 ... port_clock=540000
lane_count=4`, `i915_dmc_info` `DC3->DC5 count: 0`,
`journalctl -k` FIFO near-zero (0 in last 3 boots, occasional single in 9 boots vs 6/6 boots with FIFO when undecorated).

---

## B. Downscale via `video=` (Bandwidth Workaround)

**Effect**: Reduces pixel clock below CDCLK 337.5 MHz, avoids FIFO
without necessarily touching PSR/FBC/DC. For `1920x1080@60` the CVT-RB
clock is `~148 MHz` < 337.5; higher custom modes must be calculated
(CVT timing).

```text
video=eDP-1:1920x1080@60
# or 2048x1536@60
```

Append like A at GRUB `linux` line **before** `---`. After install,
remove `video=` and apply A for native 3200x1800. Status: theory,
not verified in Live with PSR untouched; still recommended to use A.

**When to use**: Quick bisection to confirm panel timing vs PSR issue.
If 1920x1080 boots with plain `i915` (no psr/fbc/dc params), root cause
is primarily CDCLK.

**Limit**: Live runs at non-native resolution; must remember to revert.

---

## C. `i915.modeset=0` vs `modprobe.blacklist=i915` (Scope-Narrowed Disable)

```text
i915.modeset=0          # KMS off, module still loaded (deprecated parm)
modprobe.blacklist=i915 # prevent loading entirely
```

Both fall back to `simpledrm` (`journalctl -k` shows
`simpledrm 1.0.0 on minor 0`), but blast radius differs: `modeset=0`
only disables KMS, `blacklist` prevents the module. `curtin` persistence
for these params is theoretically similar to `nomodeset` but **unverified**
(the `curtin-install.log` evidence only covers `nomodeset`). Use only
for diagnosing "is i915 the culprit?" — not as final fix.

---

## D. `nomodeset` (Baseline, Documented in PITFALL-01)

Disables **all** DRM (`return -ENODEV` in `drm_core_init`). Verified to
always boot (`BOOT_IMAGE=... quiet splash nomodeset` in
`installer-journal.txt`), but Ubuntu `curtin` persists it to
`/target/etc/default/grub` → `/boot/grub/grub.cfg` with
`GRUB_TIMEOUT_STYLE=hidden` `TIMEOUT=0`, causing post-install
`lsmod | grep i915` empty and `xrandr` `None-1`. Fix via
`scripts/fix-graphics.sh`.

Keep as fallback for novices or when GRUB edit fails.

---

## E. Custom EDID / `drm.edid_firmware`

```text
drm.edid_firmware=eDP-1:edid/1920x1080.bin
```

Provide a firmware EDID under `/lib/firmware/edid/` that advertises a
lower clock. Requires rebuilding initramfs on the USB stick
(`update-initramfs -u` inside Live is ephemeral). The `video=eDP-1:e`
syntax (force-enable) is a `video=` option, not an EDID override.
High complexity; only for EDID hackers. Status: theory.

---

## F. Kernel / VBT Rebuild

Patch `drivers/gpu/drm/i915/display/intel_cdclk.c` to set Skylake-Y
CDCLK floor to 450 MHz, or rebuild VBT
(`$VBT SKYLAKE 1000 PC 14.34 1/21/2015` → add `LFP_PanelName` `SDC415A`
with correct `port_clock`). Out of scope for installer; track upstream
via `drm/i915` issues `#16791`/`#16825` referenced in
`../TROUBLESHOOTING.md`.

---

## Recommended Flow for Contributors

1. **First-time users**: Use D (`Ubuntu (safe graphics)`) → install →
   `scripts/fix-graphics.sh` (least error-prone).
2. **Power users / re-installs**: Use A directly at GRUB to get i915
   from Live; verify with `glxinfo`/`i915_display_info` before
   installing.
3. **Debugging**: Use B to bisect, C to isolate, F for upstream.

## Related Files

* `../../scripts/fix-graphics.sh` — post-install GRUB rewrite +
  `update-grub`/`update-initramfs -u`
* `../../power/modprobe.d/99-hp-chell-power.conf` — modprobe alternative
* `../deep-dive/i915-graphics-cdclk.md` — CDCLK root cause one-pager
* `01-safe-graphics-nomodeset.md` — `nomodeset` baseline
* `../TROUBLESHOOTING.md` — quick triage

## Repro Steps for Reviewers

On HP Chromebook 13 G1, MrChromebox 2606.1, Ubuntu 26.04.1 USB:

1. Boot USB, at GRUB apply A, boot.
2. In Live, run `lsmod | grep i915`, `glxinfo | grep renderer`,
    `journalctl -k | grep -E "FIFO underrun|Atomic update failure"` (expect near-zero: 0 in last 3 boots, occasional single in 9 boots),
   `cat /sys/class/backlight/intel_backlight/max_brightness`.
3. Install, reboot, confirm `cat /proc/cmdline` retains three i915
   params and no `nomodeset`.
4. Compare to D path: Live with `nomodeset`, post-install
   `fix-graphics.sh`, reboot, same verification.
