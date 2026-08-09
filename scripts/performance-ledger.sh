#!/bin/sh
set -eu

usage() {
  echo "usage: scripts/performance-ledger.sh start <cold|warm> <absolute-jsonl-path> | report <jsonl-path>" >&2
  exit 64
}

[ "$#" -ge 2 ] || usage
action=$1

if [ "$action" = "start" ]; then
  [ "$#" -eq 3 ] || usage
  lane=$2
  ledger=$3
  [ "$lane" = "cold" ] || [ "$lane" = "warm" ] || usage
  case "$ledger" in /*) ;; *) echo "ledger path must be absolute" >&2; exit 64 ;; esac
  if [ "$lane" = "cold" ] && pgrep -x GrokBuild >/dev/null; then
    echo "cold sample requires process-zero" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$ledger")"
  : > "$ledger"
  open --env "GROKBUILD_PERFORMANCE_LEDGER=$ledger" /Applications/GrokBuild.app
  echo "Recording $lane stages in $ledger. Drive one fresh-thread task, wait for settlement, then quit normally and run:"
  echo "  scripts/performance-ledger.sh report '$ledger'"
  exit 0
fi

[ "$action" = "report" ] && [ "$#" -eq 2 ] || usage
ledger=$2
[ -s "$ledger" ] || { echo "ledger is empty: $ledger" >&2; exit 1; }
/usr/bin/python3 - "$ledger" <<'PY'
import collections, json, sys

rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
required = [
    "appLaunch", "firstWindow", "layoutLoaded", "restoreCompleted", "transcriptLoaded",
    "submitIntent", "processSpawned", "acpReady", "sessionReady", "modelConfirmed",
    "selectedMCPReady", "dispatch", "firstChunk", "settled",
]
counts = collections.Counter(row["stage"] for row in rows)
seen = collections.Counter()
previous = None
for row in sorted(rows, key=lambda value: value["elapsed_ms"]):
    stage = row["stage"]
    seen[stage] += 1
    suffix = f" #{seen[stage]}" if counts[stage] > 1 else ""
    elapsed = row["elapsed_ms"]
    delta = 0.0 if previous is None else elapsed - previous
    print(f"{stage + suffix:24} {elapsed:9.1f} ms  (+{delta:8.1f})")
    previous = elapsed

missing = [stage for stage in required if counts[stage] == 0]
if missing:
    print("missing: " + ", ".join(missing))
PY
