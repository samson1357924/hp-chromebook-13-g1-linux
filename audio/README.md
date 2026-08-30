<!-- markdownlint-disable-file -->


# 🔊 Audio - HP Chromebook 13 G1 (CHELL, AVS)

Chell uses **Intel AVS** (`snd_soc_avs`) instead of SOF. Independent multi-card architecture (card numbers are dynamic — use ALSA IDs, not fixed numbers):

| Example Card | ALSA ID | Codec/Function | Device (example) | PCM | PipeWire Role |
|------|---------|---------------|--------|-----|--------------|
| 0 | `avs_dmic` | DMIC digital mic array | `hw:DMIC,0` (`hw:0,0` example) | capture 2ch | Source `Internal Mic` |
| 1 | `avs_probe` | Compress-Offload probe | — | compress | — |
| 2 | `avs_hdaudio` | Intel Skylake HDMI | `hw:HDMI,0/1/2` (`hw:2,0/1/2` example) | playback 3× HDMI | Sink `HDMI` |
| 3 | `avs_nau8825` | Nuvoton NAU8825 Headphone/Headset Mic | `hw:NAU8825,0` (`hw:3,0` example) | playback+capture | Sink `Headphones` / Source `Headset Mic` |
| 4 | `avs_ssm4567` | ADI SSM4567 Stereo Speakers | `hw:SSM4567,0` (`hw:4,0` example) | playback 2ch | Sink `Speakers` |

> **Card enumeration is non-deterministic** — `cat /proc/asound/cards` may show `0=HDMI 1=DMIC 2=SSM4567 4=NAU8825` etc. Always use `hw:SSM4567`/`hw:NAU8825`/`hw:DMIC`/`hw:HDMI` or `$(grep -l ID /proc/asound/cards)` instead of hard-coded `hw:4,0`. Example: `alsaucm -c hw:SSM4567 dump text` / `amixer -c SSM4567 cget 'DSP Volume'`.

> **PCM Index**: Under AVS multi-card architecture each card is `device 0`; `PlaybackPCM "hw:${CardId},1"` in UCM is an incorrect template, the correct value is `hw:${CardId},0`.

## Architecture Diagram

```text
                        ┌─ avs_dmic (DMIC-2ch) ──► Mic Source
                        ├─ avs_ssm4567 ─────────► Speaker Sink  (priority 1500)
PipeWire / WirePlumber ─┤
                        ├─ avs_nau8825 ─────────► Headphone Sink (priority 2000, JackControl)
                        │                      └─ Headset Mic Source
                        └─ avs_hdaudio ───────► HDMI Sinks (priority 500, lower than internal speakers)
```

## Quick Troubleshooting

| Symptom | Cause | Solution |
|------|------|------|
| `wpctl status` default Sink is HDMI, no sound | HDMI and speakers both have `priority 1000`, HDMI enumerated first and locked as default | Deploy `50-avs-chell.conf` to raise speaker priority and `wpctl set-default` |
| `alsaucm -c hw:SSM4567 dump text` reports `-2` | `conf.d/avs_ssm4567/AVS I2S SSM4567.conf` missing | Run `./audio/install-audio.sh` to create fallback symlinks |
| `amixer -c SSM4567` DSP Volume = 0 | Digital volume muted | `amixer -c SSM4567 cset 'DSP Volume' 80` or re-run install script |
| Headphone insertion does not auto-switch | NAU8825 JackControl below threshold or priority not raised | Check `amixer -c NAU8825` JackControl, verify WirePlumber priority 2000 |

## Quick Start

```bash
# Diagnosis
./audio/diagnose-audio.sh
./audio/diagnose-audio.sh -o /tmp/audio-report.txt

# Fix (UCM fallback + PCM fix + mixer unmute + WirePlumber priority + anti-pop)
sudo ./audio/install-audio.sh --install
sudo ./audio/install-audio.sh --check      # check only
sudo ./audio/install-audio.sh --uninstall  # rollback

# Verification (use ALSA IDs — card numbers are dynamic)
speaker-test -D plughw:SSM4567,0 -c2 -l1          # Speakers (stereo, must use plughw to avoid mono trap)
speaker-test -D plughw:NAU8825,0 -c2 -l1          # Headphones
arecord -D plughw:DMIC,0 -d2 -f S16_LE -r48000 -c2 /tmp/mic.wav && pw-play /tmp/mic.wav
wpctl status                                      # Confirm HiFi profiles loaded
alsaucm -c hw:SSM4567 dump text | head -n 40      # Confirm Verb.HiFi OK
```

## Scripts & Configuration

| File | Purpose |
|------|------|
| `audio/install-audio.sh` | Main install script: UCM fallback, `hw:0` fix, mixer, WirePlumber |
| `audio/diagnose-audio.sh` | 6-dimension AVS diagnostics (DMI/Module/Firmware/ALSA/Mixer/PipeWire) |
| `audio/wireplumber/50-avs-chell.conf` | WirePlumber priority rules (Speakers 1500 > HDMI 500, Headphones 2000) |
| `power/wireplumber/50-disable-suspend.conf` | Prevent idle suspend pops (session.suspend-timeout-seconds=0) |
| `audio/ucm/README.md` | AVS does not need sof-rt5682 mirror, only distro UCM patch notes |

## Documentation

- Deep dive root cause: `audio/docs/root-cause.md`
- Diagnostics SOP: `audio/docs/diagnostics.md`
- Upstream tracking: `audio/docs/upstream.md`

## Pitfalls

- **alsa-lib search path**: only searches `conf.d/${Driver}/${CardLongName}.conf` and `conf.d/${Driver}/${Driver}.conf`, does not search DMI name; must create both `AVS I2S SSM4567.conf` and `avs_ssm4567.conf` fallbacks.
- **stereo-fallback trap**: When UCM fails to load, PipeWire only has `stereo-fallback`, all Sinks then share priority 1000 and HDMI can preempt.
- **plughw vs hw**: AVS SSM4567 `hw:SSM4567,0` only accepts 2ch S24_LE, `aplay -D hw:SSM4567,0 Front_Center.wav` (mono) will report `Channels count non available`, use `plughw:SSM4567,0` or `speaker-test -c2`.
