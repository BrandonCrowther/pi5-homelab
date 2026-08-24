#!/usr/bin/env bash
# Vaultwarden restore.
#   ./restore.sh --verify  <archive>   decrypt + check, touch nothing
#   ./restore.sh --restore <archive>   stop, replace vw-data/, start
#
# The private key is deliberately NOT on this host, so both modes need it from
# wherever you stashed it:
#   gpg --homedir /tmp/k --import /media/usb/vaultwarden-backup-SECRET.asc
#   VW_BACKUP_GNUPGHOME=/tmp/k ./restore.sh --verify /var/backups/vaultwarden/<x>.gpg
#   rm -rf /tmp/k
# That friction is the point: it tests whether the offline key is still findable.
set -euo pipefail

VW_DIR=/home/admin/dev/pi5-homelab/vaultwarden
export GNUPGHOME="${VW_BACKUP_GNUPGHOME:-/root/.gnupg-vwbackup}"
MODE=${1:-}; ARCHIVE=${2:-}
[ -f "${ARCHIVE:-/nonexistent}" ] || { sed -n '2,12p' "$0"; exit 2; }

W=$(mktemp -d); chmod 700 "$W"; trap 'rm -rf "$W"' EXIT

gpg --batch --yes -d -o "$W/a.tar.gz" "$ARCHIVE" || {
  echo "DECRYPT FAILED -- private key not in GNUPGHOME=$GNUPGHOME?" >&2; exit 1; }
tar -xzf "$W/a.tar.gz" -C "$W"
# Listed BEFORE the sqlite check below: opening the db creates its own -wal/-shm
# in the extract dir, which would otherwise show up here as archive contents.
echo "  contents: $(ls -A "$W/vw-data" | tr '\n' ' ')"

# 2FA state comes from the `twofactor` table, NOT users.totp_secret -- that is a
# legacy column, NULL on 1.37.2 even with an authenticator enrolled. Reading it
# reports "no 2FA" on a protected account, mid-restore, which is a lie.
python3 - "$W/vw-data/db.sqlite3" <<'PY'
import sqlite3, sys
c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
chk = c.execute("PRAGMA integrity_check").fetchone()[0]
if chk != "ok": sys.exit(f"integrity_check FAILED: {chk}")
tf = {u for u, e in c.execute("select user_uuid, enabled from twofactor") if e}
print(f"  integrity: {chk}   ciphers: {c.execute('select count(*) from ciphers').fetchone()[0]}")
for uuid, email in c.execute("select uuid, email from users"):
    print(f"  {email}  2fa={'yes' if uuid in tf else 'NO'}")
PY
# Without rsa_key.pem every client is logged out after a restore.
[ -f "$W/vw-data/rsa_key.pem" ] || echo "  WARNING: no rsa_key.pem -- all sessions invalidated"

case "$MODE" in
  --verify) echo "VERIFY OK -- nothing on disk was touched" ;;
  --restore)
      docker compose -f "$VW_DIR/docker-compose.yaml" stop vaultwarden
      SIDE="$VW_DIR/vw-data.superseded-$(date -u +%Y%m%d-%H%M%S)"
      mv "$VW_DIR/vw-data" "$SIDE"
      cp -a "$W/vw-data" "$VW_DIR/vw-data"
      docker compose -f "$VW_DIR/docker-compose.yaml" up -d
      echo "restored. old data at $SIDE -- delete once you have logged in." ;;
  *) echo "want --verify or --restore" >&2; exit 2 ;;
esac
