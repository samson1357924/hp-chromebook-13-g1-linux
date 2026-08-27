# Audio Diagnostics SOP (Chell AVS)

## 1. Prerequisites

* `alsa-utils`, `pipewire`, `wireplumber`, `pipewire-tools`
* Run from normal login session (not via `sudo -i` without XDG_RUNTIME_DIR)

## 2. Toolchain

### 2.1 `wpctl status`

Sinks/sources, `*` default marker. Focus on **Sinks section**:

```bash
wpctl status | sed -n '/Sinks:/,/Sources:/p'
```

### 2.2 `pw-dump` + priority

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

### 2.3 `alsaucm dump`

```bash
alsaucm -c hw:4 dump text | head -n 40  # Speakers
alsaucm -c hw:3 dump text | head -n 40  # Headphones
alsaucm -c hw:0 dump text | head -n 40  # DMIC
# Expect: Verb.HiFi with PlaybackPCM hw:${CardId},0
```

### 2.4 `amixer` (use name= syntax)

```bash
amixer -c4 cget name='DSP Volume'        # should be non-zero (0..2147483647)
amixer -c4 cset name='DSP Volume' 1500000000
amixer -c3 cget name='Headphone Jack'    # jack detection
```

### 2.5 `aplay` / `speaker-test`

```bash
speaker-test -D plughw:4,0 -c2 -l1        # speakers (must be plughw + -c2)
speaker-test -D plughw:3,0 -c2 -l1        # headphones
arecord -D plughw:0,0 -d2 -f S16_LE -r48000 -c2 /tmp/mic.wav && aplay -D plughw:4,0 /tmp/mic.wav
```

### 2.6 `dmesg` (AVS)

```bash
sudo dmesg | grep -i -E "avs|ssm4567|nau8825"
```

## 3. Checklist (5+ = high-confidence AVS issue)

* [ ] `wpctl status Sinks:` shows `* HDMI` not `* Speakers (SSM4567)`
* [ ] `pw-dump` priority.session `1000` for both HDMI and Speakers (should be 1500/500)
* [ ] `alsaucm -c hw:4 dump text` reports `-2` ENOENT
* [ ] `ls -l /usr/share/alsa/ucm2/conf.d/avs_ssm4567/AVS I2S SSM4567.conf` missing
* [ ] `amixer -c4 cget name='DSP Volume'` shows `values=0`
* [ ] `/etc/wireplumber/wireplumber.conf.d/50-avs-chell.conf` missing

## 4. Test Matrix (priority × UCM × jack)

| Scenario | wpctl Sinks | UCM verb | Playback |
|---|---|---|---|
| No fix, no headphone | `* HDMI` (priority tie) | fallback | HDMI silent, speakers silent (muted + wrong sink) |
| No fix, headphone in | `* HDMI` still | fallback | headphone may work via hw:3,0 direct but not via PipeWire |
| Fixed, no headphone | `* Built-in Speakers (SSM4567)` priority 1500 | HiFi | speakers ok |
| Fixed, headphone in | `* Headphones (NAU8825)` priority 2000 auto-switch | HiFi | headphones ok, speakers auto-muted via priority |

Note: `speaker-test -D hw:4,0` needs `-c2`; mono wav via `hw` fails, use `plughw`.

## 5. Quick Fix

1. `sudo ./audio/install-audio.sh --install`
2. `sudo alsactl store` (done by installer)
3. `systemctl --user restart wireplumber pipewire` (done by installer)
4. Re-run `./audio/diagnose-audio.sh` and `wpctl status Sinks:`

## 6. Reporting

```bash
./audio/diagnose-audio.sh -o /tmp/audio-report.txt
cat /tmp/audio-report.txt   # attach to issue
./scripts/sysreport.sh      # full bundle
```
