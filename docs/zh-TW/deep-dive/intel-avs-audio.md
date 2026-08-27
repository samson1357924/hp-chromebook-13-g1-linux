<!-- markdownlint-disable MD013 -->

# Chell Intel AVS 音訊 (SSM4567/NAU8825)

本機採用 **Intel AVS** (`snd_soc_avs`)，非 SOF。

詳見 [Audio README](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/README.md) 與 [Root Cause](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/docs/root-cause.md)。

- 音訊卡：avs_ssm4567 (喇叭 hw:4,0)、avs_nau8825 (耳機 hw:3,0)、avs_dmic (麥克風 hw:0,0)、avs_hdaudio (HDMI hw:2,0-2)
- UCM：透過 `audio/install-audio.sh` 建立 fallbacks
- Mixer：DSP Volume 0 陷阱，請用 `amixer -c4 cget name='DSP Volume'` 檢查
- WirePlumber：優先權 2000/1500/500 經 `50-avs-chell.conf` 設定
