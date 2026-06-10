#!/usr/bin/env bash
set -euo pipefail

FEATURE_LIST="${FEATURE_LIST:-/home/slimy/feature_list.json}"
BLOCKER_REPORT="${BLOCKER_REPORT:-/home/slimy/blocker-report.md}"
BLOCKER_CACHE="${BLOCKER_CACHE:-/home/slimy/.last-blocker-report.md}"
SEQUNCER_DIR="/home/slimy/slimy-harness/sequencer"

log() { echo "[$(date -Iseconds)] [notify-blockers] $*"; }

if [ -n "${HARNESS_SMOKE_ROOT:-}" ]; then
  log "Skipping Discord blocker notification (HARNESS_SMOKE_ROOT set)"

  if [ -f "$FEATURE_LIST" ] && [ -f "${BLOCKER_REPORT:-}" ]; then
    SMOKE_CACHE="${BLOCKER_CACHE:-"${HARNESS_SMOKE_ROOT}/.last-blocker-report.md"}"
    cp "$BLOCKER_REPORT" "$SMOKE_CACHE" 2>/dev/null || true
  fi

  exit 0
fi

# Load harness env for DISCORD_HARNESS_WEBHOOK_URL
# shellcheck disable=SC1090
if [ -f "${SEQUNCER_DIR}/harness-env.sh" ]; then
  source "${SEQUNCER_DIR}/harness-env.sh"
fi

# Use harness webhook from env; fallback to sr-notify for backwards compat
WEBHOOK_URL="${DISCORD_HARNESS_WEBHOOK_URL:-}"
if [ -z "$WEBHOOK_URL" ]; then
  WEBHOOK_URL=$(grep -oP 'https://discord\.com/api/webhooks/[^\s""]+' /usr/local/bin/sr-notify 2>/dev/null | head -1 || true)
fi

if [ -z "$WEBHOOK_URL" ]; then
  log "No Discord webhook URL found. Set DISCORD_HARNESS_WEBHOOK_URL in ${HARNESS_ENV_FILE:-/home/slimy/.slimy-harness.env} or ensure sr-notify has one."
  exit 0
fi

if [ ! -f "$FEATURE_LIST" ]; then
  log "ERROR: feature_list.json not found"
  exit 1
fi

BLOCKERS_CHANGED=1
if [ -f "$BLOCKER_REPORT" ] && [ -f "$BLOCKER_CACHE" ]; then
  CURRENT_MD5=$(md5sum "$BLOCKER_REPORT" | cut -d' ' -f1)
  CACHED_MD5=$(md5sum "$BLOCKER_CACHE" | cut -d' ' -f1)
  if [ "$CURRENT_MD5" = "$CACHED_MD5" ]; then
    BLOCKERS_CHANGED=0
    log "Blocker report unchanged since last post. Skipping blocker detail."
  fi
fi

PAYLOAD=$(FEATURE_LIST_PATH="$FEATURE_LIST" BLOCKERS_CHANGED="$BLOCKERS_CHANGED" python3 << 'PYEOF'
import json, os

feature_list_path = os.environ["FEATURE_LIST_PATH"]
blockers_changed = int(os.environ.get("BLOCKERS_CHANGED", "1"))

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

if blockers_changed and blocked:
    lines.append(f"🔴 **{len(blocked)} tasks need human action:**")
    for feat in blocked[:10]:
        fid = feat.get("id", "?")
        proj = feat.get("project", "?")
        blocker_desc = ", ".join(feat.get("blocked_by", []))
        lines.append(f"- `{fid}` ({proj}): {blocker_desc}")
    lines.append("")

lines.append(f"🟢 **{len(available)} tasks available** | 📊 **{len(completed)} completed | {len(features)} total**")

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
    if [ -f "$BLOCKER_REPORT" ]; then
      cp "$BLOCKER_REPORT" "$BLOCKER_CACHE"
      log "Blocker cache updated."
    fi
  else
    log "Discord notification failed (HTTP $HTTP_CODE)"
  fi
fi
