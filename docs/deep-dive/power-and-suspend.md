# Power & Suspend

Chell exposes `[s2idle] deep` (s2idle default, deep available; no hardware S0ix Modern Standby) — `cat /sys/power/mem_sleep` shows `[s2idle] deep`.

- TLP profile: `power/tlp/99-hp-chell.conf`
- Modprobe: `power/modprobe.d/99-hp-chell-power.conf` (i915 psr/fbc/dc)
- Lid: `power/systemd/logind.conf.d/99-hp-chell-lid.conf`
- Battery limit: `ec/systemd/c640-battery-limit.service` (90% default,
  configurable via `/etc/default/c640-battery-limit` `BATTERY_LIMIT=85`;
  enable via `./ec/install-ec.sh --enable-battery-limit 85`)
  — `Restart=always` covers crashes, not explicit `systemctl stop`
  (stop is intentional maintenance).
- Keyboard backlight follow idle (opt-in): `power/kbd-follow-idle.sh` +
  `power/systemd/user/kbd-backlight-follow-idle.service`
  — enabled via `./ec/install-ec.sh --enable-kbd-follow-idle`
  (user service, monitors `org.gnome.ScreenSaver` ActiveChanged,
  dims to 0 on idle, restores on wake). Disabled by default in repo;
  directly enabled on this machine.
