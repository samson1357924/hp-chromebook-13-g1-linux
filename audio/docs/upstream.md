<!-- markdownlint-disable MD013 -->

# Upstream Status & Contributor Actions (Chell AVS)

## 1. Platform

* **Driver**: Intel AVS (`CONFIG_SND_SOC_INTEL_AVS=m`) - in-kernel since 5.18, recommended 6.5+.
* **Firmware**: `linux-firmware` `/lib/firmware/intel/avs/` + `skl/dsp_basefw.bin.zst` (DSP) + `*-tplg.bin.zst` (topology); Chell runs `fw_version 9.21.0.4899` (verified 2026-10-19).
* **UCM**: `alsa-ucm-conf` ships AVS configurations under `Intel/avs/avs_{ssm4567,nau8825,dmic}/` + `hdaudioB0D2/`. This repo does **not** mirror SOF UCM; it patches the distro files in place (`conf.d` fallbacks + PCM indices).

## 2. Known-Good Environment Table

| Environment | alsa-ucm-conf | pipewire | wireplumber | AVS fw | Result |
|---|---|---|---|---|---|
| Ubuntu 26.04 LTS (this repo, verified 2026-08-27) | 1.2.15 (ships AVS, but conf.d fallbacks added by `install-audio.sh`) + 50-avs-chell.conf | 1.6.2 | 0.5.13 | skl/dsp_basefw.bin.zst | Speakers (SSM4567) + Headphones (NAU8825) + DMIC working |
| Ubuntu 26.04.1 (this repo, verified 2026-10-19, kernel 7.0.0-38-generic) | 1.2.15.3-1ubuntu1.7 patched by `install-audio.sh` (conf.d symlinks + `hw:${CardId},1\|,2` -> `,0`) | 1.6.2 | 0.5.13 | 9.21.0.4899 | Speakers (SSM4567) + DMIC verified (speakers audible, mic captured speech); headphones not re-tested; `obsolete_card_names` alternative untested here |
| Ubuntu 26.04 stock (no patch) | 1.2.15 (no conf.d fallbacks, no PCM index fix, no priority) | 1.6.2 | 0.5.13 | same | kernel >= 6.16: HiFi profile fails, only `Dummy Output`; older kernels: HDMI hijacks default, DSP 0 mute |

Add rows with tester + date as new versions are validated.

## 3. Kernel >= 6.16: AVS Card Rename + PCM Renumbering

* [`1581d5c`](https://github.com/torvalds/linux/commit/1581d5c68208) - "ASoC: Intel: avs: boards: Add Kconfig option for obsolete card names" (module parameter `snd-soc-avs.obsolete_card_names`).
* [`25293be`](https://github.com/torvalds/linux/commit/25293be4a778) - "ASoC: Intel: avs: Update machine board card names": new names (driver `avs_ssm4567`, long name `AVS I2S SSM4567`, `AVS I2S NAU8825`, `AVS DMIC`, `AVS HDMI`) and front-end PCM renumbering - the PCM device number now follows the topology-provided DAI-link `pcm_id` (enabled by `use_dai_pcm_id`; `drv->use_dai_pcm_id = !obsolete_card_names` in `sound/soc/intel/avs/pcm.c`), leaving a single device `0` on these cards.
* Legacy SKL removal in 6.12: driver [`a882f4d`](https://github.com/torvalds/linux/commit/a882f4d750ee); old `skl_nau88l25_ssm4567` board [`4dbf2f9`](https://github.com/torvalds/linux/commit/4dbf2f9a725d). AVS is the only supported path on Chell.
* Consequence for userspace: UCM written for the old DMI names and `,1`/`,2` PCM numbers no longer matches. Ubuntu 26.04 ships only the old-style UCM, so the ACP HiFi profile fails and PipeWire falls back to `Dummy Output`.
* Upstream UCM: [alsa-ucm-conf PR #571 "Intel: avs: Add new UCMs after recent kernel work"](https://github.com/alsa-project/alsa-ucm-conf/pull/571) adds the new-style UCMs - **still open (not merged) as of 2026-10**.

## 4. Alternative: `obsolete_card_names=1` (Community Workaround)

The chrultrabook community (e.g. `WeirdTreeThing/chromebook-linux-audio`, commit [`bef11f50`](https://github.com/WeirdTreeThing/chromebook-linux-audio/commit/bef11f50)) restores the old card names and PCM numbering instead of patching UCM:

```text
options snd-intel-dspcfg dsp_driver=4     # force AVS (4)
options snd-soc-avs obsolete_card_names=1 # old card names + PCM numbering
```

The repo's UCM patches must be reverted first - the restored old numbering expects the stock `,1`/`,2` indices:

1. Restore the stock UCM files: `sudo apt install --reinstall alsa-ucm-conf`, or copy the originals back from the installer's backups (`/var/backups/cros-enablement/<timestamp>/usr/share/alsa/ucm2/...`; the installer saves every file before patching it).
2. If `--uninstall` was used, it also removed the WirePlumber configs; restore them manually instead of re-running the installer: copy `audio/wireplumber/50-avs-chell.conf` and `power/wireplumber/50-disable-suspend.conf` to `/etc/wireplumber/wireplumber.conf.d/` (running the installer again would re-apply the PCM index patches and break this route).
3. Create `/etc/modprobe.d/99-avs-obsolete-names.conf` with the two `options` lines above.
4. Reboot (module parameters are read at load time).
5. Verify: `cat /proc/asound/cards` shows the old card name (`avs_ssm4567`, no `AVS I2S` prefix), `aplay -l` shows the stock numbering again (device `1` for SSM4567/NAU8825; DMIC capture at device `2`) and `wpctl status` exposes the speaker sink.
6. To switch back to the repo's patched-UCM route: delete the drop-in, reboot, then re-apply the repo patches following the install steps in [../README.md](../README.md).

Trade-offs:

| Approach | Advantages | Drawbacks |
|---|---|---|
| Patched UCM (this repo) | Matches the upstream direction (new names, device `0`); no reboot needed; keeps the new topology expectations | Modifies distro files in place; `alsa-ucm-conf` updates overwrite the patches (re-run the installer) |
| `obsolete_card_names=1` | No UCM file patching; survives `alsa-ucm-conf` updates | Deprecated kernel option ("obsolete"; upstream plans removal once the UCM PR lands); requires a reboot; conflicts with the repo's UCM patches (revert them first) |

## 5. Upstream History (for reference)

* Old C640 platform used SOF `sofrt5682` with the `WeirdTreeThing/alsa-ucm-conf-cros` mirror - **not applicable to Chell**.
* Chell AVS support is upstream in kernel and alsa-ucm-conf; this repo's role is **patching gaps** (`conf.d` symlinks + PCM index + WirePlumber priority), not forking UCM.
* Upstream UCM after the kernel rework is pending in PR #571 (open as of 2026-10); until it ships, distro UCM needs the PCM index patches or the `obsolete_card_names` fallback.

## 6. Contributor Checklist

* [ ] Verify `CONFIG_SND_SOC_INTEL_AVS` enabled in distro kernel (`grep AVS /boot/config-$(uname -r)`)
* [ ] Track `alsa-ucm-conf` AVS updates: when PR #571 (or an equivalent) ships, the PCM index patches become a no-op; also track removal of `obsolete_card_names`
* [ ] Re-run `install-audio.sh` after `alsa-ucm-conf` package updates (upgrades overwrite the patched HiFi files)
* [ ] Test after OS/kernel upgrades, update the Known-Good table
* [ ] Report AVS topology/UCM issues to `alsa-ucm-conf` or kernel `sound/soc/intel/avs`

## 7. Related

* Root cause: [root-cause.md](root-cause.md) - Diagnostics SOP: [diagnostics.md](diagnostics.md) - Install: [../README.md](../README.md)
