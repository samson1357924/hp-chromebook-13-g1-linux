<!-- markdownlint-disable MD013 -->

# Intel AVS Audio on Chell (SSM4567/NAU8825)

This device uses **Intel AVS** (`snd_soc_avs`), not SOF.

See [Audio README](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/README.md) and [Root Cause](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/docs/root-cause.md) for full details.

- Cards: avs_ssm4567 (Speakers hw:SSM4567,0), avs_nau8825 (Headphones hw:NAU8825,0), avs_dmic (Mic hw:DMIC,0), avs_hdaudio (HDMI hw:2,0-2)
- UCM: fallbacks via `audio/install-audio.sh`
- Mixer: DSP Volume 0 trap, use `amixer -cSSM4567 cget name='DSP Volume'`
- WirePlumber: priorities 2000/1500/500 via `50-avs-chell.conf`
