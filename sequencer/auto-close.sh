#!/usr/bin/env bash
# auto-close.sh — close out a session report
#
# - Updates feature_list.json (passes/last_attempted/attempt_count/blocked_by)
# - Appends a failed-approach entry to /home/slimy/failed-approaches.json
#   when status=completed AND tests.passed=false, OR status=blocked
# - Validates both JSON files after every write
#
# SkillOpt intelligence layer: track what failed so agents stop repeating
# the same approaches.
set -euo pipefail

SESSION_REPORT="/home/slimy/session-report.json"
FEATURE_LIST="/home/slimy/feature_list.json"
FAILED_APPROACHES="/home/slimy/failed-approaches.json"

log() { echo "[$(date -Iseconds)] [auto-close] $*"; }

if [ ! -f "$SESSION_REPORT" ]; then
  log "No session report at $SESSION_REPORT. Nothing to close."
  exit 0
fi

if [ ! -f "$FEATURE_LIST" ]; then
  log "ERROR: feature_list.json not found at $FEATURE_LIST"
  exit 1
fi

# Ensure failed-approaches.json exists with correct schema
if [ ! -f "$FAILED_APPROACHES" ]; then
  log "Creating $FAILED_APPROACHES with default schema"
  cat > "$FAILED_APPROACHES" << 'EOF'
{
  "version": 1,
  "entries": []
}
EOF
fi

python3 << PYEOF
import json
import os
import shutil
from datetime import datetime, timezone

session_report_path = "$SESSION_REPORT"
feature_list_path = "$FEATURE_LIST"
failed_approaches_path = "$FAILED_APPROACHES"

with open(session_report_path) as f:
    report = json.load(f)

with open(feature_list_path) as f:
    fl = json.load(f)

with open(failed_approaches_path) as f:
    failed = json.load(f)

feature_id = report.get("feature_id")
status = report.get("status")
tests_passed = report.get("tests", {}).get("passed", False)
blockers = report.get("blockers", [])

if not feature_id:
    print("[auto-close] No feature_id in session report. Nothing to close.")
    raise SystemExit(0)

now_iso = datetime.now(timezone.utc).isoformat()
feature_found = False

# Track current attempt number for this feature (count of prior failed-approaches
# entries + 1) so callers can correlate attempts across the buffer.
prior_attempts = sum(1 for e in failed.get("entries", []) if e.get("feature_id") == feature_id)
attempt_number = prior_attempts + 1


def log_failed_approach(reason_text):
    """Append a failed-approach entry to /home/slimy/failed-approaches.json.

    Used regardless of whether the feature_id is in feature_list.json — the
    failed-approach buffer is the source of truth for what NOT to retry, and
    we want to log even ad-hoc / unknown feature IDs.
    """
    approach = (
        report.get("summary")
        or report.get("work_done")
        or (report.get("notes", "")[:200] if report.get("notes") else "")
        or "(no description provided)"
    )
    entry = {
        "feature_id": feature_id,
        "repo": report.get("project", ""),
        "timestamp": now_iso,
        "approach_description": approach[:500],
        "failure_reason": reason_text[:500],
        "session_report_ref": os.path.basename(session_report_path),
        "attempt_number": attempt_number,
    }
    failed.setdefault("entries", []).append(entry)
    print(f"[auto-close] Logged failed approach #{attempt_number} for {feature_id} -> failed-approaches.json")

for feat in fl.get("features", []):
    if feat.get("id") != feature_id:
        continue
    feature_found = True

    feat["last_attempted"] = now_iso
    feat["attempt_count"] = feat.get("attempt_count", 0) + 1

    if status == "completed" and tests_passed:
        feat["passes"] = True
        feat["status"] = "completed"
        print(f"[auto-close] Auto-closed feature {feature_id} - agent completed with passing tests")
    elif status == "completed" and not tests_passed:
        # SkillOpt: log the failed approach
        # Prefer summary, fall back to work_done, fall back to first 200 chars of notes
        approach = (
            report.get("summary")
            or report.get("work_done")
            or (report.get("notes", "")[:200] if report.get("notes") else "")
            or "(no description provided)"
        )
        failure_reason_parts = []
        test_details = report.get("tests", {}).get("details", "")
        if test_details:
            failure_reason_parts.append(test_details)
        else:
            failure_reason_parts.append("tests.passed=false")
        if report.get("errors"):
            failure_reason_parts.append("errors: " + "; ".join(str(e) for e in report.get("errors", [])))

        entry = {
            "feature_id": feature_id,
            "repo": report.get("project", ""),
            "timestamp": now_iso,
            "approach_description": approach[:500],
            "failure_reason": " | ".join(failure_reason_parts)[:500],
            "session_report_ref": os.path.basename(session_report_path),
            "attempt_number": attempt_number,
        }
        failed.setdefault("entries", []).append(entry)
        print(f"[auto-close] Feature {feature_id} completed but tests failed - logged approach #{attempt_number} to failed-approaches.json")
        # Original behavior: do NOT mark passes
    elif status in ("partial", "failed"):
        # SkillOpt: also log partial / failed sessions
        approach = (
            report.get("summary")
            or report.get("work_done")
            or (report.get("notes", "")[:200] if report.get("notes") else "")
            or "(no description provided)"
        )
        failure_reason = f"status={status}"
        if report.get("errors"):
            failure_reason += " | errors: " + "; ".join(str(e) for e in report.get("errors", []))
        entry = {
            "feature_id": feature_id,
            "repo": report.get("project", ""),
            "timestamp": now_iso,
            "approach_description": approach[:500],
            "failure_reason": failure_reason[:500],
            "session_report_ref": os.path.basename(session_report_path),
            "attempt_number": attempt_number,
        }
        failed.setdefault("entries", []).append(entry)
        print(f"[auto-close] Feature {feature_id} session ended with status:{status} - logged approach #{attempt_number}")
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

        # SkillOpt: also log blocked sessions
        blocker_summary = "; ".join(
            f"{b.get('type','?')}:{b.get('description','?')}" for b in blockers
        ) or "(no blocker description)"
        entry = {
            "feature_id": feature_id,
            "repo": report.get("project", ""),
            "timestamp": now_iso,
            "approach_description": (
                report.get("summary")
                or report.get("work_done")
                or "(no description provided)"
            )[:500],
            "failure_reason": f"BLOCKED: {blocker_summary}"[:500],
            "session_report_ref": os.path.basename(session_report_path),
            "attempt_number": attempt_number,
        }
        failed.setdefault("entries", []).append(entry)
        print(f"[auto-close] Feature {feature_id} blocked reason logged to failed-approaches.json")
    else:
        print(f"[auto-close] Feature {feature_id} unknown status:{status}")

    break

if not feature_found:
    print(f"[auto-close] WARNING: feature_id '{feature_id}' not found in feature_list.json")
    # SkillOpt: still log the failed approach for unknown / ad-hoc feature IDs
    # so the buffer is the source of truth for "do not retry this".
    if status == "completed" and not tests_passed:
        test_details = report.get("tests", {}).get("details", "") or "tests.passed=false"
        log_failed_approach(test_details)
    elif status in ("partial", "failed"):
        reason = f"status={status}"
        if report.get("errors"):
            reason += " | errors: " + "; ".join(str(e) for e in report.get("errors", []))
        log_failed_approach(reason)
    elif status == "blocked":
        blocker_summary = "; ".join(
            f"{b.get('type','?')}:{b.get('description','?')}" for b in blockers
        ) or "(no blocker description)"
        log_failed_approach(f"BLOCKED: {blocker_summary}")

# Atomic write of feature_list.json
tmp_fl = feature_list_path + ".tmp"
with open(tmp_fl, "w") as f:
    json.dump(fl, f, indent=2)
    f.write("\n")
os.replace(tmp_fl, feature_list_path)

# Atomic write of failed-approaches.json
tmp_fa = failed_approaches_path + ".tmp"
with open(tmp_fa, "w") as f:
    json.dump(failed, f, indent=2)
    f.write("\n")
os.replace(tmp_fa, failed_approaches_path)

print(f"[auto-close] feature_list.json updated ({len(fl.get('features', []))} features)")
print(f"[auto-close] failed-approaches.json updated ({len(failed.get('entries', []))} total entries)")
PYEOF

# Validate both JSONs
python3 -c "import json; json.load(open('$FEATURE_LIST')); print('[auto-close] feature_list.json validated OK')"
python3 -c "import json; json.load(open('$FAILED_APPROACHES')); print('[auto-close] failed-approaches.json validated OK')"
