#!/bin/bash
# test-agent-live-retry-smoke.sh — deterministic test agent for Phase 7 live retry smoke
#
# Usage: <this-script> run --dir <worktree> --dangerously-skip-permissions <prompt>
#
# Behavior:
#   attempt-1: leave src/main.py printing "wrong", write failing session report
#   attempt-2: fix src/main.py to print "retry_ok", write passing session report
#
# Detects attempt number from the worktree path (attempt-N directory).
# Extracts session report path from the prompt preamble.
#
# This script is for TESTING ONLY. Do not use as a production agent.
set -euo pipefail

WORKDIR=""
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        run) shift ;;
        --dir) WORKDIR="$2"; shift 2 ;;
        --dangerously-skip-permissions) shift; PROMPT="$*"; break ;;
        *) shift ;;
    esac
done

if [ -z "$WORKDIR" ]; then
    echo "[test-agent-live-retry-smoke] FATAL: --dir not provided" >&2
    exit 1
fi

REPORT_PATH=""
if [ -n "$PROMPT" ]; then
    REPORT_PATH=$(printf '%s\n' "$PROMPT" | grep 'session report to:' | head -1 | sed 's/.*session report to: *//')
fi

if [ -z "$REPORT_PATH" ]; then
    echo "[test-agent-live-retry-smoke] FATAL: could not extract session report path from prompt" >&2
    exit 1
fi

mkdir -p "$(dirname "$REPORT_PATH")"

ATTEMPT_NUM=$(printf '%s' "$WORKDIR" | grep -oP 'attempt-\K[0-9]+' || echo "1")

if [ "$ATTEMPT_NUM" = "1" ]; then
    mkdir -p "$WORKDIR/src"
    cat > "$WORKDIR/src/main.py" << 'PY'
print("wrong")
PY
    cat > "$REPORT_PATH" << REPORT
{
    "session_id": "2026-06-10T00:00:00Z",
    "agent": "test-agent-live-retry-smoke",
    "nuc": "nuc1",
    "project": "smoke-test-project",
    "feature_id": "phase7-live-retry-smoke-001",
    "prompt_type": "A",
    "status": "completed",
    "summary": "Attempt 1: intentionally left src/main.py printing wrong",
    "changes": ["src/main.py"],
    "tests": {"ran": true, "passed": false, "count": 1, "failed_count": 1},
    "blockers": [],
    "recommendation": {"next_feature_id": null, "reasoning": "Test retry mechanic"}
}
REPORT
    echo "[test-agent-live-retry-smoke] attempt 1: wrote wrong src/main.py and failing report to $REPORT_PATH" >&2
else
    mkdir -p "$WORKDIR/src"
    cat > "$WORKDIR/src/main.py" << 'PY'
print("retry_ok")
PY
    cat > "$REPORT_PATH" << REPORT
{
    "session_id": "2026-06-10T00:00:01Z",
    "agent": "test-agent-live-retry-smoke",
    "nuc": "nuc1",
    "project": "smoke-test-project",
    "feature_id": "phase7-live-retry-smoke-001",
    "prompt_type": "A",
    "status": "completed",
    "summary": "Attempt 2: fixed src/main.py to print retry_ok",
    "changes": ["src/main.py"],
    "tests": {"ran": true, "passed": true, "count": 1, "failed_count": 0},
    "blockers": [],
    "recommendation": {"next_feature_id": null, "reasoning": "Retry succeeded"}
}
REPORT
    echo "[test-agent-live-retry-smoke] attempt $ATTEMPT_NUM: fixed file, wrote passing report to $REPORT_PATH" >&2
fi

exit 0
