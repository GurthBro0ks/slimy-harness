#!/bin/bash
# test-agent-live-smoke.sh — deterministic test agent for Phase 6 live smoke
#
# Usage: <this-script> run --dir <worktree> --dangerously-skip-permissions <prompt>
#
# Behavior:
#   - Creates src/main.py in the worktree with print("smoke_ok")
#   - Writes a passing session-report.json to the path extracted from the prompt
#   - Exits 0
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
    echo "[test-agent-live-smoke] FATAL: --dir not provided" >&2
    exit 1
fi

REPORT_PATH=""
if [ -n "$PROMPT" ]; then
    REPORT_PATH=$(printf '%s\n' "$PROMPT" | grep 'session report to:' | head -1 | sed 's/.*session report to: *//')
fi

if [ -z "$REPORT_PATH" ]; then
    echo "[test-agent-live-smoke] FATAL: could not extract session report path from prompt" >&2
    exit 1
fi

mkdir -p "$(dirname "$REPORT_PATH")"

mkdir -p "$WORKDIR/src"
cat > "$WORKDIR/src/main.py" << 'PY'
print("smoke_ok")
PY

cat > "$REPORT_PATH" << 'REPORT'
{
    "session_id": "2026-06-10T00:00:00Z",
    "agent": "test-agent-live-smoke",
    "nuc": "nuc1",
    "project": "smoke-test-project",
    "feature_id": "phase6-live-smoke-001",
    "prompt_type": "A",
    "status": "completed",
    "summary": "Phase 6 live smoke test: wrote src/main.py with correct output",
    "changes": ["src/main.py"],
    "tests": {"ran": true, "passed": true, "count": 1, "failed_count": 0},
    "blockers": [],
    "recommendation": {"next_feature_id": null, "reasoning": "Smoke test passed"}
}
REPORT

echo "[test-agent-live-smoke] wrote src/main.py and session report to $REPORT_PATH" >&2
exit 0
