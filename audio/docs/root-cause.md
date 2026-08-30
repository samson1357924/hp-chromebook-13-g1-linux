<!-- markdownlint-disable MD013 -->

# Root Cause: No Speaker Output on Chell AVS (HP Chromebook 13 G1)

## 1. TL;DR

* **Symptom**: No sound from built-in speakers (SSM4567), and often default sink is HDMI (no sound).
* **Root causes** (3-fold, all verified on Chell `board_name=Chell`, kernel 7.0.0-30, AVS):
  1. **PipeWire default sink hijacked by HDMI** — `avs_hdaudio` (card 2) and `avs_ssm4567` (card 4) both at `priority 1000` (stereo-fallback). HDMI enumerated first wins, WirePlumber locks it with +30000.
  2. **UCM fallback missing** — `alsa-lib` only searches `conf.d/${Driver}/${CardLongName}.conf` and `conf.d/${Driver}/${Driver}.conf`; distro ships only `Hewlett_Packard-Chell-1.0.conf` → `alsaucm -c hw:SSM4567 dump text` fails `-2`, PipeWire falls back to `stereo-fallback`.
  3. **DSP Volume 0** — `amixer -cSSM4567 cget name='DSP Volume'` range `0..2147483647` is at `0` (mute) after fresh install.
* **Not firmware**: `dmesg | grep -i avs` clean, `/lib/firmware/intel/avs/skl/dsp_basefw.bin.zst` present, `lsmod` shows `snd_soc_avs*`.

## 2. Affected Environment

* Sound: `avs_ssm4567` (Speakers hw:SSM4567,0), `avs_nau8825` (Headphones hw:NAU8825,0 + Headset Mic), `avs_dmic` (DMIC hw:DMIC,0), `avs_hdaudio` (HDMI hw:2,0-2) — **Intel AVS**, not SOF.
* OS: Ubuntu 26.04 LTS, pipewire 1.6.2, wireplumber 0.5.13, kernel 7.0.
* UCM: `/usr/share/alsa/ucm2/Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0.conf` present but `conf.d` fallbacks missing pre-fix.

## 3. Symptoms

* `wpctl status` shows Sinks: `* HDMI` (card 2) rather than `* Speakers (SSM4567)` (card 4); audio goes to HDMI (no speaker sound).
* `pw-dump` shows `priority.session=1000` for both HDMI and Speakers (tie).
* `alsaucm -c hw:SSM4567 dump text` → `[error.ucm] failed to import hw:SSM4567 -2` pre-fix.
* `amixer -cSSM4567 cget name='DSP Volume'` → `values=0` pre-fix.
* `dmesg` clean — rules out firmware/topology missing.

## 4. Wrong Explanations (excluded)

| Old theory | Refutation |
|---|---|
| SOF firmware missing (`sof-cml.ri`/`firmware-sof-signed`) | Chell uses AVS, not SOF; `lsmod \| grep snd_soc_avs` shows AVS loaded, `snd_sof` only as hda-intel shim |
| Reinstall `alsa-ucm-conf` fixes it | Distro package correctly ships AVS UCM but lacks `conf.d` fallback symlinks — need `install-audio.sh` patch |
| Dummy Output (single card `sofrt5682`) | Chell is multi-card AVS; Dummy Output is for SOF single-card, not applicable |

## 5. The Real Chain

1. **UCM search fails**:

   ```bash
   strace -e trace=file alsaucm -c hw:SSM4567 dump text 2>&1 | grep -E "conf.d/avs_ssm4567"
   # access(.../conf.d/avs_ssm4567/AVS I2S SSM4567.conf) = -1 ENOENT
   # access(.../conf.d/avs_ssm4567/avs_ssm4567.conf) = -1 ENOENT
   ```

2. PipeWire falls back to `stereo-fallback` (no HiFi), both HDMI and Speakers at `1000`.
3. WirePlumber picks HDMI as default sink (enumeration order + `default.configured.audio.sink` bonus +30000).
4. Even after UCM fixed, `DSP Volume 0` still mutes speakers — needs `amixer -cSSM4567 cset name='DSP Volume' 1500000000` (range is 0..2147483647, `120` would still be mute).

## 6. Pitfalls

* **PCM index**: AVS multi-card uses `hw:${CardId},0` per card; old template `hw:${CardId},1` would `ENOENT` even if UCM loaded.
* **Alsaucm vs UCM**: `alsaucm -c hw:SSM4567 dump text` must show `Verb.HiFi`; `alsaucm -c hw:SSM4567 dump text | grep PlaybackPCM` should show `hw:${CardId},0`.
* **plughw vs hw**: `hw:SSM4567,0` only accepts 2ch; `aplay -D hw:SSM4567,0 Front_Center.wav` (mono) fails `Channels count non available` — use `plughw:SSM4567,0` or `speaker-test -c2`.
* **Per-user WirePlumber shadowing**: `~/.config/wireplumber/wireplumber.conf.d/50-avs-rules.conf` shadows `/etc`; install script removes legacy.

## 7. Fallback Routing Limits (no UCM / no priority fix)

| Card | PCM | Role |
|---|---|---|
| 0 | hw:DMIC,0 | DMIC capture 2ch |
| 2 | hw:2,0/1/2 | HDMI playback |
| 3 | hw:NAU8825,0 | Headphone playback + Headset capture (JackControl) |
| 4 | hw:SSM4567,0 | Speaker playback |

Without priority fix, HDMI always wins. Without UCM, no `JackControl` binding for headphone auto-switch.

## 8. Fix

```bash
sudo ./audio/install-audio.sh --install   # creates conf.d fallbacks, fixes PCM, unmutes DSP, deploys 50-avs-chell.conf + 50-disable-suspend.conf
./audio/diagnose-audio.sh                  # verifies 6 dimensions
speaker-test -D plughw:SSM4567,0 -c2 -l1         # should produce pink noise on both speakers
```

See [upstream.md](upstream.md) for AVS upstream tracking.
