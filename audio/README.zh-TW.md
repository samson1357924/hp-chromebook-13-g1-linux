<!-- markdownlint-disable-file -->


# 🔊 Audio - HP Chromebook 13 G1 (CHELL, AVS)

Chell 使用 **Intel AVS** (`snd_soc_avs`) 而非 SOF。獨立多卡架構（卡號為動態，請用 ALSA ID 而非固定數字）：

| 範例 Card | ALSA ID | Codec/Function | Device (範例) | PCM | PipeWire 角色 |
|------|---------|---------------|--------|-----|--------------|
| 0 | `avs_dmic` | DMIC 數位麥克風陣列 | `hw:DMIC,0`（範例 `hw:0,0`） | capture 2ch | Source `Internal Mic` |
| 1 | `avs_probe` | Compress-Offload probe | — | compress | — |
| 2 | `avs_hdaudio` | Intel Skylake HDMI | `hw:HDMI,0/1/2`（範例 `hw:2,0/1/2`） | playback 3× HDMI | Sink `HDMI` |
| 3 | `avs_nau8825` | Nuvoton NAU8825 耳機/耳麥 | `hw:NAU8825,0`（範例 `hw:3,0`） | playback+capture | Sink `Headphones` / Source `Headset Mic` |
| 4 | `avs_ssm4567` | ADI SSM4567 立體聲喇叭 | `hw:SSM4567,0`（範例 `hw:4,0`） | playback 2ch | Sink `Speakers` |

> **卡號為動態** — 每次開機的卡號可能不同（例如 `0=HDMI 1=DMIC 2=SSM4567 4=NAU8825`）。請用 `hw:SSM4567`/`hw:NAU8825`/`hw:DMIC`/`hw:HDMI`，或用 `cat /proc/asound/cards` 查詢目前的卡號，勿寫死 `hw:4,0`。範例：`alsaucm -c hw:SSM4567 dump text` / `amixer -c SSM4567 cget 'DSP Volume'`。

> **PCM 索引**：kernel >= 6.16 起，SSM4567/NAU8825/DMIC 僅暴露 PCM device `0`；HDMI 卡（`avs_hdaudio`）仍保有 device `0`-`2`（HDMI1-HDMI3）。UCM 舊模板的 `PlaybackPCM "hw:${CardId},1"`（SSM4567/NAU8825）與 `CapturePCM "hw:${CardId},2"`（DMIC）都是錯誤值，會讓 PipeWire 的 ACP 後端無法建立 HiFi profile——症狀是只剩 `Dummy Output`、程式「播放成功」卻完全無聲。安裝腳本會把兩種索引都改寫為 `hw:${CardId},0`。

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
| `wpctl status` 只看得到 `Dummy Output`；程式「播放成功」卻無聲（exit 0） | UCM 仍指向 `hw:${CardId},1`/`,2`，但 kernel >= 6.16 起這些卡片只剩 PCM device `0`；ACP 無法建立 HiFi profile，卡片維持 profile `off` | `sudo ./audio/install-audio.sh --install` 修正 PCM 索引，之後重啟 PipeWire／重新登入。`alsaucm ... dump text` 仍可能 exit 0，不代表 profile 可用 |
| `alsaucm -c hw:SSM4567 dump text` 報 `-2` | `conf.d/avs_ssm4567/AVS I2S SSM4567.conf` 缺失 | 執行 `./audio/install-audio.sh` 建立 fallback symlinks |
| Sink 存在但聲音極小 | WirePlumber 還原了過低的節點音量（實測 0.06 = 6%）並覆蓋 DSP 混音器值 | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5`；用 `wpctl get-volume @DEFAULT_AUDIO_SINK@` 確認 |
| `amixer -c SSM4567` DSP Volume = 0 | 數位音量靜音 | 重跑 install 腳本；勿用小數值（範圍 `0..2147483647`，`80` 仍是靜音） |
| 麥克風消失／沒有 `Internal Digital Mic (DMIC)` | DMIC 也有相同的 PCM 索引問題（`CapturePCM "hw:${CardId},2"`） | 重跑 `sudo ./audio/install-audio.sh --install`（將 `,2` 改為 `,0`），再用 `pw-record` 驗證 |
| `apt upgrade` 後又沒聲音 | `alsa-ucm-conf` 更新覆寫了已修補的 `Intel/avs/**-HiFi.conf` | 重跑 `sudo ./audio/install-audio.sh --install` |
| 預設 Sink 變成 HDMI（例如外接螢幕時） | 沒有 WirePlumber 規則時，HDMI 與喇叭同為 `priority 1000` | 部署 `50-avs-chell.conf`（喇叭 1500 > HDMI 500）並 `wpctl set-default` |
| 耳機插入無自動切換 | NAU8825 JackControl 未達閾值或 priority 未提升 | 檢查 `amixer -c NAU8825` JackControl，確認 WirePlumber priority 2000（自動切換尚未充分驗證） |

## 快速使用

```bash
# 診斷
./audio/diagnose-audio.sh
./audio/diagnose-audio.sh -o /tmp/audio-report.txt

# 修復 (UCM fallback + PCM 修正 + mixer 解靜音 + WirePlumber 優先級 + 防爆音)
sudo ./audio/install-audio.sh --install
sudo ./audio/install-audio.sh --check      # 僅檢查
sudo ./audio/install-audio.sh --uninstall  # 回滾

# 驗證（請用 ALSA ID，卡號為動態）
speaker-test -D plughw:SSM4567,0 -c2 -l1          # 喇叭 (立體聲, 必須 plughw 避免 mono 陷阱)
speaker-test -D plughw:NAU8825,0 -c2 -l1          # 耳機
arecord -D plughw:DMIC,0 -d2 -f S16_LE -r48000 -c2 /tmp/mic.wav && pw-play /tmp/mic.wav
wpctl status                                      # 確認喇叭 sink 與 HiFi profile
alsaucm -c hw:SSM4567 dump text | head -n 40      # 確認 Verb.HiFi 正常（必要條件，非充分條件）
```

> **每次 `alsa-ucm-conf` 更新後**請重跑 `sudo ./audio/install-audio.sh --install`：套件升級會覆寫已修補的 `Intel/avs/**-HiFi.conf`，「Dummy Output」症狀將再次出現。

## 腳本與配置

| 檔案 | 作用 |
|------|------|
| `audio/install-audio.sh` | 主安裝腳本：UCM fallback、PCM 索引 `,1`/`,2` 修正為 `,0`、mixer、WirePlumber |
| `audio/diagnose-audio.sh` | 6 維度 AVS 診斷 (DMI/模組/韌體/ALSA/Mixer/PipeWire)，含 PCM 索引與 Dummy Output 檢查 |
| `audio/wireplumber/50-avs-chell.conf` | WirePlumber 優先級規則 (喇叭 1500 > HDMI 500, 耳機 2000) |
| `power/wireplumber/50-disable-suspend.conf` | 防閒置 suspend 爆音 (session.suspend-timeout-seconds=0) |
| `audio/ucm/README.md` | AVS 無需 sof-rt5682 鏡像，僅需修補發行版 UCM 說明 |

## 文件

- 深入根因：`audio/docs/root-cause.md`
- 診斷 SOP：`audio/docs/diagnostics.md`
- 上游追蹤：`audio/docs/upstream.md`

## Pitfalls

- **alsa-lib 搜尋路徑**：僅查 `conf.d/${Driver}/${CardLongName}.conf` 與 `conf.d/${Driver}/${Driver}.conf`；發行版只提供舊 DMI 檔名，故安裝腳本會建立 `AVS I2S SSM4567.conf`（新長名稱）與 `avs_ssm4567.conf`（driver 名）兩個 fallback。
- **PCM 索引陷阱**：kernel >= 6.16 起 SSM4567/NAU8825/DMIC 僅有 `hw:${CardId},0`（HDMI 卡仍保有 `0`-`2`），舊模板的 `,1`/`,2` 會讓 ACP HiFi profile 失敗；`alsaucm` 解析成功（exit 0、顯示 `Verb.HiFi`）**不代表** profile 可用。
- **`alsa-ucm-conf` 更新陷阱**：套件升級會覆寫已修補的 `Intel/avs/**-HiFi.conf`，`Dummy Output` 症狀重現；請重跑 `sudo ./audio/install-audio.sh --install`。
- **stereo-fallback / Dummy Output 陷阱**：HiFi profile 建構失敗時，PipeWire 只提供靜音的 `Dummy Output`（auto_null）；舊的 stereo-fallback 模式則會讓所有 Sink 同為優先級 1000，易被 HDMI 搶佔。
- **plughw vs hw**：AVS SSM4567 的 `hw:SSM4567,0` 僅接受 2ch S24_LE，`aplay -D hw:SSM4567,0 Front_Center.wav` (mono) 會報 `Channels count non available`，請用 `plughw:SSM4567,0` 或 `speaker-test -c2`。
