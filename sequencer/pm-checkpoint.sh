#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="/home/slimy/.pm-state.json"
TMP_FILE="${STATE_FILE}.tmp.$$"

MODE="${1:-null}"
FEATURE_ID="${2:-null}"
REPO="${3:-null}"
SUMMARY="${4:-}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$TMP_FILE" <<CHECKPOINT
{
  "mode": "$MODE",
  "active_feature_id": "$FEATURE_ID",
  "active_repo": "$REPO",
  "summary_of_work": "$SUMMARY",
  "decisions_made": [],
  "timestamp": "$TIMESTAMP"
}
CHECKPOINT

mv "$TMP_FILE" "$STATE_FILE"
