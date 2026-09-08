# 🐧 openSUSE Configuration Guide

Applies to: **openSUSE Tumbleweed**, **openSUSE Leap 15.x**.

---

## 1. Quick Automated Installation

```bash
git clone https://github.com/samson1357924/hp-chromebook-13-g1-linux.git
cd hp-chromebook-13-g1-linux
chmod +x setup.sh
./setup.sh --all
```

---

## 2. Manual Step-by-Step Setup

### (1) Install Package Dependencies

```bash
sudo zypper install -y patterns-devel-base-devel_basis meson ninja pkg-config \
                       glib2-devel libgusb-devel libpixman-1-0-devel \
                       libgudev-1_0-devel json-glib-devel \
                       gobject-introspection-devel fprintd fprintd-pam \
                       kernel-firmware pipewire wireplumber alsa-ucm-conf
```

> [!NOTE]
> Chell (HP Chromebook 13 G1) uses Intel AVS (`snd_soc_avs`), not SOF.
> Audio firmware is `/lib/firmware/intel/avs/` from `kernel-firmware`;
> do not install `sof-firmware` for audio.

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

### (4) Configure Fingerprint PAM (pam-config)

```bash
./fingerprint/install-fingerprint.sh
```

> [!IMPORTANT]
> Do **not** run `pam-config -a --fprintd`: it injects `pam_fprintd` into
> `common-auth`, which `gdm-password` includes — on unlock GDM forks the
> `gdm-password` and `gdm-fingerprint` workers concurrently and both try to
> Claim the single fprintd device, so the lock screen shows no fingerprint
> prompt (GNOME/gdm#1071). Keep fingerprint **only in `/etc/pam.d/sudo`**:

```bash
sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.bak
sudo sed -i '1i auth sufficient pam_fprintd.so' /etc/pam.d/sudo
```
