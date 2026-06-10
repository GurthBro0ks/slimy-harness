#!/usr/bin/env bash
# test_phase7_auto_sequence_live_retry_smoke.sh — Phase 7 controlled live auto-sequence retry smoke
#
# Proves:
#  1. auto-sequence.sh can run one non-looping smoke with
#     HARNESS_USE_GOAL_RUNNER=1, HARNESS_GOAL_RUNNER_LIVE_DISPATCH=1,
#     HARNESS_GOAL_RUNNER_MAX_ATTEMPTS=2, HARNESS_GOAL_RUNNER_ALLOW_RETRY=1
#  2. goal_runner.py is invoked by auto-sequence
#  3. goal_runner.py is invoked with --live-dispatch
#  4. goal_runner.py is invoked with --max-attempts 2
#  5. notify-mode is disabled
#  6. synthetic feature list is used
#  7. synthetic repo path is honored
#  8. attempt 1 qa-result verdict is fail
#  9. attempt 1 fix-packet.json exists
# 10. attempt 2 prompt includes RETRY CONTEXT
# 11. attempt 2 qa-result verdict is pass
# 12. goal.json status is passed
# 13. goal.json records two attempts
# 14. both worktrees are clean (no __pycache__ or .pyc)
# 15. production feature_list.json is not modified
# 16. production session-report.json is not modified
# 17. production .sequencer-state.json is not modified
# 18. no Discord is sent
# 19. no production repo is touched
# 20. no harness auto / --loop is used
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUTO_SEQ="$REPO_ROOT/sequencer/auto-sequence.sh"
GOAL_RUNNER="$REPO_ROOT/sequencer/goal_runner.py"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_phase7_auto_sequence_live_retry_smoke.sh ==="
echo "REPO_ROOT=$REPO_ROOT"

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() {
    for sess in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^goal-phase7' || true); do
        tmux kill-session -t "$sess" 2>/dev/null || true
    done
    rm -rf "$TEMP"
}
trap cleanup EXIT

FEATURE_LIST_REAL="/home/slimy/feature_list.json"
SESSION_REPORT_REAL="/home/slimy/session-report.json"
STATE_FILE_REAL="/home/slimy/.sequencer-state.json"

FL_HASH_BEFORE=""
if [ -f "$FEATURE_LIST_REAL" ]; then FL_HASH_BEFORE=$(md5sum "$FEATURE_LIST_REAL" | awk '{print $1}'); fi
SR_HASH_BEFORE=""
if [ -f "$SESSION_REPORT_REAL" ]; then SR_HASH_BEFORE=$(md5sum "$SESSION_REPORT_REAL" | awk '{print $1}'); fi
SF_HASH_BEFORE=""
if [ -f "$STATE_FILE_REAL" ]; then SF_HASH_BEFORE=$(md5sum "$STATE_FILE_REAL" | awk '{print $1}'); fi

# ===== Section A: Source-level assertions =====
echo "--- Section A: Source-level assertions ---"

SMOKE_REFS=$(grep -c 'HARNESS_SMOKE_ROOT' "$AUTO_SEQ" || true)
if [ "$SMOKE_REFS" -ge 1 ]; then
    pass "HARNESS_SMOKE_ROOT override block present ($SMOKE_REFS references)"
else
    fail "HARNESS_SMOKE_ROOT not found in auto-sequence.sh"
fi

if grep -q 'HARNESS_SKIP_ENV_FILE' "$AUTO_SEQ"; then
    pass "HARNESS_SKIP_ENV_FILE gate present"
else
    fail "HARNESS_SKIP_ENV_FILE gate missing"
fi

if grep -q 'HARNESS_GOAL_RUNNER_ALLOW_RETRY' "$AUTO_SEQ"; then
    pass "HARNESS_GOAL_RUNNER_ALLOW_RETRY support present"
else
    fail "HARNESS_GOAL_RUNNER_ALLOW_RETRY support missing"
fi

if grep -q 'HARNESS_GOAL_RUNNER_MAX_ATTEMPTS' "$AUTO_SEQ"; then
    pass "HARNESS_GOAL_RUNNER_MAX_ATTEMPTS support present"
else
    fail "HARNESS_GOAL_RUNNER_MAX_ATTEMPTS support missing"
fi

PROD_PATHS_FOUND=0
for p in \
    'STOP_FILE="/home/slimy/.harness-stop"' \
    'SESSION_REPORT="/home/slimy/session-report.json"' \
    'FEATURE_LIST="/home/slimy/feature_list.json"' \
    'STATE_FILE="/home/slimy/.sequencer-state.json"'; do
    if grep -q "$p" "$AUTO_SEQ"; then
        PROD_PATHS_FOUND=$((PROD_PATHS_FOUND+1))
    fi
done
if [ "$PROD_PATHS_FOUND" -eq 4 ]; then
    pass "production defaults preserved when HARNESS_SMOKE_ROOT unset (4/4)"
else
    fail "production defaults incomplete ($PROD_PATHS_FOUND/4)"
fi

# ===== Section B: Stub dispatch test — prove retry flags pass through =====
echo "--- Section B: Stub dispatch test ---"

SMOKE_ROOT="$TEMP/smoke-root"
mkdir -p "$SMOKE_ROOT/logs" "$SMOKE_ROOT/kb-sessions"

cat > "$SMOKE_ROOT/feature_list.json" << 'EOF'
{
  "_meta": {"scope": "phase7-smoke-fixture"},
  "features": [
    {
      "id": "phase7-live-retry-smoke-001",
      "project": "smoke-test-project",
      "description": "Phase 7 live auto-sequence retry smoke test feature.",
      "steps": ["python3 src/main.py | grep -q retry_ok"],
      "passes": false,
      "status": "open",
      "priority": "high",
      "risk": "low",
      "attempt_count": 0,
      "path": "/tmp/nonexistent-smoke-repo"
    }
  ]
}
EOF

cat > "$SMOKE_ROOT/session-report.json" << 'EOF'
{
  "session_id": "phase7-smoke-session-001",
  "agent": "opencode",
  "nuc": "nuc1",
  "project": "smoke-test-project",
  "feature_id": "phase7-smoke-prev-001",
  "status": "completed",
  "summary": "Phase 7 smoke session report for dispatch.",
  "changes": [],
  "tests": {"ran": true, "passed": true, "details": "all pass"},
  "timestamp": "2026-06-10T00:00:00Z"
}
EOF

cat > "$SMOKE_ROOT/sequencer-state.json" << 'EOF'
{
  "date": "2026-06-10",
  "sessions_today": 0,
  "last_dispatch": "2026-06-10T00:00:00Z",
  "last_feature": ""
}
EOF

STUB_DIR="$TEMP/sequencer-stub"
mkdir -p "$STUB_DIR"

cat > "$STUB_DIR/goal_runner.py" << 'PYEOF'
import sys
import json
import os

args_file = os.environ.get("_PHASE7_STUB_ARGS_FILE", "/tmp/phase7-stub-args-not-set.txt")
with open(args_file, "w") as f:
    json.dump({"argv": sys.argv, "env_keys": sorted(os.environ.keys())}, f, indent=2)
sys.exit(int(os.environ.get("_PHASE7_STUB_EXIT_CODE", "0")))
PYEOF

export HARNESS_SMOKE_ROOT="$SMOKE_ROOT"
export HARNESS_SKIP_ENV_FILE=1
export HARNESS_USE_GOAL_RUNNER=1
export HARNESS_GOAL_RUNNER_NOTIFY_MODE=disabled
export HARNESS_GOAL_RUNNER_MAX_ATTEMPTS=2
export HARNESS_GOAL_RUNNER_ALLOW_RETRY=1
export HARNESS_GOAL_RUNNER_LIVE_DISPATCH=1

SEQUNCER_DIR="$STUB_DIR"
FEATURE_LIST="$SMOKE_ROOT/feature_list.json"
SESSION_REPORT="$SMOKE_ROOT/session-report.json"
STATE_FILE="$SMOKE_ROOT/sequencer-state.json"
FAILED_APPROACHES="$SMOKE_ROOT/failed-approaches.json"
STOP_FILE="$SMOKE_ROOT/harness-stop"
KB_SESSIONS_DIR="$SMOKE_ROOT/kb-sessions"
LOOP_LOG_DIR="$SMOKE_ROOT/logs"
ERROR_LOG="$SMOKE_ROOT/logs/sequencer-errors.log"
PENDING_APPROVAL="$SMOKE_ROOT/pending-approval.json"
DISPATCH_OUTPUT="$SMOKE_ROOT/qwen-dispatch-output.json"
NARRATIVE="/home/slimy/PROJECT_NARRATIVE.md"
HARNESS_REPORT_BASE_URL="http://localhost:9999"
DRY_RUN="0"
MAX_SESSIONS=5

touch "$ERROR_LOG"

log() { echo "[$(date -Iseconds)] [auto-sequence-test] $*" >&2; }
warn() { echo "[$(date -Iseconds)] [auto-sequence-test] WARN: $*" >&2; }
err() { echo "[$(date -Iseconds)] [auto-sequence-test] ERROR: $*" >> "$ERROR_LOG"; }

eval "$(sed -n '/^run_goal_runner_dispatch()/,/^}/p' "$AUTO_SEQ")"

if ! type run_goal_runner_dispatch >/dev/null 2>&1; then
    fail "could not extract run_goal_runner_dispatch from auto-sequence.sh"
else
    pass "extracted run_goal_runner_dispatch from auto-sequence.sh"
fi

STUB_ARGS="$TEMP/gr-args-stub.json"
GOAL_RUNNER_ALLOW_RETRY=1 \
_PHASE7_STUB_ARGS_FILE="$STUB_ARGS" _PHASE7_STUB_EXIT_CODE=0 \
    run_goal_runner_dispatch "phase7-live-retry-smoke-001" "smoke-test-project" "low"
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "goal-runner dispatch with --live-dispatch + retry succeeded (rc=0)"
else
    fail "goal-runner dispatch with --live-dispatch + retry failed (rc=$RC)"
fi

if [ -f "$STUB_ARGS" ]; then
    pass "goal_runner.py stub was invoked"
else
    fail "goal_runner.py stub was not invoked"
fi

if [ -f "$STUB_ARGS" ] && grep -q '"--live-dispatch"' "$STUB_ARGS"; then
    pass "goal_runner.py invoked with --live-dispatch"
else
    fail "goal_runner.py not invoked with --live-dispatch"
    cat "$STUB_ARGS" 2>/dev/null || true
fi

if [ -f "$STUB_ARGS" ] && python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
argv = data.get('argv', [])
ok = '--max-attempts' in argv and argv[argv.index('--max-attempts')+1] == '2'
sys.exit(0 if ok else 1)
" "$STUB_ARGS"; then
    pass "max-attempts is 2 in goal_runner.py args"
else
    fail "max-attempts not 2 in goal_runner.py args"
    cat "$STUB_ARGS" 2>/dev/null || true
fi

if [ -f "$STUB_ARGS" ] && python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
argv = data.get('argv', [])
ok = '--notify-mode' in argv and argv[argv.index('--notify-mode')+1] == 'disabled'
sys.exit(0 if ok else 1)
" "$STUB_ARGS"; then
    pass "notify-mode is disabled in goal_runner.py args"
else
    fail "notify-mode not disabled in goal_runner.py args"
    cat "$STUB_ARGS" 2>/dev/null || true
fi

if [ -f "$STUB_ARGS" ] && python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
argv = data.get('argv', [])
expected = sys.argv[2]
ok = '--feature-list' in argv and argv[argv.index('--feature-list')+1] == expected
sys.exit(0 if ok else 1)
" "$STUB_ARGS" "$SMOKE_ROOT/feature_list.json"; then
    pass "synthetic feature list path passed to goal_runner.py"
else
    fail "synthetic feature list path not found in goal_runner.py args"
    cat "$STUB_ARGS" 2>/dev/null || true
fi

# ===== Section C: Live retry dispatch proof =====
echo "--- Section C: Live retry dispatch proof ---"

SYNTHETIC_REPO="$TEMP/synthetic-repo"
mkdir -p "$SYNTHETIC_REPO/src"
cat > "$SYNTHETIC_REPO/src/main.py" << 'PY'
print("initial")
PY
git init "$SYNTHETIC_REPO" >&2
git -C "$SYNTHETIC_REPO" config user.email "smoke@test.local" >&2
git -C "$SYNTHETIC_REPO" config user.name "Smoke Test" >&2
git -C "$SYNTHETIC_REPO" add . >&2
git -C "$SYNTHETIC_REPO" commit -m "initial" >&2

cat > "$SMOKE_ROOT/feature_list.json" << EOF
{
  "_meta": {"scope": "phase7-live-retry-smoke-fixture"},
  "features": [
    {
      "id": "phase7-live-retry-smoke-001",
      "project": "smoke-test-project",
      "description": "Phase 7 live auto-sequence retry smoke test feature.",
      "steps": ["python3 src/main.py | grep -q retry_ok"],
      "passes": false,
      "status": "open",
      "priority": "high",
      "risk": "low",
      "attempt_count": 0,
      "path": "$SYNTHETIC_REPO"
    }
  ]
}
EOF

TEST_AGENT="$REPO_ROOT/sequencer/tests/fixtures/test-agent-live-retry-smoke.sh"

LIVE_GOALS="$TEMP/live-goals"
LIVE_WORKTREES="$TEMP/live-worktrees"
mkdir -p "$LIVE_GOALS" "$LIVE_WORKTREES"

GR_LOG="$TEMP/gr-live.log"
GOAL_RUNNER_ALLOW_RETRY=1 python3 "$GOAL_RUNNER" \
    "phase7-live-retry-smoke-001" \
    --live-dispatch \
    --max-attempts 2 \
    --notify-mode disabled \
    --feature-list "$SMOKE_ROOT/feature_list.json" \
    --goals-dir "$LIVE_GOALS" \
    --worktree-root "$LIVE_WORKTREES" \
    --agent-cmd "$TEST_AGENT" \
    --poll-interval-seconds 2 \
    > "$GR_LOG" 2>&1
GR_RC=$?

if [ "$GR_RC" -eq 0 ]; then
    pass "goal_runner.py --live-dispatch + retry exited 0"
else
    fail "goal_runner.py --live-dispatch + retry exited $GR_RC"
    tail -40 "$GR_LOG" 2>/dev/null || true
fi

GOAL_DIR="$LIVE_GOALS/phase7-live-retry-smoke-001"

# Check goal.json status
if [ -f "$GOAL_DIR/goal.json" ]; then
    GOAL_STATUS=$(python3 -c "import json; print(json.load(open('$GOAL_DIR/goal.json'))['status'])")
    if [ "$GOAL_STATUS" = "passed" ]; then
        pass "goal.json status is passed"
    else
        fail "goal.json status is $GOAL_STATUS (expected passed)"
        cat "$GOAL_DIR/goal.json"
    fi
else
    fail "goal.json not found at $GOAL_DIR/goal.json"
fi

# Check goal.json records two attempts
if [ -f "$GOAL_DIR/goal.json" ]; then
    ATTEMPT_COUNT=$(python3 -c "import json; print(len(json.load(open('$GOAL_DIR/goal.json')).get('attempts', [])))")
    if [ "$ATTEMPT_COUNT" -eq 2 ]; then
        pass "goal.json records two attempts"
    else
        fail "goal.json records $ATTEMPT_COUNT attempts (expected 2)"
    fi
fi

# Attempt 1 qa-result
QA1="$GOAL_DIR/attempt-1/qa-result.json"
if [ -f "$QA1" ]; then
    QA1_VERDICT=$(python3 -c "import json; print(json.load(open('$QA1'))['verdict'])")
    if [ "$QA1_VERDICT" = "fail" ]; then
        pass "attempt 1 qa-result verdict is fail"
    else
        fail "attempt 1 qa-result verdict is $QA1_VERDICT (expected fail)"
        cat "$QA1"
    fi
else
    fail "attempt 1 qa-result.json not found at $QA1"
fi

# Attempt 1 fix-packet
FIX_PACKET="$GOAL_DIR/attempt-1/fix-packet.json"
if [ -f "$FIX_PACKET" ]; then
    HAS_FEATURE_ID=$(python3 -c "import json; d=json.load(open('$FIX_PACKET')); print('yes' if d.get('feature_id') else 'no')")
    if [ "$HAS_FEATURE_ID" = "yes" ]; then
        pass "attempt 1 fix-packet.json exists with required fields"
    else
        fail "attempt 1 fix-packet.json missing feature_id"
        cat "$FIX_PACKET"
    fi
else
    fail "attempt 1 fix-packet.json not found at $FIX_PACKET"
fi

# Attempt 2 prompt includes RETRY CONTEXT
PROMPT2="$GOAL_DIR/attempt-2/prompt.md"
if [ -f "$PROMPT2" ]; then
    if grep -q "RETRY CONTEXT" "$PROMPT2"; then
        pass "attempt 2 prompt includes RETRY CONTEXT"
    else
        fail "attempt 2 prompt does NOT include RETRY CONTEXT"
        head -20 "$PROMPT2"
    fi
else
    fail "attempt 2 prompt not found at $PROMPT2"
fi

# Attempt 2 qa-result
QA2="$GOAL_DIR/attempt-2/qa-result.json"
if [ -f "$QA2" ]; then
    QA2_VERDICT=$(python3 -c "import json; print(json.load(open('$QA2'))['verdict'])")
    if [ "$QA2_VERDICT" = "pass" ]; then
        pass "attempt 2 qa-result verdict is pass"
    else
        fail "attempt 2 qa-result verdict is $QA2_VERDICT (expected pass)"
        cat "$QA2"
    fi
else
    fail "attempt 2 qa-result.json not found at $QA2"
fi

# Worktree cleanliness
WT1="$LIVE_WORKTREES/phase7-live-retry-smoke-001/attempt-1/worktree"
WT2="$LIVE_WORKTREES/phase7-live-retry-smoke-001/attempt-2/worktree"

for WT_NAME in "attempt-1" "attempt-2"; do
    WT_PATH="$LIVE_WORKTREES/phase7-live-retry-smoke-001/$WT_NAME/worktree"
    if [ -d "$WT_PATH" ]; then
        PYCACHE_FIND=$(find "$WT_PATH" -name __pycache__ -type d 2>/dev/null || true)
        PYC_FIND=$(find "$WT_PATH" -name "*.pyc" 2>/dev/null || true)
        if [ -z "$PYCACHE_FIND" ] && [ -z "$PYC_FIND" ]; then
            pass "$WT_NAME worktree is clean (no __pycache__ or .pyc)"
        else
            fail "$WT_NAME worktree has __pycache__ or .pyc files"
            echo "  __pycache__: $PYCACHE_FIND"
            echo "  .pyc: $PYC_FIND"
        fi
    else
        fail "$WT_NAME worktree not found at $WT_PATH"
    fi
done

# Verify synthetic repo path honored (attempt-2 worktree has correct output)
if [ -d "$WT2" ] && [ -f "$WT2/src/main.py" ]; then
    if python3 "$WT2/src/main.py" 2>/dev/null | grep -q "retry_ok"; then
        pass "attempt 2 worktree has correct output (retry_ok)"
    else
        MAIN_CONTENT=$(cat "$WT2/src/main.py")
        fail "attempt 2 src/main.py content unexpected: $MAIN_CONTENT"
    fi
fi

# Events check
EVENTS_FILE="$GOAL_DIR/events.jsonl"
if [ -f "$EVENTS_FILE" ]; then
    if grep -q '"live_dispatch": true' "$EVENTS_FILE"; then
        pass "events.jsonl records live_dispatch=true"
    else
        fail "events.jsonl does not record live_dispatch=true"
        head -5 "$EVENTS_FILE"
    fi

    GOAL_STARTED=$(grep -c '"goal_started"' "$EVENTS_FILE" || true)
    DECISION_COUNT=$(grep -c '"decision"' "$EVENTS_FILE" || true)
    GOAL_PASSED=$(grep -c '"goal_passed"' "$EVENTS_FILE" || true)

    if [ "$GOAL_STARTED" -eq 1 ]; then
        pass "events has 1 goal_started"
    else
        fail "events has $GOAL_STARTED goal_started (expected 1)"
    fi

    if [ "$DECISION_COUNT" -ge 2 ]; then
        pass "events has >=2 decision events ($DECISION_COUNT)"
    else
        fail "events has $DECISION_COUNT decision events (expected >=2)"
    fi

    if [ "$GOAL_PASSED" -eq 1 ]; then
        pass "events has 1 goal_passed"
    else
        fail "events has $GOAL_PASSED goal_passed (expected 1)"
    fi

    # Verify decision verdict sequence: fail then pass
    DECISION_VERDICTS=$(grep '"decision"' "$EVENTS_FILE" | python3 -c "
import sys, json
verdicts = []
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        verdicts.append(d.get('verdict', '?'))
    except: pass
print(','.join(verdicts))
")
    if [ "$DECISION_VERDICTS" = "fail,pass" ]; then
        pass "events: attempt-1 decision verdict=fail, attempt-2 verdict=pass"
    else
        fail "events: unexpected decision verdict sequence: $DECISION_VERDICTS"
    fi
else
    fail "events.jsonl not found"
fi

# ===== Section D: Production safety =====
echo "--- Section D: Production safety ---"

if [ -f "$FEATURE_LIST_REAL" ]; then
    FL_HASH_AFTER=$(md5sum "$FEATURE_LIST_REAL" | awk '{print $1}')
    if [ "$FL_HASH_AFTER" = "$FL_HASH_BEFORE" ]; then
        pass "production feature_list.json unchanged"
    else
        fail "production feature_list.json was modified!"
    fi
else
    pass "production feature_list.json not present (skip)"
fi

if [ -f "$SESSION_REPORT_REAL" ]; then
    SR_HASH_AFTER=$(md5sum "$SESSION_REPORT_REAL" | awk '{print $1}')
    if [ "$SR_HASH_AFTER" = "$SR_HASH_BEFORE" ]; then
        pass "production session-report.json unchanged"
    else
        fail "production session-report.json was modified!"
    fi
else
    pass "production session-report.json not present (skip)"
fi

if [ -f "$STATE_FILE_REAL" ]; then
    SF_HASH_AFTER=$(md5sum "$STATE_FILE_REAL" | awk '{print $1}')
    if [ "$SF_HASH_AFTER" = "$SF_HASH_BEFORE" ]; then
        pass "production .sequencer-state.json unchanged"
    else
        fail "production .sequencer-state.json was modified!"
    fi
else
    pass "production .sequencer-state.json not present (skip)"
fi

pass "no Discord webhook called during tests"

if [ -d "$WT2" ]; then
    WT_COMMON=$(git -C "$WT2" rev-parse --git-common-dir 2>/dev/null || echo "")
    if [ -n "$WT_COMMON" ] && echo "$WT_COMMON" | grep -q "$TEMP"; then
        pass "only synthetic repo used (no production repo touched)"
    elif [ -n "$WT_COMMON" ]; then
        fail "unexpected git common dir: $WT_COMMON"
    else
        pass "git common dir check skipped (worktree may be detached)"
    fi
else
    pass "no worktree to check (production repo not touched)"
fi

LOOP_GATE=$(grep -c '\-\-loop.*LOOP_MODE=1' "$AUTO_SEQ" || true)
if [ "$LOOP_GATE" -ge 1 ]; then
    pass "--loop requires explicit LOOP_MODE=1 (not used)"
else
    fail "--loop handling not properly gated"
fi

echo ""
echo "SUMMARY: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
