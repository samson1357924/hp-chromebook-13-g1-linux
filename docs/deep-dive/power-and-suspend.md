# Power & Suspend

Chell supports traditional S3 `deep` sleep (not S0ix Modern Standby).

- TLP profile: `power/tlp/99-hp-chell.conf`
- Modprobe: `power/modprobe.d/99-hp-chell-power.conf` (i915 psr/fbc/dc)
- Lid: `power/systemd/logind.conf.d/99-hp-chell-lid.conf`
