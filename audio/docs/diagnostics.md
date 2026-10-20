<!-- markdownlint-disable MD013 -->

# Audio Diagnostics SOP (Chell AVS)

## 1. Prerequisites

* `alsa-utils`, `pipewire`, `wireplumber`, `pipewire-tools`
* Run from a normal login session (not via `sudo -i` without `XDG_RUNTIME_DIR`)
* Since 2026-10, `./audio/diagnose-audio.sh` automates the key checks: stale UCM PCM index (`hw:${CardId},1`/`,2` vs `,0`, boundary-safe), missing speaker sink (`Dummy Output`), and low default-sink volume. It degrades gracefully (exit 0) when tools or a session are unavailable.

## 2. Toolchain

### 2.1 `wpctl status`

Sinks/sources, `*` default marker. Focus on the **Sinks section**: a working system shows `* Built-in Speakers (SSM4567)`; the kernel >= 6.16 UCM failure shows only `Dummy Output` (auto_null).

```bash
wpctl status | sed -n '/Sinks:/,/Sources:/p'
```

### 2.2 `pw-dump` + priority and profiles

```bash
pw-dump | python3 -c "
import json,sys
data=json.load(sys.stdin)
for n in data:
  if n.get('type')=='PipeWire:Interface:Node':
    props=n.get('info',{}).get('props',{})
    if 'media.class' in props:
        print(props.get('node.name'), props.get('priority.session'), props.get('node.description'))
"
# Expect: avs_ssm4567 1500 Built-in Speakers (SSM4567)
#         avs_dmic 1500 Internal Digital Mic
```

Card profiles - the failure signature is a missing `HiFi` profile. With a stale UCM PCM index the ACP profile build fails and every AVS card offers only `{off, pro-audio}` with active profile `off`:

```bash
pw-dump | python3 -c "
import json,sys
for d in json.load(sys.stdin):
    if d.get('type') == 'PipeWire:Interface:Device':
        p = d.get('info', {}).get('props', {})
        if p.get('device.api') == 'alsa':
            params = d.get('info', {}).get('params', {})
            offered = ','.join(x.get('name', '?') for x in params.get('EnumProfile', []))
            active = ','.join(x.get('name', '?') for x in params.get('Profile', [])) or '(none)'
            print(p.get('device.name'), '| offered:', offered, '| active:', active)
"
# Working:   ...avs_ssm4567... | offered: off,HiFi,pro-audio | active: HiFi
# Failure:   ...avs_ssm4567... | offered: off,pro-audio | active: off
# Note: idle cards may legitimately stay on "off" (HDMI without a display, NAU8825 without headphones);
#       the SSM4567 (speakers) and DMIC entries are the decisive ones.
```

### 2.3 `alsaucm dump` + PCM device existence

```bash
alsaucm -c hw:SSM4567 dump text | head -n 40  # Speakers
alsaucm -c hw:NAU8825 dump text | head -n 40  # Headphones
alsaucm -c hw:DMIC dump text | head -n 40     # DMIC
# Expect: Verb.HiFi with hw:${CardId},0 in PlaybackPCM / CapturePCM
```

**Caveat**: exit 0 and `Verb.HiFi` are necessary but **not sufficient**. alsa-lib only parses the UCM text; the referenced PCM may still not exist and the ACP profile build then fails. Always cross-check the device:

```bash
aplay -l | grep -A2 SSM4567        # kernel >= 6.16: only "device 0"
aplay -D hw:SSM4567,1 /usr/share/sounds/alsa/Front_Left.wav 2>&1 | tail -n2
# Failing state: "audio open error: No such file or directory" (ENOENT)
arecord -D hw:DMIC,2 -d1 /dev/null 2>&1 | tail -n2   # ENOENT on current kernels
# Stale PCM index in the UCM files (boundary-safe pattern used by diagnose-audio.sh):
grep -RE 'hw:\$\{CardId\},[12]([^0-9]|$)' /usr/share/alsa/ucm2/Intel/avs/avs_{ssm4567,nau8825,dmic}/*-HiFi.conf
# No output = OK; matches are the stale indices that break the ACP profile build.
```

### 2.4 `amixer` + WirePlumber volume

```bash
amixer -cSSM4567 cget name='DSP Volume'   # installer sets ~1500000000; range 0..2147483647 (small values like 80 are still mute)
wpctl get-volume @DEFAULT_AUDIO_SINK@     # WirePlumber node volume; below 0.2 is suspicious
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5 # persistent correction
amixer -cNAU8825 cget iface=CARD,name='Headphone Jack'   # jack detection
```

Note: on login WirePlumber restores its saved node volume and writes it to `DSP Volume`, overriding the installer's mixer value (observed 0.06 = 6%, mixer about -24 dB).

### 2.5 `aplay` / `speaker-test`

```bash
speaker-test -D plughw:SSM4567,0 -c2 -l1        # speakers (must be plughw + -c2)
speaker-test -D plughw:NAU8825,0 -c2 -l1        # headphones
arecord -D plughw:DMIC,0 -d2 -f S16_LE -r48000 -c2 /tmp/mic.wav && aplay -D plughw:SSM4567,0 /tmp/mic.wav
```

On kernel >= 6.16, `hw:SSM4567,1` / `hw:DMIC,2` do not exist — an ENOENT here happens on both fixed and unfixed systems (kernel >= 6.16 exposes only device 0), so it is **not** the discriminator; use `wpctl status` and `grep hw:\\${CardId},` in the UCM instead. Mono WAVs via `hw` also fail (`Channels count non available`); use `plughw` or `-c2`.

### 2.6 `dmesg` (AVS)

```bash
sudo dmesg | grep -i -E "avs|ssm4567|nau8825"
```

`Endpoint format configuration not found` (DMIC NHLT, repeated per DMIC open) is a warning only - capture works after the PCM index fix.

## 3. Checklist (failure signatures)

* [ ] `wpctl status` Sinks: only `Dummy Output` (no `Built-in Speakers (SSM4567)`)
* [ ] `pw-dump` AVS cards offer no `HiFi` profile (only `{off, pro-audio}`, active `off`)
* [ ] UCM HiFi files contain a stale `hw:${CardId},1` or `,2` index (automated by `diagnose-audio.sh`)
* [ ] `aplay -D hw:SSM4567,1 ...` fails ENOENT on both fixed and unfixed systems (not the discriminator); `wpctl status` shows only `Dummy Output`; `pw-dump` cards all `off`
* [ ] `alsaucm -c hw:SSM4567 dump text` reports `-2` (missing `conf.d` fallbacks - older failure mode; parsing can also succeed while the profile still fails)
* [ ] `amixer -cSSM4567 cget name='DSP Volume'` shows `values=0`, or `wpctl get-volume @DEFAULT_AUDIO_SINK@` is below 0.2
* [ ] `/etc/wireplumber/wireplumber.conf.d/50-avs-chell.conf` missing
* [ ] UCM `conf.d` fallback symlinks missing (`ls /usr/share/alsa/ucm2/conf.d/avs_ssm4567/`)

## 4. Test Matrix (UCM state × profile × sink)

| Scenario | wpctl Sinks | UCM verb | Playback |
|---|---|---|---|
| Stale PCM index (kernel >= 6.16; e.g. after an `alsa-ucm-conf` update overwrote the patches) | only `Dummy Output` | `alsaucm` parses OK | silent everywhere, exit 0 |
| Missing `conf.d` fallbacks (stock, older failure) | `* HDMI` (priority tie) | `alsaucm` fails `-2` | HDMI silent, speakers silent |
| Fixed, no headphone | `* Built-in Speakers (SSM4567)` (1500) | HiFi | speakers ok (set node volume if restored low) |
| Fixed, headphone in | `* Headphones (NAU8825)` (2000) | HiFi | headphones expected (auto-switch not fully re-verified) |

Note: `speaker-test -D hw:SSM4567,0` needs `-c2`; mono WAV via `hw` fails, use `plughw`.

## 5. Quick Fix

1. `sudo ./audio/install-audio.sh --install`
2. `sudo alsactl store` (done by the installer)
3. `systemctl --user restart wireplumber pipewire` (done by the installer)
4. `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5` if the restored node volume is too low
5. Re-run `./audio/diagnose-audio.sh` and check `wpctl status` Sinks:
6. After any `alsa-ucm-conf` package update, repeat step 1 (updates overwrite the patched HiFi files)

## 6. Reporting

```bash
./audio/diagnose-audio.sh -o /tmp/audio-report.txt
cat /tmp/audio-report.txt   # attach to issue
./scripts/sysreport.sh      # full bundle
```
