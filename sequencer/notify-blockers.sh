#!/usr/bin/env bash
set -euo pipefail

FEATURE_LIST="/home/slimy/feature_list.json"
BLOCKER_REPORT="/home/slimy/blocker-report.md"

log() { echo "[$(date -Iseconds)] [notify-blockers] $*"; }

WEBHOOK_URL="${DISCORD_BLOCKER_WEBHOOK:-}"
if [ -z "$WEBHOOK_URL" ]; then
  WEBHOOK_URL=$(grep -oP 'https://discord\.com/api/webhooks/[^\s""]+' /usr/local/bin/sr-notify 2>/dev/null | head -1 || true)
fi

if [ -z "$WEBHOOK_URL" ]; then
  log "No Discord webhook URL found. Set DISCORD_BLOCKER_WEBHOOK or ensure sr-notify has one."
  exit 0
fi

if [ ! -f "$FEATURE_LIST" ]; then
  log "ERROR: feature_list.json not found"
  exit 1
fi

PAYLOAD=$(python3 << 'PYEOF'
import json

feature_list_path = "/home/slimy/feature_list.json"

with open(feature_list_path) as f:
    fl = json.load(f)

features = fl.get("features", [])
blocked = []
available = []
completed = []

for feat in features:
    blocked_by = feat.get("blocked_by", [])
    status = feat.get("status", "open")
    passes = feat.get("passes", False)

    if passes or status == "completed":
        completed.append(feat)
    elif blocked_by and len(blocked_by) > 0:
        blocked.append(feat)
    else:
        available.append(feat)

lines = []

if blocked:
    lines.append(f"🔴 **{len(blocked)} tasks need human action:**")
    for feat in blocked[:10]:
        fid = feat.get("id", "?")
        proj = feat.get("project", "?")
        blocker_desc = ", ".join(feat.get("blocked_by", []))
        lines.append(f"- `{fid}` ({proj}): {blocker_desc}")
    lines.append("")

lines.append(f"🟢 **{len(available)} tasks available for auto-dispatch**")
lines.append(f"📊 **{len(completed)} completed | {len(features)} total**")

msg = "\n".join(lines)

payload = {"content": msg}
print(json.dumps(payload))
PYEOF
)

if [ -n "$PAYLOAD" ]; then
  RESPONSE=$(curl -s -w "\n%{http_code}" -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL" 2>/dev/null || echo "000")
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
    log "Discord notification sent (HTTP $HTTP_CODE)"
  else
    log "Discord notification failed (HTTP $HTTP_CODE)"
  fi
fi
