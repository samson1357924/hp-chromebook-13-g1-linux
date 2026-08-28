#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Samson <https://github.com/samson1357924>
# power/kbd-follow-idle.sh - Optional keyboard backlight follow-screen-dim
# When GNOME screensaver/idle becomes active, dim kbd backlight to 0; restore on wake.
# Opt-in via: ./ec/install-ec.sh --enable-kbd-follow-idle
# User service: power/systemd/user/kbd-backlight-follow-idle.service
set -e

KBD_LED="/sys/class/leds/chromeos::kbd_backlight/brightness"
SAVED=""
SAVED_BRIGHTNESS_FILE="${XDG_RUNTIME_DIR:-/tmp}/kbd-backlight-saved"

get_kbd_brightness() {
    # Always use sysfs 0-100 to avoid gsd Steps (0-21) vs sysfs (0-100) mismatch
    cat "$KBD_LED" 2> /dev/null | tr -d ' \r\n' || echo "0"
}

set_kbd_brightness() {
    local val="$1"
    # Prefer gsd-power D-Bus (no sudo, no sysfs permission needed, respects systemd-backlight)
    if command -v busctl > /dev/null 2>&1; then
        local gsd_val=$(( val * 21 / 100 ))
        if busctl --user set-property org.gnome.SettingsDaemon.Power /org/gnome/SettingsDaemon/Power org.gnome.SettingsDaemon.Power.Keyboard Brightness i "$gsd_val" > /dev/null 2>&1; then
            # gsd will sync sysfs; also ensure sysfs if writable
            if [ -w "$KBD_LED" ]; then
                echo "$val" > "$KBD_LED" 2> /dev/null || true
            fi
            return 0
        fi
        if [ "$val" = "0" ]; then
            busctl --user call org.gnome.SettingsDaemon.Power /org/gnome/SettingsDaemon/Power org.gnome.SettingsDaemon.Power.Keyboard Toggle > /dev/null 2>&1 || true
        fi
    fi
    # Fallback sysfs (requires uaccess/plugdev via 61-chromeos-kbd-backlight.rules)
    if [ -w "$KBD_LED" ]; then
        echo "$val" > "$KBD_LED" 2> /dev/null || true
    else
        echo "[kbd-follow-idle] WARN: $KBD_LED not writable (need re-login for plugdev/uaccess)" >&2 || true
        if [ "$val" = "0" ] && command -v busctl > /dev/null 2>&1; then
            busctl --user call org.gnome.SettingsDaemon.Power /org/gnome/SettingsDaemon/Power org.gnome.SettingsDaemon.Power.Keyboard Toggle > /dev/null 2>&1 || true
        fi
    fi
}

save_and_dim() {
    local cur
    cur=$(get_kbd_brightness)
    if [ -z "$cur" ]; then cur="0"; fi
    # Debounce: if already dimmed, don't overwrite saved
    if [ -f "$SAVED_BRIGHTNESS_FILE" ] && [ "$(cat "$KBD_LED" 2> /dev/null || echo 0)" = "0" ]; then
        return 0
    fi
    if [ "$cur" != "0" ] && [ -n "$cur" ]; then
        echo "$cur" > "$SAVED_BRIGHTNESS_FILE" 2> /dev/null || true
        SAVED="$cur"
    fi
    set_kbd_brightness 0
}

restore() {
    local to_restore=""
    if [ -f "$SAVED_BRIGHTNESS_FILE" ]; then
        to_restore=$(cat "$SAVED_BRIGHTNESS_FILE" 2> /dev/null | tr -d ' \r\n' || echo "")
    fi
    if [ -z "$to_restore" ]; then to_restore="$SAVED"; fi
    # Fallback 50% (sysfs 0-100) instead of magic 25; preserve user choice
    if [ -z "$to_restore" ] || [ "$to_restore" = "0" ]; then to_restore="50"; fi
    set_kbd_brightness "$to_restore"
}

# Register IdleMonitor watches (dim) and listen for both ScreenSaver and IdleMonitor
echo "[kbd-follow-idle] listening for ScreenSaver + IdleMonitor (Ctrl+C to stop)" >&2

# Determine idle interval from gsettings (default 300s for lock, use 30s for dim if idle-dim enabled)
IDLE_DELAY=$(gsettings get org.gnome.desktop.session idle-delay 2> /dev/null | grep -oE '[0-9]+' | tail -n1 || echo 300)
if ! [[ "$IDLE_DELAY" =~ ^[0-9]+$ ]]; then IDLE_DELAY=300; fi
if gsettings get org.gnome.settings-daemon.plugins.power idle-dim 2> /dev/null | grep -q "true"; then
    DIM_INTERVAL=30000
else
    DIM_INTERVAL=$((IDLE_DELAY * 1000))
fi

IDLE_WATCH_ID=""
ACTIVE_WATCH_ID=""
if command -v gdbus > /dev/null 2>&1; then
    IDLE_WATCH_ID=$(gdbus call --session --dest org.gnome.Mutter.IdleMonitor --object-path /org/gnome/Mutter/IdleMonitor/Core --method org.gnome.Mutter.IdleMonitor.AddIdleWatch "$DIM_INTERVAL" 2> /dev/null | grep -oE '[0-9]+' | tail -n1 || echo "")
    ACTIVE_WATCH_ID=$(gdbus call --session --dest org.gnome.Mutter.IdleMonitor --object-path /org/gnome/Mutter/IdleMonitor/Core --method org.gnome.Mutter.IdleMonitor.AddUserActiveWatch 2> /dev/null | grep -oE '[0-9]+' | tail -n1 || echo "")
    echo "[kbd-follow-idle] registered IdleWatch $IDLE_WATCH_ID (${DIM_INTERVAL}ms) ActiveWatch $ACTIVE_WATCH_ID" >&2
fi

cleanup_watches() {
    [ -n "$IDLE_WATCH_ID" ] && gdbus call --session --dest org.gnome.Mutter.IdleMonitor --object-path /org/gnome/Mutter/IdleMonitor/Core --method org.gnome.Mutter.IdleMonitor.RemoveWatch "$IDLE_WATCH_ID" > /dev/null 2>&1 || true
    [ -n "$ACTIVE_WATCH_ID" ] && gdbus call --session --dest org.gnome.Mutter.IdleMonitor --object-path /org/gnome/Mutter/IdleMonitor/Core --method org.gnome.Mutter.IdleMonitor.RemoveWatch "$ACTIVE_WATCH_ID" > /dev/null 2>&1 || true
}
trap cleanup_watches EXIT

# Monitor ScreenSaver ActiveChanged
gdbus monitor --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver 2> /dev/null | while read -r line; do
    case "$line" in
        *"ActiveChanged"*"'true'"*)
            echo "[kbd-follow-idle] screen lock/active -> save & dim 0" >&2
            save_and_dim
            ;;
        *"ActiveChanged"*"'false'"*)
            echo "[kbd-follow-idle] screen wake -> restore" >&2
            restore
            ;;
    esac
done &
PID1=$!

# Monitor IdleMonitor WatchFired for dim/restore
gdbus monitor --session --dest org.gnome.Mutter.IdleMonitor --object-path /org/gnome/Mutter/IdleMonitor/Core 2> /dev/null | while read -r line; do
    case "$line" in
        *"WatchFired"*"uint32 $IDLE_WATCH_ID"*)
            echo "[kbd-follow-idle] idle WatchFired $IDLE_WATCH_ID -> dim 0" >&2
            save_and_dim
            ;;
        *"WatchFired"*"uint32 $ACTIVE_WATCH_ID"*)
            echo "[kbd-follow-idle] active WatchFired $ACTIVE_WATCH_ID -> restore" >&2
            restore
            ;;
        # Fallback heuristic if IDs not matched
        *"WatchFired"* )
            # Only handle if IDs were not captured
            if [ -z "$IDLE_WATCH_ID" ]; then
                echo "[kbd-follow-idle] idle WatchFired (fallback) -> dim 0" >&2
                save_and_dim
            fi
            ;;
    esac
done &
PID2=$!

wait $PID1 $PID2
