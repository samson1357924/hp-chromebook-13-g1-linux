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

> **Card enumeration is non-deterministic** — the card numbers change between boots (e.g. one boot may show `0=HDMI 1=DMIC 2=SSM4567 4=NAU8825`). Always use `hw:SSM4567`/`hw:NAU8825`/`hw:DMIC`/`hw:HDMI`, or look up the current IDs with `cat /proc/asound/cards`, instead of hard-coded `hw:4,0`. Example: `alsaucm -c hw:SSM4567 dump text` / `amixer -c SSM4567 cget 'DSP Volume'`.

> **PCM Index**: On kernel >= 6.16, SSM4567/NAU8825/DMIC expose PCM device `0` only; the HDMI card (`avs_hdaudio`) keeps devices `0`-`2` (HDMI1-HDMI3). The legacy `PlaybackPCM "hw:${CardId},1"` (SSM4567/NAU8825) and `CapturePCM "hw:${CardId},2"` (DMIC) templates are wrong and make the PipeWire ACP HiFi profile fail - symptom: only `Dummy Output`, everything plays silently. The installer rewrites both indices to `hw:${CardId},0`.

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
| `wpctl status` shows only `Dummy Output`; apps "play" silently (exit 0) | UCM references `hw:${CardId},1`/`,2` but kernel >= 6.16 exposes those cards as PCM device `0` only; the ACP HiFi profile cannot build and cards stay on profile `off` | `sudo ./audio/install-audio.sh --install` (patches the PCM indices), then restart PipeWire/re-login. `alsaucm ... dump text` may still exit 0 - it is not proof the profile works |
| `alsaucm -c hw:SSM4567 dump text` reports `-2` | `conf.d/avs_ssm4567/AVS I2S SSM4567.conf` missing | Run `./audio/install-audio.sh` to create fallback symlinks |
| Sink appears but playback is near-silent | WirePlumber restored a low saved node volume (observed 0.06 = 6%) and overrode the DSP mixer | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5`; check with `wpctl get-volume @DEFAULT_AUDIO_SINK@` |
| `amixer -c SSM4567` DSP Volume = 0 | Digital volume muted | Re-run the install script; never use small values (range `0..2147483647`, `80` is still mute) |
| No microphone / `Internal Digital Mic (DMIC)` missing | Same PCM index bug for DMIC (`CapturePCM "hw:${CardId},2"`) | Re-run `sudo ./audio/install-audio.sh --install` (rewrites `,2` -> `,0`); verify with `pw-record` |
| Sound breaks again after `apt upgrade` | An `alsa-ucm-conf` update overwrote the patched `Intel/avs/**-HiFi.conf` files | Re-run `sudo ./audio/install-audio.sh --install` |
| Default sink is HDMI (e.g. display attached) | HDMI and speakers both at `priority 1000` without the WirePlumber rule | Deploy `50-avs-chell.conf` (speakers 1500 > HDMI 500) and `wpctl set-default` |
| Headphone insertion does not auto-switch | NAU8825 JackControl below threshold or priority not raised | Check `amixer -c NAU8825` JackControl, verify WirePlumber priority 2000 (auto-switch not fully evidenced) |

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
wpctl status                                      # Confirm speaker sink + HiFi profile
alsaucm -c hw:SSM4567 dump text | head -n 40      # Confirm Verb.HiFi OK (necessary, not sufficient)
```

> **After every `alsa-ucm-conf` update**, re-run `sudo ./audio/install-audio.sh --install`: package upgrades overwrite the patched `Intel/avs/**-HiFi.conf` files and the "Dummy Output" failure returns.

## Scripts & Configuration

| File | Purpose |
|------|------|
| `audio/install-audio.sh` | Main install script: UCM fallback, PCM index `,1`/`,2` -> `,0` fix, mixer, WirePlumber |
| `audio/diagnose-audio.sh` | 6-dimension AVS diagnostics (DMI/Module/Firmware/ALSA/Mixer/PipeWire) incl. PCM-index and Dummy-Output checks |
| `audio/wireplumber/50-avs-chell.conf` | WirePlumber priority rules (Speakers 1500 > HDMI 500, Headphones 2000) |
| `power/wireplumber/50-disable-suspend.conf` | Prevent idle suspend pops (session.suspend-timeout-seconds=0) |
| `audio/ucm/README.md` | AVS does not need sof-rt5682 mirror, only distro UCM patch notes |

## Documentation

- Deep dive root cause: `audio/docs/root-cause.md`
- Diagnostics SOP: `audio/docs/diagnostics.md`
- Upstream tracking: `audio/docs/upstream.md`

## Pitfalls

- **alsa-lib search path**: only searches `conf.d/${Driver}/${CardLongName}.conf` and `conf.d/${Driver}/${Driver}.conf`; the distro only ships the old DMI file name, so the installer creates `AVS I2S SSM4567.conf` (new long name) and `avs_ssm4567.conf` (driver) fallbacks.
- **PCM index trap**: kernel >= 6.16 exposes SSM4567/NAU8825/DMIC as `hw:${CardId},0` only (the HDMI card keeps `0`-`2`); legacy `,1`/`,2` templates make the ACP HiFi profile fail. `alsaucm` parsing OK (exit 0, `Verb.HiFi`) does NOT prove the profile works.
- **`alsa-ucm-conf` update trap**: package upgrades overwrite the patched `Intel/avs/**-HiFi.conf` and the "Dummy Output" failure returns; re-run `sudo ./audio/install-audio.sh --install`.
- **stereo-fallback / Dummy Output trap**: when the HiFi profile fails to build, PipeWire falls back to the silent `Dummy Output` (auto_null); the older stereo-fallback mode instead exposed all sinks at priority 1000 so HDMI could preempt.
- **plughw vs hw**: AVS SSM4567 `hw:SSM4567,0` only accepts 2ch S24_LE, `aplay -D hw:SSM4567,0 Front_Center.wav` (mono) will report `Channels count non available`, use `plughw:SSM4567,0` or `speaker-test -c2`.
