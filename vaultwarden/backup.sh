#!/usr/bin/env bash
# Nightly Vaultwarden backup: consistent, encrypted to a key that is not on this
# host, reported to Home Assistant. Rationale: SECURITY-HANDOFF.md, Finding 5.
set -euo pipefail

VW=/home/admin/dev/pi5-homelab/vaultwarden/vw-data
DEST=/var/backups/vaultwarden
STATUS=/home/admin/dev/pi5-homelab/homeassistant/config/vaultwarden_backup.json
KEYID=D6883B705B0D600F
export GNUPGHOME=/root/.gnupg-vwbackup

OUT="$DEST/vaultwarden-$(date -u +%Y%m%d-%H%M%S).tar.gz.gpg"
W=$(mktemp -d); chmod 700 "$W"

# Status written on EVERY exit path. A script that reports only when it succeeds
# is indistinguishable from one that never ran; HA also checks this file's mtime.
finish() {
  local rc=$?
  printf '{"status":"%s","timestamp":"%s","ciphers":%s,"retained":%s}\n' \
    "$([ $rc -eq 0 ] && echo ok || echo failed)" "$(date -u +%FT%TZ)" \
    "${CIPHERS:-0}" "$(ls -1 "$DEST"/vaultwarden-*.gpg 2>/dev/null | wc -l)" > "$STATUS"
  chmod 644 "$STATUS"; rm -rf "$W"
}
trap finish EXIT

mkdir -p "$W/vw-data" "$DEST"; chmod 700 "$DEST"

# vw-data is WAL: copying db.sqlite3 alone silently drops recent transactions.
# The backup API folds the WAL in with no downtime, unlike stopping the container.
CIPHERS=$(python3 -c "
import sqlite3,sys
s=sqlite3.connect('$VW/db.sqlite3',timeout=30); d=sqlite3.connect('$W/vw-data/db.sqlite3')
with d: s.backup(d)
if d.execute('PRAGMA integrity_check').fetchone()[0]!='ok': sys.exit('integrity_check failed')
n=d.execute('select count(*) from ciphers').fetchone()[0]
s.close(); d.close()   # close() checkpoints and removes the copy's own -wal/-shm
print(n)")

# Everything else wholesale -- an explicit include-list already missed icon_cache/.
tar -C "$VW" --exclude=./db.sqlite3 --exclude='./db.sqlite3-*' --exclude=./tmp -cf - . \
  | tar -C "$W/vw-data" -xf -

tar -czf - -C "$W" vw-data | gpg --batch --yes --trust-model always -e -r "$KEYID" -o "$OUT"
chmod 600 "$OUT"

# Right key? --list-only parses structure without the secret key, which is offline.
gpg --batch --list-only --list-packets "$OUT" | grep -q "keyid $KEYID"

# Count-based, not `find -mtime +30`: the Pi is not always on, and time-based
# deletion wipes every backup after a month offline.
ls -1t "$DEST"/vaultwarden-*.gpg | tail -n +31 | xargs -r rm -f
echo "ok: $(basename "$OUT") ciphers=$CIPHERS"
