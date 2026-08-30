<!-- markdownlint-disable MD013 -->

# UCM for HP Chromebook 13 G1 (Chell)

Chell 使用 **Intel AVS**，由發行版 `alsa-ucm-conf` 原生提供 UCM：

- `Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0.conf` (Speaker)
- `Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0.conf` (Headphones)
- `Intel/avs/avs_dmic/DMIC-2ch.conf` (DMIC)
- `Intel/avs/hdaudioB0D2/hdaudioB0D2.conf` (HDMI)

**本倉庫不再鏡像 `sof-rt5682` UCM**（舊 CometLake 鏡像已移除）。`audio/install-audio.sh` 的職責是**修補**發行版 UCM 的兩個已知問題，而非重新分發 UCM：

1. **fallback symlink 缺失**：`alsa-lib` 僅搜尋 `conf.d/${Driver}/${CardLongName}.conf` 與 `conf.d/${Driver}/${Driver}.conf`；發行版僅提供 `Hewlett_Packard-Chell-1.0.conf`，缺少 `AVS I2S SSM4567.conf` / `avs_ssm4567.conf` 等，導致 `alsaucm -c hw:SSM4567 dump text` 報 `-2`。
2. **PCM device 索引歷史錯誤**：舊模板曾寫 `hw:${CardId},1`，實機為 `hw:${CardId},0`（多卡架構每卡 device 0）。若仍為 `,1` 需就地修正。

修補由 `install-audio.sh` 透過 `backup_file_manifest_aware` 安全備份後執行，所有異動可經 `install-audio.sh --uninstall` 回滾。

驗證：

```bash
alsaucm -c hw:SSM4567 dump text | grep -q "Verb.HiFi" && echo "UCM OK"
alsaucm -c hw:NAU8825 dump text | grep -q "Verb.HiFi" && echo "UCM OK"
```
