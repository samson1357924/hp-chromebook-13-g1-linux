<!-- markdownlint-disable MD013 -->

# UCM for HP Chromebook 13 G1 (Chell)

Chell 使用 **Intel AVS**，由發行版 `alsa-ucm-conf` 原生提供 UCM：

- `Intel/avs/avs_ssm4567/Hewlett_Packard-Chell-1.0.conf`（喇叭）
- `Intel/avs/avs_nau8825/Hewlett_Packard-Chell-1.0.conf`（耳機）
- `Intel/avs/avs_dmic/DMIC-2ch.conf`（DMIC）
- `Intel/avs/hdaudioB0D2/hdaudioB0D2.conf`（HDMI）

**本倉庫不再鏡像 `sof-rt5682` UCM**（舊 CometLake 鏡像已移除）。`audio/install-audio.sh` 的職責是**就地修補**發行版 UCM 的已知缺陷，而非重新分發 UCM：

1. **fallback symlink 缺失**：`alsa-lib` 僅搜尋 `conf.d/${Driver}/${CardLongName}.conf` 與 `conf.d/${Driver}/${Driver}.conf`；發行版只提供舊 DMI 名稱 `Hewlett_Packard-Chell-1.0.conf`，缺少新卡名的 `AVS I2S SSM4567.conf` / `avs_ssm4567.conf` 等，缺失時 `alsaucm -c hw:SSM4567 dump text` 報 `-2`。
2. **PCM device 索引錯誤（kernel >= 6.16 迴歸）**：舊模板的播放索引為 `hw:${CardId},1`（SSM4567/NAU8825，NAU8825 的擷取同為 `,1`），DMIC 擷取為 `hw:${CardId},2`；但 kernel >= 6.16（commit `1581d5c`、`25293be`）把 AVS 各卡的 FE PCM 重新編號為 device `0`，實際只有 `hw:${CardId},0` 存在。索引不符時 PipeWire ACP 無法建立 HiFi profile，卡片只剩 `off`/`pro-audio`，最終只剩靜音的 `Dummy Output`（auto_null）。安裝腳本以邊界安全的 sed 同時把 `,1`、`,2` 改為 `,0`（不誤改 `,10`／`,12`／`,20`）。

注意事項：

- `alsaucm -c hw:SSM4567 dump text` 成功（exit 0、顯示 `Verb.HiFi`）**不代表** profile 可用：alsa-lib 只解析檔案、不會開啟 PCM，仍可能因裝置不存在而建構失敗。
- **`alsa-ucm-conf` 套件更新會覆寫** `Intel/avs/**-HiFi.conf` 的修補，索引回到 `,1`／`,2`，症狀重現；更新後請重跑 `sudo ./audio/install-audio.sh --install`。

修補由 `install-audio.sh` 透過 `backup_file_manifest_aware` 安全備份後執行，所有異動可經 `install-audio.sh --uninstall` 回滾。

驗證：

```bash
# 索引檢查（無輸出 = 正確；與 diagnose-audio.sh 相同的邊界安全規則）
grep -RE 'hw:\$\{CardId\},[12]([^0-9]|$)' /usr/share/alsa/ucm2/Intel/avs/avs_{ssm4567,nau8825,dmic}/*-HiFi.conf
# UCM 解析（必要條件）
alsaucm -c hw:SSM4567 dump text | grep -q "Verb.HiFi" && echo "UCM OK"
alsaucm -c hw:NAU8825 dump text | grep -q "Verb.HiFi" && echo "UCM OK"
# 實際可用性（充分條件）：sink 必須存在，且 device 0 可開啟
aplay -l | grep -A2 SSM4567
wpctl status | sed -n '/Sinks:/,/Sources:/p'
```
