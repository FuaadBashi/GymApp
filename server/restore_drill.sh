#!/bin/sh
# Restore drill: proves a backup can bring the data back. It syncs rows into a fresh database
# through the API, dumps it with pg_dump, restores the dump into a second database, and checks
# that a server on the restored copy returns exactly the same rows.
# Needs local Postgres (createdb, pg_dump, pg_restore) and a built server (swift build).
set -eu
cd "$(dirname "$0")"
SRC=bashi_drill_src DST=bashi_drill_restored PORT=8091 DUMP=$(mktemp -t bashi-drill).dump
BIN=.build/debug/Run
[ -x "$BIN" ] || swift build --product Run
cleanup() { [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; dropdb --if-exists "$SRC"; dropdb --if-exists "$DST"; rm -f "$DUMP"; }
trap cleanup EXIT
dropdb --if-exists "$SRC"; dropdb --if-exists "$DST"; createdb "$SRC"; createdb "$DST"

serve() {
  AUTH_DEV=1 DATABASE_NAME="$1" "$BIN" serve --port $PORT >/dev/null 2>&1 & PID=$!
  i=0; until curl -s -o /dev/null "http://localhost:$PORT/health"; do i=$((i+1)); [ $i -lt 50 ] || { echo "server did not start"; exit 1; }; sleep 0.2; done
}

serve "$SRC"
python3 -I - "$PORT" write <<'PY'
import json, sys, urllib.request
port = sys.argv[1]
def call(path, body=None, token=None, method=None):
    req = urllib.request.Request(f"http://localhost:{port}{path}", data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + token} if token else {})}, method=method)
    with urllib.request.urlopen(req) as r: return json.loads(r.read() or "null")
token = call("/v1/auth/dev", {"subject": "drill"})["accessToken"]
changes = [{"table": "workoutSet", "id": f"S{i}", "op": "upsert", "updatedAt": 1_790_000_000_000 + i,
            "row": {"id": f"S{i}", "workoutExerciseId": "WE", "position": i, "loadHundredths": 10_000 + 250 * i,
                    "unit": "kg", "reps": 8, "type": "working", "annotations": []}} for i in range(450)]
for start in range(0, len(changes), 200): call("/v1/sync/push", {"changes": changes[start:start + 200]}, token)
call("/v1/sync/push", {"changes": [{"table": "workoutSet", "id": "S7", "op": "delete", "updatedAt": 1_790_000_009_999}]}, token)
PY
snapshot() {
  python3 -I - "$PORT" <<'PY'
import json, sys, urllib.request, hashlib
port = sys.argv[1]
req = urllib.request.Request(f"http://localhost:{port}/v1/auth/dev", data=b'{"subject":"drill"}', headers={"Content-Type": "application/json"})
token = json.loads(urllib.request.urlopen(req).read())["accessToken"]
rows, cur = [], 0
while True:
    r = json.loads(urllib.request.urlopen(urllib.request.Request(f"http://localhost:{port}/v1/sync/pull?since={cur}",
                                                                 headers={"Authorization": "Bearer " + token})).read())
    rows += r["changes"]; cur = r["nextCursor"]
    if not r["hasMore"]: break
print(len(rows), sum(c["op"] == "delete" for c in rows), hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()[:16])
PY
}
BEFORE=$(snapshot); kill "$PID"; wait "$PID" 2>/dev/null || true; PID=

pg_dump --format=custom --no-owner "$SRC" > "$DUMP"
pg_restore --no-owner --dbname="$DST" "$DUMP"

serve "$DST"
AFTER=$(snapshot)
echo "before restore: rows, tombstones, hash = $BEFORE"
echo "after restore:  rows, tombstones, hash = $AFTER"
[ "$BEFORE" = "$AFTER" ] && echo "PASS: the restored copy returns exactly the same rows" || { echo "FAIL: the restored copy differs"; exit 1; }
