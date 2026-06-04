#!/usr/bin/env bash
set -uo pipefail

SESSIONS_DIR="/home/slimy/slimy-kb/raw/sessions"
REMOTE_HOST="nuc2"
REMOTE_DIR="/home/slimy/slimy-kb/raw/sessions"

log()  { echo "[sync-session-reports] $*"; }
warn() { echo "[sync-session-reports] WARN: $*" >&2; }

if [ ! -d "$SESSIONS_DIR" ]; then
    warn "Local sessions dir not found: $SESSIONS_DIR"
    exit 1
fi

LOCAL_COUNT=$(find "$SESSIONS_DIR" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l)
if [ "$LOCAL_COUNT" -eq 0 ]; then
    log "No session reports to sync."
    exit 0
fi

ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_DIR'" 2>/dev/null
if [ $? -ne 0 ]; then
    warn "Cannot reach $REMOTE_HOST via ssh. Sync aborted."
    exit 1
fi

RSYNC_OUT=$(rsync -a --include='*.json' --exclude='*' --stats "$SESSIONS_DIR/" "$REMOTE_HOST:$REMOTE_DIR/" 2>&1)
RC=$?

if [ $RC -ne 0 ]; then
    warn "rsync failed with exit code $RC"
    echo "$RSYNC_OUT"
    exit 1
fi

SYNCED=$(echo "$RSYNC_OUT" | grep -oP 'Number of regular files transferred: \K\d+' || echo "0")
REMOTE_TOTAL=$(ssh "$REMOTE_HOST" "find '$REMOTE_DIR' -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l" 2>/dev/null || echo "?")

log "Synced $SYNCED files. Local: $LOCAL_COUNT reports. Remote ($REMOTE_HOST): $REMOTE_TOTAL reports."
