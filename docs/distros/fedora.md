# 🐧 Fedora Configuration Guide

Applies to: **Fedora Workstation 39 / 40 / 41**, **Fedora Silverblue**, **Nobara**, **RHEL 9**.

---

## 1. Quick Automated Installation

```bash
git clone https://github.com/samson1357924/hp-chromebook-13-g1-linux.git
cd hp-chromebook-13-g1-linux
chmod +x setup.sh
./setup.sh --all
```

---

## 2. Manual Step-by-Step Guide

### (1) Install Package Dependencies

```bash
sudo dnf install -y gcc meson ninja-build pkgconf-pkg-config \
                    glib2-devel libgusb-devel pixman-devel \
                    libgudev-devel json-glib-devel \
                    gobject-introspection-devel fprintd fprintd-pam \
                    linux-firmware pipewire wireplumber alsa-ucm
```

> [!NOTE]
> Chell (HP Chromebook 13 G1) uses Intel AVS (`snd_soc_avs`), not SOF.
> Audio firmware is `/lib/firmware/intel/avs/` from `linux-firmware`;
> do not install `alsa-sof-firmware` for audio.

### (2) Deploy Audio UCM Configuration

```bash
sudo ./audio/install-audio.sh --install
# Verifies AVS modules/firmware, UCM fallbacks, mixer unmute, WirePlumber priority.
./audio/diagnose-audio.sh
```

### (3) Deploy Keyboard Top-Row Mapping

```bash
sudo cp keyboard/90-chromebook-keyboard.hwdb /etc/udev/hwdb.d/
sudo systemd-hwdb update
sudo udevadm trigger --subsystem-match=input
```

### (4) Compile the Fingerprint Driver and Configure PAM (authselect)

```bash
# Compile and install to /usr/lib64 using this project's script
./fingerprint/install-fingerprint.sh
```

> [!IMPORTANT]
> Do **not** run `authselect enable-feature with-fingerprint`. That feature
> injects `pam_fprintd` into `system-auth`, which `gdm-password` includes —
> on unlock GDM forks the `gdm-password` and `gdm-fingerprint` workers
> concurrently and both try to Claim the single fprintd device, so the lock
> screen shows no fingerprint prompt (GNOME/gdm#1071). Keep fingerprint
> **only in `/etc/pam.d/sudo`**:

```bash
# Make sure the with-fingerprint feature stays disabled
sudo authselect disable-feature with-fingerprint
sudo authselect apply-changes

# Enable fingerprint for sudo only
echo 'auth sufficient pam_fprintd.so' | sudo tee /etc/pam.d/sudo
sudo chmod 0644 /etc/pam.d/sudo
```
