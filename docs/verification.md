# ✅ Verification Matrix (HP Chromebook 13 G1 - chell)

## Test Environment

| Item | Value |
| :--- | :--- |
| **Device** | HP Chromebook 13 G1 (board `chell`, SKU 10467908) |
| **Board** | `chell` 1.0, MrChromebox 2606.1, m7-6Y75 |
| **OS** | Ubuntu 26.04.1 LTS, Wayland, kernel 7.0.0-14-generic |
| **Graphics** | simpledrm (nomodeset trap), i915 available but blocked |
| **Audio** | AVS SSM4567/NAU8825/DMIC, PipeWire 1.6.2 |
| **Network** | 7265 AC, wlp1s0 |

## Verified

* **EC** `/dev/cros_ec` + `/dev/cros_pd` present
* **Audio** 3 cards via `aplay -l`, wpctl sinks/sources OK
* **Wi-Fi/BT** iwlwifi/btusb bound, connected
* **Display** 1920x1080 via simpledrm (needs i915 fix)

## Untested / Needs Fix

* **i915 acceleration** - blocked by nomodeset, fix via `scripts/fix-graphics.sh`
* **Touchpad gestures**, **backlight**, **S3 resume**, **Type-C DP**
* **Fingerprint** - N/A (no hardware)

See VERIFICATION for evidence vs claims.
