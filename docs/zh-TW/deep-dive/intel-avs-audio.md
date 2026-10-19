<!-- markdownlint-disable MD013 -->

# Chell Intel AVS 音訊 (SSM4567/NAU8825)

本機採用 **Intel AVS** (`snd_soc_avs`)，非 SOF。完整說明請見 [Audio README](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/README.md)、[Root Cause](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/docs/root-cause.md) 與 [Upstream Status](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/docs/upstream.md)。

## 音訊卡與路由

- 音訊卡（請用 ALSA ID，卡號為動態）：`avs_ssm4567`（喇叭 `hw:SSM4567`）、`avs_nau8825`（耳機 `hw:NAU8825`）、`avs_dmic`（麥克風 `hw:DMIC`）、`avs_hdaudio`（HDMI `hw:HDMI`）——SSM4567／NAU8825／DMIC 只暴露 PCM device `0`；`avs_hdaudio` 仍保有 device `0`-`2`（HDMI1-HDMI3）。
- UCM：發行版 `alsa-ucm-conf` 由 `audio/install-audio.sh` 就地修補（`conf.d` fallback symlink + PCM 索引 `,1`／`,2` -> `,0` + mixer）；Chell 永遠不需要 SOF UCM。
- WirePlumber：`50-avs-chell.conf` 設定耳機 2000 > 喇叭 1500 > HDMI 500（修復 HDMI 優先權搶佔）。
- 音量：持久旋鈕是 `wpctl set-volume @DEFAULT_AUDIO_SINK@`——登入時 WirePlumber 會還原它儲存的節點音量（實測低至 `0.06`）並寫回 `DSP Volume`，覆蓋安裝器設定。

## kernel >= 6.16：音訊卡更名與 PCM 重新編號（UCM 為何失效）

- [`25293be`](https://github.com/torvalds/linux/commit/25293be4a778) "ASoC: Intel: avs: Update machine board card names" 更名 AVS 音訊卡（驅動 `avs_ssm4567`，長名稱 `AVS I2S SSM4567`、`AVS I2S NAU8825`、`AVS DMIC`、`AVS HDMI`），並重新編號 FE PCM：PCM device 編號改由拓撲提供的 DAI-link `pcm_id` 決定（`drv->use_dai_pcm_id = !obsolete_card_names`，見 `sound/soc/intel/avs/pcm.c`），Chell 上 SSM4567／NAU8825／DMIC 因此只剩 device `0`；HDMI 卡（`avs_hdaudio`）仍保有 device `0`-`2`（HDMI1-HDMI3）。
- 為舊卡名撰寫的發行版 UCM 帶有 `PlaybackPCM "hw:${CardId},1"`（SSM4567/NAU8825）與 `CapturePCM "hw:${CardId},2"`（DMIC），這些 PCM 已不存在（`aplay -D hw:SSM4567,1` -> ENOENT）；PipeWire 的 ACP 後端因此建不出 HiFi profile：每張 AVS 卡只剩 `{off, pro-audio}`、作用中 profile `off`，沒有硬體 sink，PipeWire 退回靜音的 `Dummy Output`（auto_null），應用程式 exit 0。
- `alsaucm -c hw:SSM4567 dump text` 仍可能 exit 0 並顯示 `Verb.HiFi`：alsa-lib 只解析 UCM 文字、從不開啟引用的 PCM，所以解析成功**不代表** profile 可用。請改看 `aplay -l` / `aplay -D hw:SSM4567,0`。

## 修復路線

| 路線 | 做法 | 取捨 |
| :--- | :--- | :--- |
| 本倉庫 UCM 修補（預設） | `sudo ./audio/install-audio.sh --install` — `conf.d` symlink + `,1`／`,2` -> `,0` PCM 索引 + mixer + WirePlumber；用 `./audio/diagnose-audio.sh` 驗證 | 與上游方向一致（新卡名、device `0`）、不需重開機；`alsa-ucm-conf` 更新會覆寫修補檔——更新後請重跑安裝器 |
| `obsolete_card_names=1`（免重補的替代） | 還原原廠 UCM，於 `/etc/modprobe.d/` 加入 `options snd-intel-dspcfg dsp_driver=4` + `options snd-soc-avs obsolete_card_names=1` 後重開機 | 完全不改 UCM 檔、可存活 `alsa-ucm-conf` 更新；但屬已標記 "obsolete" 的核心選項、需重開機，且與本倉庫的 UCM 修補互斥（須先還原） |

替代路線完整步驟：[audio/docs/upstream.md](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/audio/docs/upstream.md) §4。上游 UCM 修復：[alsa-ucm-conf PR #571 "Intel: avs: Add new UCMs after recent kernel work"](https://github.com/alsa-project/alsa-ucm-conf/pull/571)——截至 2026-10 仍未合併。

實測 2026-10-19（kernel 7.0.0-38）：sink `Built-in Speakers (SSM4567)`、source `Internal Digital Mic (DMIC)`；喇叭使用者確認可聽、麥克風錄到語音。
