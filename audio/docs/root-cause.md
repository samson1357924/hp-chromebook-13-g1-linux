<!-- markdownlint-disable MD013 -->

# Root Cause: No Speaker Output on Chell AVS (HP Chromebook 13 G1)

## 1. TL;DR

* **Symptom**: No sound at all. Applications "play" their streams and exit 0, but nothing is audible; `wpctl status` lists only `Dummy Output`.
* **Primary chain (verified 2026-10-19, kernel 7.0.0-38)**: the distro UCM references `hw:${CardId},1` (SSM4567/NAU8825 playback) and `hw:${CardId},2` (DMIC capture), but kernel >= 6.16 exposes every AVS card as PCM device `0`. PipeWire's ACP backend cannot build the HiFi profile, every card keeps profile `off`, no hardware sink/source exists and PipeWire falls back to the silent `Dummy Output` (auto_null).
* **`alsaucm` parsing is not proof**: `alsaucm -c hw:SSM4567 dump text` exits 0 and prints `Verb.HiFi` even while the profile cannot be built - alsa-lib parses the file without opening the referenced PCM.
* **Discriminating checks**: `wpctl status` shows only `Dummy Output`; `pw-dump` card profiles are all `off`; `aplay -D hw:SSM4567,1` fails ENOENT while `-D hw:SSM4567,0` streams fine.
* **Secondary / historical defects**: HDMI vs speakers priority tie (mitigated by `50-avs-chell.conf`, speakers 1500 > HDMI 500; matters when a display is attached) and missing `conf.d` fallback symlinks (created by the installer).
* **Volume**: after the sink appears, WirePlumber restores its saved node volume (observed 0.06 = 6%) and overrides the installer's `DSP Volume`; the persistent knob is `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5`.
* **Not firmware**: `/sys/.../avs/fw_version = 9.21.0.4899` with no load errors; Chell uses AVS, never SOF.
* **Fix**: `sudo ./audio/install-audio.sh --install` (conf.d symlinks + `,1`/`,2` -> `,0` PCM indices + mixers + WirePlumber). **Re-run it after every `alsa-ucm-conf` update** - package upgrades overwrite the patched HiFi files and reintroduce the failure.

## 2. Affected Environment

* Sound: `avs_ssm4567` (speakers, SSP0), `avs_nau8825` (headset, SSP1), `avs_dmic`, `avs_hdaudio`, `avs_probe` - **Intel AVS** (`snd_soc_avs`), not SOF.
* OS: Ubuntu 26.04.1 LTS, kernel 7.0.0-38-generic, PipeWire 1.6.2, WirePlumber 0.5.13, alsa-ucm-conf 1.2.15.3-1ubuntu1.7 (verified 2026-10-19).
* UCM: Ubuntu ships only the old DMI-named lookup (`conf.d/avs_ssm4567/Hewlett_Packard-Chell-1.0.conf`); the new-style UCM for kernel >= 6.16 is still an open upstream PR (see [upstream.md](upstream.md)).
* Cards and their numbers are non-deterministic - always use ALSA IDs (`hw:SSM4567`, `hw:NAU8825`, `hw:DMIC`, `hw:HDMI`) and device index `0`.
* Status after the fix: sink `Built-in Speakers (SSM4567)` and source `Internal Digital Mic (DMIC)`; speakers user-confirmed audible, microphone verified with `pw-record` capturing speech.

## 3. The Failure Chain Actually Observed (kernel >= 6.16)

1. **UCM references a PCM device that does not exist.** Legacy UCM files ship `PlaybackPCM "hw:${CardId},1"` (SSM4567, NAU8825) and `CapturePCM "hw:${CardId},2"` (DMIC), but kernel >= 6.16 renumbered all AVS front-end PCMs to device `0` - only `hw:${CardId},0` exists.
2. **Parsing still succeeds.** The `conf.d` fallback symlinks are present and `alsaucm -c hw:SSM4567 dump text` exits 0; alsa-lib expands the UCM text without opening the PCM, so this check cannot see the mismatch.
3. **ACP cannot build the HiFi profile.** PipeWire's ALSA Card Profile backend tries to open the UCM-referenced PCM, fails, and leaves the card with only the `{off, pro-audio}` profile set, active profile `off`.
4. **No hardware sink exists.** PipeWire creates its fallback sink `Dummy Output` (auto_null). Applications open the null sink, exit 0, and everything "plays" silently.

### Discriminating Checks

| Check | Failing state (observed) | Working state |
|---|---|---|
| `wpctl status` Sinks: | only `Dummy Output` | `* Built-in Speakers (SSM4567)` |
| `pw-dump` card profiles | only `off` / `pro-audio`, active `off` | `HiFi` offered (and active for SSM4567/DMIC) |
| `aplay -D hw:SSM4567,1 <wav>` | `audio open error: No such file or directory` (ENOENT) | - |
| `aplay -D hw:SSM4567,0 <wav>` | streams fine | streams fine |
| `arecord -D hw:DMIC,2 ...` | ENOENT | - |
| `arecord -D hw:DMIC,0 ...` | captures fine | captures fine |
| `alsaucm -c hw:SSM4567 dump text` | exit 0, `Verb.HiFi` printed - **not sufficient evidence** | exit 0 |

> **Historical note**: on older setups the same silent failure could be caused by missing `conf.d` fallback symlinks; in that case `alsaucm -c hw:SSM4567 dump text` fails with `-2` and detects the problem. The installer still creates those symlinks; both defects must be fixed for the HiFi profile to build.

## 4. Upstream Cause

* **Kernel >= 6.16 renamed the AVS cards and renumbered their PCM devices**:
  * [`1581d5c`](https://github.com/torvalds/linux/commit/1581d5c68208) - "ASoC: Intel: avs: boards: Add Kconfig option for obsolete card names" (module parameter `snd-soc-avs.obsolete_card_names`).
  * [`25293be`](https://github.com/torvalds/linux/commit/25293be4a778) - "ASoC: Intel: avs: Update machine board card names": new names (driver `avs_ssm4567`, long name `AVS I2S SSM4567`, ...) and front-end PCM renumbering - the PCM device number now follows the topology-provided DAI-link `pcm_id` (enabled by `use_dai_pcm_id`; `drv->use_dai_pcm_id = !obsolete_card_names` in `sound/soc/intel/avs/pcm.c`), leaving a single device `0` on these cards.
* The legacy SKL driver was removed in 6.12 ([`a882f4d`](https://github.com/torvalds/linux/commit/a882f4d750ee); the old `skl_nau88l25_ssm4567` board: [`4dbf2f9`](https://github.com/torvalds/linux/commit/4dbf2f9a725d)) - AVS is the only path on Chell.
* Ubuntu 26.04 still ships the old DMI-named UCM; the new-style UCM is upstream PR [alsa-ucm-conf #571](https://github.com/alsa-project/alsa-ucm-conf/pull/571) (open as of 2026-10).
* The community workaround `obsolete_card_names=1` (+ `dsp_driver=4`) and its trade-offs are documented in [upstream.md](upstream.md).

## 5. Wrong Explanations (excluded)

| Theory | Refutation |
|---|---|
| SOF firmware missing (`sof-cml.ri` / `firmware-sof-signed`) | Chell uses AVS, not SOF; `lsmod` shows `snd_soc_avs*` (SOF only as an HDA shim); `fw_version = 9.21.0.4899` loads with no errors |
| Reinstalling `alsa-ucm-conf` fixes it | The opposite: the package restores the stock `,1`/`,2` indices and overwrites the patched HiFi files - re-run the installer after any package update |
| "`Dummy Output` is a SOF single-card issue, not applicable to Chell" | The old `sofrt5682` single-card scenario still does not apply, but on Chell `Dummy Output` (auto_null) is the **symptom** of the failed AVS HiFi profile - see section 3 |
| DMIC NHLT warning `Endpoint format configuration not found` (x6 per DMIC open) | Warning only - capture works after the PCM index fix (verified with `pw-record` capturing speech) |
| HDMI/speakers priority tie | Secondary: handled by `50-avs-chell.conf` (speakers 1500 > HDMI 500); only matters when a display with audio is attached |

## 6. Volume (DSP Volume Re-framed)

* The installer sets the `DSP Volume` mixer, but on login **WirePlumber restores its saved node volume** and writes it to the control, overriding the installer (observed: node volume 0.06 = 6%, `DSP Volume` ended at 128843776, about -24 dB).
* The persistent, user-facing knob is the WirePlumber node volume:

```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5   # persistent correction
wpctl get-volume @DEFAULT_AUDIO_SINK@       # check; values below 0.2 are suspicious
```

`audio/diagnose-audio.sh` warns when the default sink volume is below 0.2.

## 7. Fix and Package-Update Caveat

```bash
sudo ./audio/install-audio.sh --install    # conf.d symlinks, ,1/,2 -> ,0 PCM indices, mixers, WirePlumber
./audio/diagnose-audio.sh                  # 6-dimension verification
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5  # if the restored node volume is too low
speaker-test -D plughw:SSM4567,0 -c2 -l1   # pink noise on both speakers
```

Verified after the fix (2026-10-19): `wpctl status` shows sink `* Built-in Speakers (SSM4567)` and source `* Internal Digital Mic (DMIC)`; speakers audible (user-confirmed); microphone captured speech via `pw-record`.

> **Package updates reintroduce the failure.** Upgrading `alsa-ucm-conf` overwrites `Intel/avs/**-HiFi.conf`, restoring the stale `,1`/`,2` PCM indices. Re-run `sudo ./audio/install-audio.sh --install` after such updates. This is very likely how this machine regressed before this session.

## 8. Pitfalls

* **PCM index**: every AVS card is PCM device `0` on kernel >= 6.16; the old `,1` (SSM4567/NAU8825) and `,2` (DMIC) templates open nothing - `ENOENT` even when `alsaucm` parses fine.
* **`alsaucm` is not enough**: `alsaucm -c hw:SSM4567 dump text` must show `Verb.HiFi` **and** the referenced PCM must exist; check `aplay -l` / `arecord -l` for device `0`.
* **plughw vs hw**: `hw:SSM4567,0` only accepts 2ch; `aplay -D hw:SSM4567,0 Front_Center.wav` (mono) fails `Channels count non available` - use `plughw:SSM4567,0` or `speaker-test -c2`.
* **Card numbers are dynamic**: use ALSA IDs, never fixed numbers.
* **Per-user WirePlumber shadowing**: `~/.config/wireplumber/wireplumber.conf.d/50-avs-rules.conf` shadows `/etc`; the install script removes legacy copies.
* **DMIC NHLT warning**: `Endpoint format configuration not found` (repeated per DMIC open) is harmless; capture works.

## 9. Fallback Routing Limits (no UCM / no priority fix)

Example enumeration (card numbers change between boots):

| Example card | PCM | Role |
|---|---|---|
| 0 | hw:NAU8825,0 | Headphone playback + headset capture (JackControl) |
| 2 | hw:HDMI,0/1/2 | HDMI playback |
| 3 | hw:DMIC,0 | DMIC capture 2ch |
| 4 | hw:SSM4567,0 | Speaker playback |

Without the UCM PCM fix there is no HiFi profile at all (silent `Dummy Output`); without the priority rules HDMI can take over the default sink when a display is attached; without UCM there is no `JackControl` binding for headphone auto-switch (auto-switch not fully evidenced).

See [upstream.md](upstream.md) for AVS upstream tracking and the `obsolete_card_names` alternative.
