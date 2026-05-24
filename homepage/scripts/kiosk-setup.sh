#!/bin/bash
# One-time bootstrap: installs the kiosk autostart entry for labwc.
# Run as the desktop user (admin). Safe to re-run.
set -e

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIOSK_SCRIPT="$REPO_DIR/homepage/scripts/kiosk-start.sh"
AUTOSTART_DIR="$HOME/.config/labwc"
AUTOSTART_FILE="$AUTOSTART_DIR/autostart"
SYSTEM_AUTOSTART="/etc/xdg/labwc/autostart"

chmod +x "$KIOSK_SCRIPT"
mkdir -p "$AUTOSTART_DIR"

# Seed from system defaults so existing desktop entries are preserved
if [ ! -f "$AUTOSTART_FILE" ] && [ -f "$SYSTEM_AUTOSTART" ]; then
    cp "$SYSTEM_AUTOSTART" "$AUTOSTART_FILE"
    echo "Seeded $AUTOSTART_FILE from system defaults."
fi

if ! grep -qF "kiosk-start.sh" "$AUTOSTART_FILE"; then
    printf '\n# Homepage kiosk display\n%s &\n' "$KIOSK_SCRIPT" >> "$AUTOSTART_FILE"
    echo "Added kiosk entry to $AUTOSTART_FILE"
else
    echo "Kiosk entry already present — no changes made."
fi

echo "Done. Reboot (or restart LightDM) to activate."
