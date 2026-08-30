<!-- markdownlint-disable MD013 -->

# Contributing to HP Chromebook 13 G1 Linux Guide

Thank you for your interest in improving hardware support for the HP Chromebook 13 G1 and related ChromeOS devices!

---

## 🛠️ Development & Testing

### 1. Fingerprint Driver (`crfpmoc`) — *Not applicable to Chell*

> **Chell (HP Chromebook 13 G1) has no fingerprint hardware.** This section is retained for legacy `c640` compatibility only.

* **Unit Tests**: Compile and run the standalone unit tests:

  ```bash
  cd fingerprint/tests
  gcc -Wall -Wextra -O2 test-crfpmoc-unit.c $(pkg-config --cflags --libs glib-2.0) -o test-crfpmoc-unit
  ./test-crfpmoc-unit
  ```

* **Protocol Modifications**: When editing ChromeOS EC Host Command structures
  in `fingerprint/driver/crfpmoc.h` or `crfpmoc.c`, ensure all fields sent to
  or received from the MCU are wrapped in `GUINT32_TO_LE()` / `GUINT32_FROM_LE()`.

### 2. Top-Row Keyboard Mapping (`HWDB`)

* **Testing Mappings**:

  ```bash
  sudo systemd-hwdb update
  sudo udevadm trigger --subsystem-match=input
  sudo evtest
  ```

* Ensure all HWDB properties start with a **single leading space** and match proper DMI strings (`cat /sys/class/dmi/id/product_name`).

### 3. Audio (ALSA / AVS for Chell)

Chell uses **Intel AVS** (`avs_ssm4567` Speakers, `avs_nau8825` Headphones, `avs_dmic` Mic, `avs_hdaudio` HDMI) — **not** SOF `sofrt5682`. See [audio/README.md](audio/README.md) and [audio/ucm/README.md](audio/ucm/README.md).

#### 3.1 UCM source

* Upstream AVS UCM is in `alsa-ucm-conf` (`Intel/avs/`). This repo **does not mirror** UCM; `audio/install-audio.sh` **patches** distro UCM: creates `conf.d/avs_*/AVS I2S *.conf` fallbacks and fixes `hw:${CardId},0` index.
* Rule: **upstream first, patch second**; when upstream adds fallbacks, the patch becomes no-op.

#### 3.2 Verification flow

```bash
sudo ./audio/install-audio.sh --install   # patches UCM, deploys 50-avs-chell.conf, unmutes DSP
./audio/diagnose-audio.sh                  # 6-dimension check
alsaucm -c hw:SSM4567 dump text | grep Verb.HiFi # should show HiFi
speaker-test -D plughw:SSM4567,0 -c2 -l1          # speakers (must be plughw + -c2)
```

* Pitfall: `hw:SSM4567,0` only accepts 2ch; mono `aplay -D hw:SSM4567,0` fails — use `plughw:SSM4567,0`.
* WirePlumber priority: `50-avs-chell.conf` (2000 Headphones > 1500 Speakers > 500 HDMI).

#### 3.3 Diagnostics

See [audio/docs/diagnostics.md](audio/docs/diagnostics.md) for `wpctl`/`pw-dump`/`alsaucm`/`amixer name='DSP Volume'` SOP.

#### 3.4 Upstream

* Track `alsa-ucm-conf` AVS updates and kernel `CONFIG_SND_SOC_INTEL_AVS`. See [audio/docs/upstream.md](audio/docs/upstream.md).

### 4. Documentation & GitHub Pages

* **Local preview**:

  ```bash
  pip install -r requirements-docs.txt
  mkdocs serve        # http://127.0.0.1:8000/hp-chromebook-13-g1-linux/
  mkdocs build --strict --site-dir site  # strict: broken links/nav fail
  ```

* **Add a page**: create `docs/<name>.md` (and `docs/zh-TW/<name>.md` for Traditional Chinese), add it to `mkdocs.yml` `nav` under both `en` and `zh-TW`. Assets go to `docs/assets/` (CC0) and styles to `docs/stylesheets/` (CC0).

* **First-time enablement (maintainers only)**: GitHub → Settings → Pages → Build and deployment → Source: **GitHub Actions**. After that, `push` to `main` auto-deploys via `.github/workflows/pages.yml` (build → upload artifact → deploy). PRs only build, never deploy.

* **Checks before PR**: `markdownlint-cli2 --config .markdownlint.yaml "**/*.md"` (ignores `site/`), `lychee --config lychee.toml "**/*.md"`, and `reuse lint` must pass. `site/` and `.cache/` are git-ignored.

### 5. Submitting Pull Requests

1. Fork the repository.
2. Create a feature branch (`git checkout -b feat/audio-improvement`).
3. Commit using Conventional Commits (`feat(audio): ...`, `fix(fingerprint): ...`, `docs: ...`).
4. Submit a Pull Request.
