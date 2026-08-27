#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Backward compatibility wrapper for audio/install-audio.sh
# Chell uses Intel AVS - no sof-rt5682 UCM mirror needed; this wrapper forwards to the AVS installer.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[INFO] Chell uses Intel AVS (avs_ssm4567/nau8825/dmic), not SOF sof-rt5682." >&2
echo "[INFO] Forwarding to install-audio.sh (UCM fallback + mixer + WirePlumber) ..." >&2
exec "$SCRIPT_DIR/install-audio.sh" "$@"
