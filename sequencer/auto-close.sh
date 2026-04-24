#!/usr/bin/env bash
set -euo pipefail

SESSION_REPORT="/home/slimy/session-report.json"
FEATURE_LIST="/home/slimy/feature_list.json"

log() { echo "[$(date -Iseconds)] [auto-close] $*"; }

if [ ! -f "$SESSION_REPORT" ]; then
  log "No session report at $SESSION_REPORT. Nothing to close."
  exit 0
fi

if [ ! -f "$FEATURE_LIST" ]; then
  log "ERROR: feature_list.json not found at $FEATURE_LIST"
  exit 1
fi

python3 << 'PYEOF'
import json
from datetime import datetime, timezone

session_report_path = "/home/slimy/session-report.json"
feature_list_path = "/home/slimy/feature_list.json"

with open(session_report_path) as f:
    report = json.load(f)

with open(feature_list_path) as f:
    fl = json.load(f)

feature_id = report.get("feature_id")
status = report.get("status")
tests_passed = report.get("tests", {}).get("passed", False)
blockers = report.get("blockers", [])

if not feature_id:
    print(f"[auto-close] No feature_id in session report. Nothing to close.")
    exit(0)

now_iso = datetime.now(timezone.utc).isoformat()
feature_found = False

for feat in fl.get("features", []):
    if feat.get("id") != feature_id:
        continue
    feature_found = True

    feat["last_attempted"] = now_iso
    feat["attempt_count"] = feat.get("attempt_count", 0) + 1

    if status == "completed" and tests_passed:
        feat["passes"] = True
        feat["status"] = "completed"
        print(f"[auto-close] Auto-closed feature {feature_id} — agent completed with passing tests")
    elif status == "completed" and not tests_passed:
        print(f"[auto-close] Feature {feature_id} reported completed but tests failed — not closing")
    elif status in ("partial", "failed"):
        print(f"[auto-close] Feature {feature_id} session ended with status:{status}")
    elif status == "blocked":
        existing_blockers = feat.get("blocked_by", [])
        for blocker in blockers:
            blocker_str = f"{blocker.get('type', 'manual')}:{blocker.get('description', 'unknown')}"
            if blocker_str not in existing_blockers:
                existing_blockers.append(blocker_str)
        feat["blocked_by"] = existing_blockers
        feat["status"] = "blocked"
        blocker_descs = ", ".join(b.get("description", "?") for b in blockers)
        print(f"[auto-close] Feature {feature_id} blocked: {blocker_descs}")
    else:
        print(f"[auto-close] Feature {feature_id} unknown status:{status}")

    break

if not feature_found:
    print(f"[auto-close] WARNING: feature_id '{feature_id}' not found in feature_list.json")

with open(feature_list_path, "w") as f:
    json.dump(fl, f, indent=2)

PYEOF

python3 -c "import json; json.load(open('$FEATURE_LIST')); print('[auto-close] feature_list.json validated OK')"
