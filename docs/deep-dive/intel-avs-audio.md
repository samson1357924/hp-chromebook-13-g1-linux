<!-- markdownlint-disable MD013 -->

# Intel AVS Audio on Chell (SSM4567/NAU8825)

This device uses **Intel AVS** (`snd_soc_avs`), not SOF. See the [Audio README](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/README.md), [Root Cause](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/docs/root-cause.md) and [Upstream Status](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/docs/upstream.md) for the full write-up.

## Cards & Routing

- Cards (use ALSA IDs, card numbers are non-deterministic): `avs_ssm4567` (Speakers `hw:SSM4567`), `avs_nau8825` (Headphones `hw:NAU8825`), `avs_dmic` (Mic `hw:DMIC`), `avs_hdaudio` (HDMI `hw:HDMI`) — SSM4567/NAU8825/DMIC expose PCM device `0` only; `avs_hdaudio` keeps devices `0`-`2` (HDMI1-HDMI3).
- UCM: the distro `alsa-ucm-conf` is patched in place by `audio/install-audio.sh` (`conf.d` fallback symlinks + PCM indices `,1`/`,2` -> `,0` + mixers); Chell never needs SOF UCM.
- WirePlumber: `50-avs-chell.conf` sets Headphones 2000 > Speakers 1500 > HDMI 500 (HDMI priority tie fix).
- Volume: the persistent knob is `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5` — on login WirePlumber restores its saved node volume (observed as low as `0.06`) and writes it to the `DSP Volume` mixer, overriding the installer value.

## Kernel >= 6.16: Card Rename + PCM Renumbering (why the UCM broke)

- [`25293be`](https://github.com/torvalds/linux/commit/25293be4a778) "ASoC: Intel: avs: Update machine board card names" renamed the AVS cards (driver `avs_ssm4567`, long name `AVS I2S SSM4567`, `AVS I2S NAU8825`, `AVS DMIC`, `AVS HDMI`) and renumbered the front-end PCMs: the PCM device number now follows the topology-provided DAI-link `pcm_id` (`drv->use_dai_pcm_id = !obsolete_card_names` in `sound/soc/intel/avs/pcm.c`), leaving PCM device `0` as the only device on the SSM4567/NAU8825/DMIC cards on Chell; the HDMI card (`avs_hdaudio`) keeps devices `0`-`2` (HDMI1-HDMI3).
- Distro UCM written for the old names shipped `PlaybackPCM "hw:${CardId},1"` (SSM4567/NAU8825) and `CapturePCM "hw:${CardId},2"` (DMIC). Those PCMs no longer exist (`aplay -D hw:SSM4567,1` -> ENOENT), so PipeWire's ACP backend cannot build the HiFi profile: every AVS card offers only `{off, pro-audio}` with active profile `off`, no hardware sink is created and PipeWire falls back to the silent `Dummy Output` (auto_null) — apps exit 0.
- `alsaucm -c hw:SSM4567 dump text` can still exit 0 and print `Verb.HiFi`: alsa-lib only parses the UCM text, it never opens the referenced PCM, so parsing success is **not** proof the profile works. Check `aplay -l` / `aplay -D hw:SSM4567,0` instead.

## Fix Approaches

| Approach | How | Trade-offs |
| :--- | :--- | :--- |
| Repo UCM patch (default) | `sudo ./audio/install-audio.sh --install` — `conf.d` symlinks + `,1`/`,2` -> `,0` PCM indices + mixers + WirePlumber; verify with `./audio/diagnose-audio.sh` | Matches the upstream direction (new names, device `0`); no reboot needed. Updates to `alsa-ucm-conf` overwrite the patched HiFi files — re-run the installer after such updates |
| `obsolete_card_names=1` (update-proof alternative) | Restore the stock UCM, then `options snd-intel-dspcfg dsp_driver=4` + `options snd-soc-avs obsolete_card_names=1` in `/etc/modprobe.d/` and reboot | No UCM file patching, survives `alsa-ucm-conf` updates; a deprecated kernel option ("obsolete"), requires a reboot, and conflicts with the repo's UCM patches (revert them first) |

Full steps for the alternative route: [audio/docs/upstream.md](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/docs/upstream.md) §4. Upstream UCM fix: [alsa-ucm-conf PR #571 "Intel: avs: Add new UCMs after recent kernel work"](https://github.com/alsa-project/alsa-ucm-conf/pull/571) — still open (not merged) as of 2026-10.

Verified 2026-10-19 (kernel 7.0.0-38): sink `Built-in Speakers (SSM4567)`, source `Internal Digital Mic (DMIC)`; speakers user-confirmed audible, microphone captured speech.
