<!-- markdownlint-disable MD013 -->

# 電源與休眠

Chell 暴露 `[s2idle] deep`（s2idle 預設，deep 可用；無硬體 S0ix Modern Standby）— `cat /sys/power/mem_sleep` 顯示 `[s2idle] deep`。

- TLP 設定：`power/tlp/99-hp-chell.conf`
- Modprobe：`power/modprobe.d/99-hp-chell-power.conf` (i915 psr/fbc/dc)
- Lid：`power/systemd/logind.conf.d/99-hp-chell-lid.conf`
- 電池上限：`ec/systemd/c640-battery-limit.service`（預設 90%，可透過 `/etc/default/c640-battery-limit` `BATTERY_LIMIT=85` 設定；透過 `./ec/install-ec.sh --enable-battery-limit 85` 啟用）— `Restart=always` 僅處理崩潰，不處理明確的 `systemctl stop`（stop 為預期的維護操作）。
- 鍵盤背光跟隨閒置（選用）：`power/kbd-follow-idle.sh` + `power/systemd/user/kbd-backlight-follow-idle.service` — 透過 `./ec/install-ec.sh --enable-kbd-follow-idle` 啟用（user service，監聽 `org.gnome.ScreenSaver` ActiveChanged，閒置時調暗至 0，喚醒時還原）。預設在 repo 停用；本機已直接啟用。
