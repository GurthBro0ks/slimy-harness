#!/usr/bin/env bash
set -euo pipefail

DISCORD_WEBHOOK=$(grep -oP 'https://discord[^"'"'"']+' /usr/local/bin/sr-notify 2>/dev/null || grep -oP 'https://discord[^"'"'"']+' /home/slimy/slimy-harness/sequencer/auto-sequence.sh 2>/dev/null || true)
KB_RAW="/home/slimy/slimy-kb/raw/sessions"
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
LOGFILE="${KB_RAW}/pm-${TIMESTAMP}.md"
HOSTNAME=$(hostname)
DATE=$(date +%Y-%m-%d)

mkdir -p "$KB_RAW"

SUMMARY=""
if [[ $# -gt 0 ]]; then
    SUMMARY="$*"
elif [[ ! -t 0 ]]; then
    SUMMARY=$(cat)
else
    SUMMARY="PM session completed"
fi

cat > "$LOGFILE" << HEREDOC
# PM Session Log — ${DATE}

**Host:** ${HOSTNAME}
**Time:** ${TIMESTAMP}

## Summary
${SUMMARY}
HEREDOC

echo "[log-pm-session] Written: ${LOGFILE}"

if [[ -d /home/slimy/slimy-kb/.git ]]; then
    cd /home/slimy/slimy-kb
    git add "$LOGFILE" 2>/dev/null || true
    git commit -m "kb: pm session log ${DATE}" 2>/dev/null || true
    echo "[log-pm-session] Committed to slimy-kb"
fi

if [[ -n "$DISCORD_WEBHOOK" ]]; then
    SHORT_SUMMARY=$(echo "$SUMMARY" | head -1 | cut -c1-200)
    curl -sf -H "Content-Type: application/json" \
        -d "{\"content\": \"PM Session (${HOSTNAME}): ${SHORT_SUMMARY}\"}" \
        "$DISCORD_WEBHOOK" 2>/dev/null && \
        echo "[log-pm-session] Posted to Discord" || \
        echo "[log-pm-session] Discord post failed (non-fatal)"
fi
