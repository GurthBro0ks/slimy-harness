#!/usr/bin/env bash
set -euo pipefail

FEATURE_LIST="/home/slimy/feature_list.json"
SESSION_REPORT="/home/slimy/session-report.json"
OUTPUT="/home/slimy/blocker-report.md"

log() { echo "[$(date -Iseconds)] [blocker-report] $*"; }

if [ ! -f "$FEATURE_LIST" ]; then
  log "ERROR: feature_list.json not found"
  exit 1
fi

python3 << 'PYEOF'
import json
from datetime import datetime, timezone

feature_list_path = "/home/slimy/feature_list.json"
session_report_path = "/home/slimy/session-report.json"
output_path = "/home/slimy/blocker-report.md"

with open(feature_list_path) as f:
    fl = json.load(f)

report = {}
try:
    with open(session_report_path) as f:
        report = json.load(f)
except:
    pass

features = fl.get("features", [])
today = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

blocked = []
available = []
completed = []
failed_retrying = []

for feat in features:
    blocked_by = feat.get("blocked_by", [])
    status = feat.get("status", "open")
    passes = feat.get("passes", False)

    if passes or status == "completed":
        completed.append(feat)
    elif blocked_by and len(blocked_by) > 0:
        blocked.append(feat)
    elif status in ("partial", "failed") and not passes:
        failed_retrying.append(feat)
    else:
        available.append(feat)

lines = []
lines.append(f"# Blocker Report — {today}")
lines.append("")

lines.append(f"## Tasks Needing Human Action ({len(blocked)})")
lines.append("")
if blocked:
    lines.append("| Feature | Project | Blocked By | Priority |")
    lines.append("|---------|---------|------------|----------|")
    for feat in blocked:
        fid = feat.get("id", "?")
        proj = feat.get("project", "?")
        blockers_str = ", ".join(feat.get("blocked_by", []))
        prio = feat.get("priority", "medium")
        lines.append(f"| {fid} | {proj} | {blockers_str} | {prio} |")
else:
    lines.append("_No blocked tasks._")
lines.append("")

failed_sorted = sorted(failed_retrying, key=lambda f: f.get("attempt_count", 0), reverse=True)[:3]
lines.append(f"## Recently Failed (last 3 attempts, not yet passing)")
lines.append("")
if failed_sorted:
    lines.append("| Feature | Project | Attempts | Last Tried | Priority |")
    lines.append("|---------|---------|----------|------------|----------|")
    for feat in failed_sorted:
        fid = feat.get("id", "?")
        proj = feat.get("project", "?")
        attempts = feat.get("attempt_count", 0)
        last = feat.get("last_attempted", "never")
        prio = feat.get("priority", "medium")
        lines.append(f"| {fid} | {proj} | {attempts} | {last} | {prio} |")
else:
    lines.append("_No recently failed tasks._")
lines.append("")

lines.append(f"## Available for Auto-Dispatch ({len(available)})")
lines.append("")
if available:
    lines.append("| Feature | Project | Priority | Risk |")
    lines.append("|---------|---------|----------|------|")
    for feat in available:
        fid = feat.get("id", "?")
        proj = feat.get("project", "?")
        prio = feat.get("priority", "medium")
        risk = feat.get("risk", "medium")
        lines.append(f"| {fid} | {proj} | {prio} | {risk} |")
else:
    lines.append("_No available tasks._")
lines.append("")

completed_today = [f for f in completed if f.get("last_attempted", "") and f.get("last_attempted", "").startswith(today[:10])]
lines.append(f"## Completed Today ({len(completed_today)})")
lines.append("")
if completed_today:
    for feat in completed_today:
        summary = ""
        if report.get("feature_id") == feat.get("id"):
            summary = report.get("summary", "")
        fid = feat.get("id", "?")
        lines.append(f"- {fid}: {summary or '(no session report)'}")
else:
    lines.append("_No tasks completed today._")
lines.append("")

total = len(features)
completed_count = len(completed)
available_count = len(available)
blocked_count = len(blocked)
failed_count = len(failed_retrying)

lines.append("## Stats")
lines.append(f"- Total features: {total}")
lines.append(f"- Completed: {completed_count}")
lines.append(f"- Available: {available_count}")
lines.append(f"- Blocked: {blocked_count}")
lines.append(f"- Failed/Retrying: {failed_count}")
lines.append("")

with open(output_path, "w") as f:
    f.write("\n".join(lines))

print(f"[blocker-report] Generated {output_path} ({total} features, {blocked_count} blocked, {available_count} available)")

PYEOF
