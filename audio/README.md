# 🔊 Audio - HP Chromebook 13 G1 (chell, AVS)

Chell uses **AVS** (`avs_ssm4567`, `avs_nau8825`, `avs_dmic`) not SOF. 3 cards:

* Card0 SSM4567 Speakers, Card1 NAU8825 Headset, Card2 DMIC

Diagnose with `./audio/diagnose-audio.sh` and PipeWire `wpctl status`. No UCM  sof-rt5682 needed.

See `docs/pitfalls/` for installer graphics trap.
