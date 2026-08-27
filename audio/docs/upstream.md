<!-- markdownlint-disable MD013 -->

# Upstream Status & Contributor Actions (Chell AVS)

## 1. Platform

* **Driver**: Intel AVS (`CONFIG_SND_SOC_INTEL_AVS=m`) — in-kernel since 5.18, recommended 6.5+.
* **Firmware**: `linux-firmware` `/lib/firmware/intel/avs/` + `skl/dsp_basefw.bin.zst` (DSP) + `*-tplg.bin.zst` (topology).
* **UCM**: `alsa-ucm-conf` ships AVS configs in `Intel/avs/avs_{ssm4567,nau8825,dmic}/` + `hdaudioB0D2/`. This repo does **not** mirror SOF UCM; it patches `conf.d` fallbacks.

## 2. Known-Good Environment Table

| Environment | alsa-ucm-conf | pipewire | wireplumber | AVS fw | Result |
|---|---|---|---|---|---|
| Ubuntu 26.04 LTS (this repo, verified 2026-08-27) | 1.2.15 (ships AVS, but conf.d fallbacks added by `install-audio.sh`) + 50-avs-chell.conf | 1.6.2 | 0.5.13 | skl/dsp_basefw.bin.zst | Speakers (SSM4567) + Headphones (NAU8825) + DMIC working |
| Ubuntu 26.04 stock (no patch) | 1.2.15 (no conf.d fallbacks, no priority) | 1.6.2 | 0.5.13 | same | HDMI hijacks default, DSP 0 mute |

Add rows with tester + date as new versions are validated.

## 3. Upstream History (for reference)

* Old C640 platform used SOF `sofrt5682` with `WeirdTreeThing/alsa-ucm-conf-cros` mirror — **not applicable to Chell**.
* Chell AVS support is upstream in kernel and alsa-ucm-conf; this repo's role is **patching gaps** (conf.d symlinks + WirePlumber priority), not forking UCM.

## 4. Contributor Checklist

* [ ] Verify `CONFIG_SND_SOC_INTEL_AVS` enabled in distro kernel (`grep AVS /boot/config-$(uname -r)`)
* [ ] Track `alsa-ucm-conf` AVS updates — when `conf.d` fallbacks are added upstream, `install-audio.sh` patch becomes no-op
* [ ] Test after OS/kernel upgrades, update Known-Good table
* [ ] Report AVS topology issues to `alsa-ucm-conf` or kernel `sound/soc/intel/avs`

## 5. Related

* Root cause: [root-cause.md](root-cause.md) — Diagnostics SOP: [diagnostics.md](diagnostics.md) — Install: [../README.md](../README.md)
