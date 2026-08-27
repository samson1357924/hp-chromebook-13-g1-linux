<!-- markdownlint-disable MD013 -->

# 電源與休眠

Chell 支援傳統 S3 `deep` 休眠（非 S0ix Modern Standby）。

- TLP 設定：`power/tlp/99-hp-chell.conf`
- Modprobe：`power/modprobe.d/99-hp-chell-power.conf` (i915 psr/fbc/dc)
- Lid：`power/systemd/logind.conf.d/99-hp-chell-lid.conf`
