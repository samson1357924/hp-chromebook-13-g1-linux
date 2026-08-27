<!-- markdownlint-disable MD013 MD060 -->

# 🔊 Audio - HP Chromebook 13 G1 (CHELL, AVS)

Chell 使用 **Intel AVS** (`snd_soc_avs`) 而非 SOF。獨立多卡架構：

| Card | ALSA ID | Codec/Function | Device | PCM | PipeWire 角色 |
|------|---------|---------------|--------|-----|--------------|
| 0 | `avs_dmic` | DMIC 數位麥克風陣列 | `hw:0,0` | capture 2ch | Source `Internal Mic` |
| 1 | `avs_probe` | Compress-Offload probe | — | compress | — |
| 2 | `avs_hdaudio` | Intel Skylake HDMI | `hw:2,0/1/2` | playback 3× HDMI | Sink `HDMI` |
| 3 | `avs_nau8825` | Nuvoton NAU8825 耳機/耳麥 | `hw:3,0` | playback+capture | Sink `Headphones` / Source `Headset Mic` |
| 4 | `avs_ssm4567` | ADI SSM4567 立體聲喇叭 | `hw:4,0` | playback 2ch | Sink `Speakers` |

> **PCM 索引**：AVS 多卡架構下每張卡皆為 `device 0`；UCM 中的 `PlaybackPCM "hw:${CardId},1"` 為錯誤模板，正確為 `hw:${CardId},0`。

## 架構圖

```text
                        ┌─ avs_dmic (DMIC-2ch) ──► Mic Source
                        ├─ avs_ssm4567 ─────────► Speaker Sink  (priority 1500)
PipeWire / WirePlumber ─┤
                        ├─ avs_nau8825 ─────────► Headphone Sink (priority 2000, JackControl)
                        │                      └─ Headset Mic Source
                        └─ avs_hdaudio ───────► HDMI Sinks (priority 500, 低於內建喇叭)
```

## 常見問題速查

| 症狀 | 原因 | 解法 |
|------|------|------|
| `wpctl status` 預設 Sink 為 HDMI，無聲 | HDMI 與喇叭同為 `priority 1000`，HDMI 先枚舉被鎖為 default | 部署 `50-avs-chell.conf` 提高喇叭優先級並 `wpctl set-default` |
| `alsaucm -c hw:4 dump text` 報 `-2` | `conf.d/avs_ssm4567/AVS I2S SSM4567.conf` 缺失 | 執行 `./audio/install-audio.sh` 建立 fallback symlinks |
| `amixer -c4` DSP Volume = 0 | 數位音量靜音 | `amixer -c4 cset 'DSP Volume' 80` 或重跑 install 腳本 |
| 耳機插入無自動切換 | NAU8825 JackControl 未達閾值或 priority 未提升 | 檢查 `amixer -c3` JackControl，確認 WirePlumber priority 2000 |

## 快速使用

```bash
# 診斷
./audio/diagnose-audio.sh
./audio/diagnose-audio.sh -o /tmp/audio-report.txt

# 修復 (UCM fallback + PCM 修正 + mixer 解靜音 + WirePlumber 優先級 + 防爆音)
sudo ./audio/install-audio.sh --install
sudo ./audio/install-audio.sh --check      # 僅檢查
sudo ./audio/install-audio.sh --uninstall  # 回滾

# 驗證
speaker-test -D plughw:4,0 -c2 -l1          # 喇叭 (立體聲, 必須 plughw 避免 mono 陷阱)
speaker-test -D plughw:3,0 -c2 -l1          # 耳機
arecord -D plughw:0,0 -d2 -f S16_LE -r48000 -c2 /tmp/mic.wav && aplay -D plughw:4,0 /tmp/mic.wav
wpctl status                                # 確認 HiFi profiles 已載入
alsaucm -c hw:4 dump text | head -n 40      # 確認 Verb.HiFi 正常
```

## 腳本與配置

| 檔案 | 作用 |
|------|------|
| `audio/install-audio.sh` | 主安裝腳本：UCM fallback、`hw:0` 修正、mixer、WirePlumber |
| `audio/diagnose-audio.sh` | 6 維度 AVS 診斷 (DMI/模組/韌體/ALSA/Mixer/PipeWire) |
| `audio/wireplumber/50-avs-chell.conf` | WirePlumber 優先級規則 (喇叭 1500 > HDMI 500, 耳機 2000) |
| `power/wireplumber/50-disable-suspend.conf` | 防閒置 suspend 爆音 (session.suspend-timeout-seconds=0) |
| `audio/ucm/README.md` | AVS 無需 sof-rt5682 鏡像，僅需修補發行版 UCM 說明 |

## 文件

- 深入根因：`audio/docs/root-cause.md`
- 診斷 SOP：`audio/docs/diagnostics.md`
- 上游追蹤：`audio/docs/upstream.md`

## Pitfalls

- **alsa-lib 搜尋路徑**：僅查 `conf.d/${Driver}/${CardLongName}.conf` 與 `conf.d/${Driver}/${Driver}.conf`，不會查 DMI 名；必須建立 `AVS I2S SSM4567.conf` 與 `avs_ssm4567.conf` 兩個 fallback。
- **stereo-fallback 陷阱**：UCM 載入失敗時 PipeWire 僅有 `stereo-fallback`，此時所有 Sink 同優先級 1000，易被 HDMI 搶佔。
- **plughw vs hw**：AVS SSM4567 的 `hw:4,0` 僅接受 2ch S24_LE，`aplay -D hw:4,0 Front_Center.wav` (mono) 會報 `Channels count non available`，請用 `plughw:4,0` 或 `speaker-test -c2`。
