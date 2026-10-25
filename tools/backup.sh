#!/bin/sh
# Weekly backup of the hosted sync database (server/README.md, "Backups"). The connection
# string lives in the login Keychain, never in a file:
#   security add-generic-password -s bashi-neon -a backup -w '<postgresql://...>'
# Usage: tools/backup.sh   writes ~/Backups/bashi-gym/bashi-YYYY-MM-DD.dump and keeps the newest 8.
set -eu
URL=$(security find-generic-password -s bashi-neon -a backup -w 2>/dev/null || true)
[ -n "$URL" ] || { echo "No connection string in the Keychain (service bashi-neon). See the comment at the top."; exit 1; }
DIR="$HOME/Backups/bashi-gym"; mkdir -p "$DIR"
OUT="$DIR/bashi-$(date +%F).dump"
pg_dump --format=custom --no-owner "$URL" > "$OUT.partial"
mv "$OUT.partial" "$OUT"
# A backup is only proof if it restores: list its contents and count the synced rows.
pg_restore --list "$OUT" | grep -q 'TABLE DATA public sync_row' || { echo "Backup has no sync_row data: $OUT"; exit 1; }
ls -1t "$DIR"/bashi-*.dump | tail -n +9 | while read -r old; do rm -f "$old"; done
echo "Backup written: $OUT ($(du -h "$OUT" | cut -f1)). Kept: $(ls "$DIR"/bashi-*.dump | wc -l | tr -d ' ')"
