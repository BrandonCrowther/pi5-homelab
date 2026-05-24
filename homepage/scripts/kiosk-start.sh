#!/bin/bash
# Waits for homepage to be available, then opens Chromium in kiosk mode.
# Launched from ~/.config/labwc/autostart via kiosk-setup.sh.
until curl -sf http://localhost:3000 > /dev/null 2>&1; do
    sleep 2
done

exec chromium \
    --ozone-platform=wayland \
    --disable-gpu \
    --password-store=basic \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --no-first-run \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    http://localhost:3000
