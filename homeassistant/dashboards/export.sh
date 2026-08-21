#!/bin/bash
# Refresh service-dashboard.yaml from Home Assistant's live copy.
#
# The Service Dashboard is storage-mode: HA owns it in
# ../config/.storage/lovelace.service_dashboard and the UI can edit it, so this
# repo file goes stale the moment you rearrange a card. Run this afterwards to
# bring it back in step.
#
# Needs sudo: .storage is root-owned and holds auth tokens alongside this file.
#
# CAVEAT: the leading comment block is preserved, but INLINE comments inside
# the views body are lost. HA's stored copy is JSON and never held them, so
# there is nothing to dump them back from. Running this trades the annotations
# in that file for an accurate snapshot -- worth it after real UI edits, not
# worth it just to tidy up. `git diff` afterwards shows exactly what you lose.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
STORE="$DIR/../config/.storage/lovelace.service_dashboard"
OUT="$DIR/service-dashboard.yaml"

[ -r "$OUT" ] || { echo "missing $OUT" >&2; exit 1; }
sudo test -r "$STORE" || { echo "cannot read $STORE (try sudo)" >&2; exit 1; }

# Keep every line up to (not including) the first non-comment, non-blank line.
awk '/^[^#]/ && NF { exit } { print }' "$OUT" > "$OUT.tmp"

sudo cat "$STORE" | python3 -c '
import json, sys, yaml
cfg = json.load(sys.stdin)["data"]["config"]
yaml.safe_dump(cfg, sys.stdout, sort_keys=False, allow_unicode=True, width=100)
' >> "$OUT.tmp"

mv "$OUT.tmp" "$OUT"
echo "refreshed $OUT"
