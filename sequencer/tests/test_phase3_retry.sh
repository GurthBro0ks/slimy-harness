#!/usr/bin/env bash
# test_phase3_retry.sh — Phase 3 controlled live retry validation
#
# Proves:
#   1. max_attempts=2 with GOAL_RUNNER_ALLOW_RETRY=1 is allowed
#   2. attempt-1 qa-result verdict=fail
#   3. attempt-1 fix-packet.json exists
#   4. attempt-2 prompt contains RETRY CONTEXT
#   5. attempt-2 prompt starts with exact 3-line block
#   6. goal.json records two attempts
#   7. final status is passed (deterministic fixture: attempt-2 fixes the file)
#   8. no __pycache__ or .pyc files appear inside either worktree
#   9. events.jsonl shows attempt 1 fail, fix-packet/retry, attempt 2 result
#
# Uses a deterministic test agent script (test-agent-retry.sh) that intentionally
# fails attempt 1 and fixes attempt 2. No model variability.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GOAL_RUNNER="$REPO_ROOT/sequencer/goal_runner.py"
TEST_AGENT="$REPO_ROOT/sequencer/tests/fixtures/test-agent-retry.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_phase3_retry.sh ==="
echo "REPO_ROOT=$REPO_ROOT"

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

# --- Setup: create synthetic repo with a file that prints "wrong" ---
SYN_REPO="$TEMP/syn-repo"
mkdir -p "$SYN_REPO/src"
git -C "$SYN_REPO" init -q -b main
git -C "$SYN_REPO" config user.email "t@t"
git -C "$SYN_REPO" config user.name "t"
cat > "$SYN_REPO/src/main.py" << 'PY'
print("wrong")
PY
git -C "$SYN_REPO" add src/main.py
git -C "$SYN_REPO" commit -q -m "initial: prints wrong"
pass "created synthetic repo at $SYN_REPO"

# Truth gate: python3 src/main.py must contain "correct"
TRUTH_GATE="python3 src/main.py | grep -q correct"

# --- Setup: create synthetic feature list ---
SYN_FL="$TEMP/feature-list.json"
FID="phase3-retry-test-001"
cat > "$SYN_FL" << EOF
{
  "_meta": {"scope": "phase3-retry-test"},
  "features": [
    {
      "id": "$FID",
      "project": "phase3-test-repo",
      "description": "Fix src/main.py to print correct instead of wrong.",
      "steps": ["$TRUTH_GATE"],
      "passes": false,
      "status": "open",
      "priority": "medium",
      "risk": "low",
      "path": "$SYN_REPO",
      "blocked_by": []
    }
  ]
}
EOF
pass "wrote synthetic feature list"

GOALS_DIR="$TEMP/goals"
WT_ROOT="$TEMP/worktrees"

# --- Test 1: max_attempts=2 with GOAL_RUNNER_ALLOW_RETRY=1 is allowed ---
echo
echo "--- check 1: max_attempts=2 with GOAL_RUNNER_ALLOW_RETRY=1 allowed ---"
GOAL_RUNNER_ALLOW_RETRY=1 python3 "$GOAL_RUNNER" "$FID" \
  --live-dispatch \
  --max-attempts 2 \
  --notify-mode disabled \
  --worktree-root "$WT_ROOT" \
  --goals-dir "$GOALS_DIR" \
  --feature-list "$SYN_FL" \
  --agent-cmd "$TEST_AGENT" \
  --tmux-prefix "p3-test" \
  --wall-clock-minutes 4 \
  --poll-interval-seconds 2 \
  2>"$TEMP/run-stderr.log"
RC=$?
echo "  goal_runner exit code: $RC"

if [ "$RC" = "0" ]; then
  pass "goal_runner exited 0 (full retry cycle completed)"
else
  fail "goal_runner exited $RC"
  echo "    [debug] stderr:"
  sed 's/^/      /' "$TEMP/run-stderr.log" | head -30
fi

# --- Test 2: attempt-1 qa-result verdict=fail ---
echo
echo "--- check 2: attempt-1 qa-result verdict=fail ---"
if [ -f "$GOALS_DIR/$FID/attempt-1/qa-result.json" ]; then
  V1=$(python3 -c "import json; print(json.load(open('$GOALS_DIR/$FID/attempt-1/qa-result.json')).get('verdict',''))")
  if [ "$V1" = "fail" ]; then
    pass "attempt-1 qa-result verdict=fail"
  else
    fail "attempt-1 qa-result verdict=$V1 (want fail)"
  fi
else
  fail "attempt-1 qa-result.json missing"
fi

# --- Test 3: attempt-1 fix-packet.json exists ---
echo
echo "--- check 3: attempt-1 fix-packet.json exists ---"
if [ -f "$GOALS_DIR/$FID/attempt-1/fix-packet.json" ]; then
  python3 -c "
import json
fp = json.load(open('$GOALS_DIR/$FID/attempt-1/fix-packet.json'))
required = ['feature_id', 'attempt_completed', 'failing_commands', 'qa_fix_brief']
missing = [k for k in required if k not in fp]
if missing:
    print(f'FAIL: missing fields: {missing}')
else:
    print(f'OK: fix-packet has all required fields (attempt_completed={fp.get(\"attempt_completed\")})')
"
  FP_OK=$?
  if [ "$FP_OK" = "0" ]; then pass "attempt-1 fix-packet.json exists with required fields"; else fail "fix-packet check failed"; fi
else
  fail "attempt-1 fix-packet.json missing"
fi

# --- Test 4: attempt-2 prompt contains RETRY CONTEXT ---
echo
echo "--- check 4: attempt-2 prompt contains RETRY CONTEXT ---"
PROMPT2="$GOALS_DIR/$FID/attempt-2/prompt.md"
if [ -f "$PROMPT2" ]; then
  if grep -q "RETRY CONTEXT" "$PROMPT2"; then
    pass "attempt-2 prompt contains RETRY CONTEXT"
  else
    fail "attempt-2 prompt missing RETRY CONTEXT"
  fi
else
  fail "attempt-2 prompt.md missing"
fi

# --- Test 5: attempt-2 prompt starts with exact 3-line block ---
echo
echo "--- check 5: attempt-2 prompt starts with exact 3-line block ---"
if [ -f "$PROMPT2" ]; then
  LINE1=$(sed -n '1p' "$PROMPT2")
  LINE2=$(sed -n '2p' "$PROMPT2")
  LINE3=$(sed -n '3p' "$PROMPT2")
  if [ "$LINE1" = "cat /home/slimy/AGENTS.md" ] \
     && [ "$LINE2" = "cat /home/slimy/claude-progress.md" ] \
     && [ "$LINE3" = "source /home/slimy/init.sh" ]; then
    pass "attempt-2 prompt starts with exact 3-line block"
  else
    fail "attempt-2 prompt first 3 lines: '$LINE1' / '$LINE2' / '$LINE3'"
  fi
else
  fail "attempt-2 prompt.md missing (cannot check 3-line block)"
fi

# --- Test 6: goal.json records two attempts ---
echo
echo "--- check 6: goal.json records two attempts ---"
if [ -f "$GOALS_DIR/$FID/goal.json" ]; then
  ATTEMPT_COUNT=$(python3 -c "
import json
g = json.load(open('$GOALS_DIR/$FID/goal.json'))
attempts = g.get('attempts', [])
print(len(attempts))
")
  if [ "$ATTEMPT_COUNT" = "2" ]; then
    pass "goal.json has 2 attempts recorded"
  else
    fail "goal.json has $ATTEMPT_COUNT attempts (want 2)"
  fi
  FINAL_STATUS=$(python3 -c "import json; print(json.load(open('$GOALS_DIR/$FID/goal.json')).get('status',''))")
  if [ "$FINAL_STATUS" = "passed" ]; then
    pass "goal.json final status=passed"
  else
    fail "goal.json final status=$FINAL_STATUS (want passed)"
  fi
else
  fail "goal.json missing"
fi

# --- Test 7: events.jsonl shows full retry sequence ---
echo
echo "--- check 7: events.jsonl shows retry sequence ---"
EVENTS="$GOALS_DIR/$FID/events.jsonl"
if [ -f "$EVENTS" ]; then
  HAS_GOAL_STARTED=$(grep -c '"event": "goal_started"' "$EVENTS" || true)
  HAS_DECISION=$(grep -c '"event": "decision"' "$EVENTS" || true)
  HAS_GOAL_PASSED=$(grep -c '"event": "goal_passed"' "$EVENTS" || true)
  if [ "$HAS_GOAL_STARTED" = "1" ]; then pass "events has 1 goal_started"; else fail "events has $HAS_GOAL_STARTED goal_started (want 1)"; fi
  if [ "$HAS_DECISION" -ge 2 ]; then pass "events has $HAS_DECISION decision events (>=2)"; else fail "events has $HAS_DECISION decisions (want >=2)"; fi
  if [ "$HAS_GOAL_PASSED" = "1" ]; then pass "events has 1 goal_passed"; else fail "events has $HAS_GOAL_PASSED goal_passed (want 1)"; fi

  # Verify attempt-1 decision has verdict=fail
  A1_VERDICT=$(python3 -c "
import json
with open('$EVENTS') as f:
    for line in f:
        e = json.loads(line)
        if e.get('event') == 'decision' and e.get('attempt') == 1:
            print(e.get('verdict',''))
            break
")
  if [ "$A1_VERDICT" = "fail" ]; then
    pass "events: attempt-1 decision verdict=fail"
  else
    fail "events: attempt-1 decision verdict=$A1_VERDICT (want fail)"
  fi

  # Verify attempt-2 decision has verdict=pass
  A2_VERDICT=$(python3 -c "
import json
with open('$EVENTS') as f:
    for line in f:
        e = json.loads(line)
        if e.get('event') == 'decision' and e.get('attempt') == 2:
            print(e.get('verdict',''))
            break
")
  if [ "$A2_VERDICT" = "pass" ]; then
    pass "events: attempt-2 decision verdict=pass"
  else
    fail "events: attempt-2 decision verdict=$A2_VERDICT (want pass)"
  fi
else
  fail "events.jsonl missing"
fi

# --- Test 8: no __pycache__ or .pyc in worktrees ---
echo
echo "--- check 8: no __pycache__ or .pyc in worktrees ---"
WT1="$WT_ROOT/$FID/attempt-1/worktree"
WT2="$WT_ROOT/$FID/attempt-2/worktree"
DIRTY_WT=0

for wt in "$WT1" "$WT2"; do
  if [ -d "$wt" ]; then
    PYCACHE=$(find "$wt" -type d -name "__pycache__" 2>/dev/null || true)
    PYC=$(find "$wt" -name "*.pyc" 2>/dev/null || true)
    if [ -n "$PYCACHE" ] || [ -n "$PYC" ]; then
      fail "$(basename $(dirname $wt)) worktree has __pycache__ or .pyc files"
      DIRTY_WT=1
    else
      pass "$(basename $(dirname $wt)) worktree is clean (no __pycache__ or .pyc)"
    fi
  else
    fail "worktree $wt does not exist"
  fi
done

echo
echo "=== results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] && exit 0 || exit 1
