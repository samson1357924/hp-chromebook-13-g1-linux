# 🔄 Uninstallation & Rollback Guide (chell)

All files installed via `setup.sh` are backed up to `/var/backups/cros-enablement/` with manifest.

## One-Click Full Uninstall

```bash
./setup.sh --uninstall
```

Removes:
1. Keyboard `hwdb` `/etc/udev/hwdb.d/90-chromebook-keyboard.hwdb`
2. Audio AVS diagnostics (no UCM to remove on chell, only WirePlumber tweaks if installed)
3. Power/EC tweaks, `c640-battery-limit`-style daemon
4. Restores original backups

## Per-Module

* **Keyboard only**: `./keyboard/install-keyboard.sh --uninstall`
* **Audio only**: `./audio/install-audio.sh --uninstall`
* **Power/EC only**: `./power/install-power.sh --uninstall` / `./ec/install-ec.sh --uninstall`
