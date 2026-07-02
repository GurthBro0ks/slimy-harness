#!/usr/bin/env bash
# test_resume.sh — idempotent resume behavior of goal_runner.py
#
# Verifies:
#  1. First run writes prompt.md and exits 0
#  2. Second run with no new report does NOT overwrite prompt.md
#  3. events.jsonl has no duplicate goal_started events
#  4. Placing a pass report and re-running drives the goal to status=passed
#  5. RESULT.md exists
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURES="$REPO_ROOT/sequencer/tests/fixtures"
GOAL_RUNNER="$REPO_ROOT/sequencer/goal_runner.py"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_resume.sh ==="

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

# 1. First run
echo
echo "--- step 1: first invocation ---"
python3 "$GOAL_RUNNER" test-feature-001 \
  --dry-run \
  --goals-dir "$TEMP" \
  --feature-list "$FIXTURES/feature-sample.json" >/dev/null 2>&1
RC=$?
if [ "$RC" = "0" ]; then pass "first run exit 0"; else fail "first run rc=$RC"; fi

PROMPT="$TEMP/test-feature-001/attempt-1/prompt.md"
if [ ! -f "$PROMPT" ]; then fail "prompt.md missing after first run"; fi
MD5_1=$(md5sum "$PROMPT" | awk '{print $1}')
pass "first prompt md5=$MD5_1"

# Assert prompt.md STARTS with sanitized 3-line harness context block
if head -3 "$PROMPT" | sed -n '1p' | grep -qx "cat /home/slimy/AGENTS.md" \
   && head -3 "$PROMPT" | sed -n '2p' | grep -qx "bash /home/slimy/slimy-harness/sequencer/startup-context.sh --progress-only" \
   && head -3 "$PROMPT" | sed -n '3p' | grep -qx "source /home/slimy/init.sh"; then
  pass "prompt.md starts with sanitized 3-line harness context block"
else
  fail "prompt.md does NOT start with sanitized 3-line block (got: $(head -3 "$PROMPT" | tr '\n' '|'))"
fi

# 2. Second run, no report
echo
echo "--- step 2: second invocation (no report) ---"
python3 "$GOAL_RUNNER" test-feature-001 \
  --dry-run \
  --goals-dir "$TEMP" \
  --feature-list "$FIXTURES/feature-sample.json" >/dev/null 2>&1
RC=$?
if [ "$RC" = "0" ]; then pass "second run exit 0"; else fail "second run rc=$RC"; fi

MD5_2=$(md5sum "$PROMPT" | awk '{print $1}')
if [ "$MD5_1" = "$MD5_2" ]; then
  pass "prompt.md NOT overwritten (md5 stable)"
else
  fail "prompt.md was overwritten (md5 $MD5_1 -> $MD5_2)"
fi

# 3. events.jsonl has no duplicate goal_started
GS_COUNT=$(grep -c '"event": "goal_started"' "$TEMP/test-feature-001/events.jsonl" || true)
if [ "$GS_COUNT" = "1" ]; then
  pass "events.jsonl has exactly 1 goal_started event"
else
  fail "events.jsonl has $GS_COUNT goal_started events (want 1)"
fi

# 4. Place pass report and re-run
echo
echo "--- step 3: place pass report + re-run ---"
cp "$FIXTURES/report-pass.json" "$TEMP/test-feature-001/attempt-1/session-report.json"
pass "placed pass report"

python3 "$GOAL_RUNNER" test-feature-001 \
  --dry-run \
  --goals-dir "$TEMP" \
  --feature-list "$FIXTURES/feature-sample.json" >/dev/null 2>&1
RC=$?
if [ "$RC" = "0" ]; then pass "third run exit 0"; else fail "third run rc=$RC"; fi

# 5. goal.json status=passed
STATUS=$(python3 -c "import json; print(json.load(open('$TEMP/test-feature-001/goal.json')).get('status',''))")
if [ "$STATUS" = "passed" ]; then pass "goal.json status=passed"; else fail "goal.json status=$STATUS (want passed)"; fi

# 6. RESULT.md exists
if [ -f "$TEMP/test-feature-001/RESULT.md" ]; then
  pass "RESULT.md exists"
else
  fail "RESULT.md missing"
fi

# 7. qa-result.json verdict=pass
if [ -f "$TEMP/test-feature-001/attempt-1/qa-result.json" ]; then
  VERDICT=$(python3 -c "import json; print(json.load(open('$TEMP/test-feature-001/attempt-1/qa-result.json')).get('verdict',''))")
  if [ "$VERDICT" = "pass" ]; then pass "qa-result verdict=pass"; else fail "qa-result verdict=$VERDICT (want pass)"; fi
else
  fail "qa-result.json missing"
fi

# 8. goal_passed event recorded
if grep -q '"event": "goal_passed"' "$TEMP/test-feature-001/events.jsonl"; then
  pass "events.jsonl has goal_passed"
else
  fail "events.jsonl missing goal_passed"
fi

echo
echo "=== results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] && exit 0 || exit 1
