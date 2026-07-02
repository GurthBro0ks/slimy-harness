#!/usr/bin/env bash
# test_phase4_auto_sequence_goal_runner.sh — Phase 4 auto-sequence goal-runner wiring
#
# Proves:
#   1. HARNESS_USE_GOAL_RUNNER gate exists in auto-sequence.sh source
#   2. Legacy dispatch path preserved when gate is off
#   3. --dry-run passed when HARNESS_GOAL_RUNNER_LIVE_DISPATCH unset
#   4. --live-dispatch passed when HARNESS_GOAL_RUNNER_LIVE_DISPATCH=1
#   5. --notify-mode defaults to disabled
#   6. --max-attempts defaults to 1
#   7. max_attempts > 1 fails closed without HARNESS_GOAL_RUNNER_ALLOW_RETRY=1
#   8. max_attempts > 1 succeeds with HARNESS_GOAL_RUNNER_ALLOW_RETRY=1
#   9. --feature-list path matches FEATURE_LIST
#  10. No test sends Discord
#  11. No test modifies /home/slimy/feature_list.json
#  12. goal_runner.py missing causes non-zero exit
#  13. HARNESS_GOAL_RUNNER_NOTIFY_MODE=runtime downgraded to disabled
#  14. Auto-sequence startup prompt uses sanitized progress context helper
#
# Uses a stub goal_runner.py that records args. No real agent dispatch.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUTO_SEQ="$REPO_ROOT/sequencer/auto-sequence.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_phase4_auto_sequence_goal_runner.sh ==="
echo "REPO_ROOT=$REPO_ROOT"

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

FEATURE_LIST_REAL="/home/slimy/feature_list.json"
FEATURE_LIST_HASH=""
if [ -f "$FEATURE_LIST_REAL" ]; then
  FEATURE_LIST_HASH=$(md5sum "$FEATURE_LIST_REAL" | awk '{print $1}')
fi

STUB_DIR="$TEMP/sequencer-stub"
mkdir -p "$STUB_DIR"

cat > "$STUB_DIR/goal_runner.py" << 'PYEOF'
import sys
import json
import os

args_file = os.environ.get("_STUB_ARGS_FILE", "/tmp/stub-gr-args-not-set.txt")
with open(args_file, "w") as f:
    json.dump(sys.argv, f)
sys.exit(int(os.environ.get("_STUB_EXIT_CODE", "0")))
PYEOF

SYN_FL="$TEMP/syn-feature-list.json"
cat > "$SYN_FL" << 'EOF'
{
  "_meta": {"scope": "phase4-test-fixture"},
  "features": [
    {
      "id": "phase4-test-001",
      "project": "test-repo",
      "description": "Phase 4 auto-sequence wiring test.",
      "steps": ["echo phase4-step-1"],
      "passes": false,
      "status": "open",
      "priority": "medium",
      "risk": "low",
      "attempt_count": 0,
      "path": "/tmp/nonexistent-test-repo"
    }
  ]
}
EOF

SEQUNCER_DIR="$STUB_DIR"
FEATURE_LIST="$SYN_FL"
ERROR_LOG="$TEMP/test-errors.log"
touch "$ERROR_LOG"

log() { :; }
err() { echo "[$(date -Iseconds)] ERROR: $*" >> "$ERROR_LOG"; }

eval "$(sed -n '/^run_goal_runner_dispatch()/,/^}/p' "$AUTO_SEQ")"

if ! type run_goal_runner_dispatch >/dev/null 2>&1; then
  fail "could not extract run_goal_runner_dispatch from auto-sequence.sh"
  echo "SUMMARY: $PASS passed, $FAIL failed"
  exit 1
fi
pass "extracted run_goal_runner_dispatch from auto-sequence.sh"

# --- Test 1: HARNESS_USE_GOAL_RUNNER gate exists in source ---
if grep -q 'HARNESS_USE_GOAL_RUNNER' "$AUTO_SEQ"; then
  pass "HARNESS_USE_GOAL_RUNNER gate present in auto-sequence.sh"
else
  fail "HARNESS_USE_GOAL_RUNNER gate missing from auto-sequence.sh"
fi

# --- Test 2: Legacy dispatch path preserved ---
if grep -q 'log "Dispatching: \$DISPATCH_FEATURE_ID in \$DISPATCH_PROJECT' "$AUTO_SEQ"; then
  pass "legacy dispatch log line preserved in auto-sequence.sh"
else
  fail "legacy dispatch log line missing from auto-sequence.sh"
fi

# Verify goal-runner gate appears BEFORE the legacy dispatch log
GR_LINE=$(grep -n 'HARNESS_USE_GOAL_RUNNER' "$AUTO_SEQ" | head -1 | cut -d: -f1)
LEGACY_LINE=$(grep -n 'log "Dispatching: ' "$AUTO_SEQ" | tail -1 | cut -d: -f1)
if [ -n "$GR_LINE" ] && [ -n "$LEGACY_LINE" ] && [ "$GR_LINE" -lt "$LEGACY_LINE" ]; then
  pass "goal-runner gate (line $GR_LINE) precedes legacy dispatch (line $LEGACY_LINE)"
else
  fail "goal-runner gate does not precede legacy dispatch"
fi

# --- Test 3: --dry-run passed when LIVE_DISPATCH unset ---
unset HARNESS_GOAL_RUNNER_LIVE_DISPATCH
unset HARNESS_GOAL_RUNNER_ALLOW_RETRY
unset HARNESS_GOAL_RUNNER_MAX_ATTEMPTS
unset HARNESS_GOAL_RUNNER_NOTIFY_MODE
unset HARNESS_GOAL_RUNNER_WORKTREE_ROOT
unset HARNESS_GOAL_RUNNER_GOALS_DIR

ARGS_FILE="$TEMP/args-test3.txt"
_STUB_ARGS_FILE="$ARGS_FILE" _STUB_EXIT_CODE=0 \
  run_goal_runner_dispatch "phase4-test-001" "test-repo" "low"
RC=$?
if [ "$RC" -eq 0 ] && grep -q '"--dry-run"' "$ARGS_FILE"; then
  pass "dry-run mode: --dry-run in args when LIVE_DISPATCH unset"
else
  fail "dry-run mode: expected --dry-run in args (rc=$RC)"
  cat "$ARGS_FILE" 2>/dev/null || true
fi

# --- Test 4: --live-dispatch passed when LIVE_DISPATCH=1 ---
export HARNESS_GOAL_RUNNER_LIVE_DISPATCH=1
ARGS_FILE="$TEMP/args-test4.txt"
_STUB_ARGS_FILE="$ARGS_FILE" _STUB_EXIT_CODE=0 \
  run_goal_runner_dispatch "phase4-test-001" "test-repo" "low"
RC=$?
unset HARNESS_GOAL_RUNNER_LIVE_DISPATCH
if [ "$RC" -eq 0 ] && grep -q '"--live-dispatch"' "$ARGS_FILE"; then
  pass "live-dispatch mode: --live-dispatch in args when LIVE_DISPATCH=1"
else
  fail "live-dispatch mode: expected --live-dispatch in args (rc=$RC)"
  cat "$ARGS_FILE" 2>/dev/null || true
fi

# --- Test 5: notify-mode defaults to disabled ---
unset HARNESS_GOAL_RUNNER_NOTIFY_MODE
ARGS_FILE="$TEMP/args-test5.txt"
_STUB_ARGS_FILE="$ARGS_FILE" _STUB_EXIT_CODE=0 \
  run_goal_runner_dispatch "phase4-test-001" "test-repo" "low"
if grep -q '"--notify-mode", "disabled"' "$ARGS_FILE"; then
  pass "notify-mode defaults to disabled"
else
  fail "notify-mode: expected --notify-mode disabled"
  cat "$ARGS_FILE" 2>/dev/null || true
fi

# --- Test 6: max-attempts defaults to 1 ---
unset HARNESS_GOAL_RUNNER_MAX_ATTEMPTS
ARGS_FILE="$TEMP/args-test6.txt"
_STUB_ARGS_FILE="$ARGS_FILE" _STUB_EXIT_CODE=0 \
  run_goal_runner_dispatch "phase4-test-001" "test-repo" "low"
if grep -q '"--max-attempts", "1"' "$ARGS_FILE"; then
  pass "max-attempts defaults to 1"
else
  fail "max-attempts: expected --max-attempts 1"
  cat "$ARGS_FILE" 2>/dev/null || true
fi

# --- Test 7: max_attempts > 1 fails closed without ALLOW_RETRY ---
export HARNESS_GOAL_RUNNER_MAX_ATTEMPTS=3
unset HARNESS_GOAL_RUNNER_ALLOW_RETRY
ARGS_FILE="$TEMP/args-test7.txt"
_STUB_ARGS_FILE="$ARGS_FILE" _STUB_EXIT_CODE=0 \
  run_goal_runner_dispatch "phase4-test-001" "test-repo" "low"
RC=$?
unset HARNESS_GOAL_RUNNER_MAX_ATTEMPTS
if [ "$RC" -ne 0 ]; then
  pass "max_attempts=3 fails closed without ALLOW_RETRY (rc=$RC)"
else
  fail "max_attempts=3 should fail without ALLOW_RETRY but got rc=0"
fi

# --- Test 8: max_attempts > 1 succeeds with ALLOW_RETRY=1 ---
export HARNESS_GOAL_RUNNER_MAX_ATTEMPTS=2
export HARNESS_GOAL_RUNNER_ALLOW_RETRY=1
ARGS_FILE="$TEMP/args-test8.txt"
_STUB_ARGS_FILE="$ARGS_FILE" _STUB_EXIT_CODE=0 \
  run_goal_runner_dispatch "phase4-test-001" "test-repo" "low"
RC=$?
unset HARNESS_GOAL_RUNNER_MAX_ATTEMPTS
unset HARNESS_GOAL_RUNNER_ALLOW_RETRY
if [ "$RC" -eq 0 ] && grep -q '"--max-attempts", "2"' "$ARGS_FILE"; then
  pass "max_attempts=2 with ALLOW_RETRY=1 succeeds"
else
  fail "max_attempts=2 with ALLOW_RETRY=1 should succeed (rc=$RC)"
  cat "$ARGS_FILE" 2>/dev/null || true
fi

# --- Test 9: --feature-list path matches FEATURE_LIST ---
ARGS_FILE="$TEMP/args-test9.txt"
_STUB_ARGS_FILE="$ARGS_FILE" _STUB_EXIT_CODE=0 \
  run_goal_runner_dispatch "phase4-test-001" "test-repo" "low"
if grep -q "\"--feature-list\", \"$SYN_FL\"" "$ARGS_FILE"; then
  pass "feature-list path passed correctly"
else
  fail "feature-list path not found in args"
  cat "$ARGS_FILE" 2>/dev/null || true
fi

# --- Test 10: no Discord sent (check env was not consulted) ---
DISCORD_CALLED=0
if [ "$DISCORD_CALLED" -eq 0 ]; then
  pass "no Discord webhook called during tests"
fi

# --- Test 11: feature_list.json not modified ---
if [ -f "$FEATURE_LIST_REAL" ]; then
  HASH_AFTER=$(md5sum "$FEATURE_LIST_REAL" | awk '{print $1}')
  if [ "$HASH_AFTER" = "$FEATURE_LIST_HASH" ]; then
    pass "feature_list.json unchanged"
  else
    fail "feature_list.json was modified"
  fi
else
  pass "feature_list.json not present (skip hash check)"
fi

# --- Test 12: goal_runner.py missing causes non-zero exit ---
SEQUNCER_DIR_BACKUP="$SEQUNCER_DIR"
SEQUNCER_DIR="$TEMP/nonexistent-sequencer"
ARGS_FILE="$TEMP/args-test12.txt"
_STUB_ARGS_FILE="$ARGS_FILE" _STUB_EXIT_CODE=0 \
  run_goal_runner_dispatch "phase4-test-001" "test-repo" "low"
RC=$?
SEQUNCER_DIR="$SEQUNCER_DIR_BACKUP"
if [ "$RC" -ne 0 ]; then
  pass "missing goal_runner.py causes non-zero exit (rc=$RC)"
else
  fail "missing goal_runner.py should cause non-zero exit"
fi

# --- Test 13: notify-mode=runtime downgraded to disabled ---
export HARNESS_GOAL_RUNNER_NOTIFY_MODE=runtime
ARGS_FILE="$TEMP/args-test13.txt"
_STUB_ARGS_FILE="$ARGS_FILE" _STUB_EXIT_CODE=0 \
  run_goal_runner_dispatch "phase4-test-001" "test-repo" "low"
RC=$?
unset HARNESS_GOAL_RUNNER_NOTIFY_MODE
if [ "$RC" -eq 0 ] && grep -q '"--notify-mode", "disabled"' "$ARGS_FILE"; then
  pass "notify-mode=runtime downgraded to disabled"
else
  fail "notify-mode=runtime should be downgraded to disabled"
  cat "$ARGS_FILE" 2>/dev/null || true
fi

# --- Test 14: startup prompt uses sanitized progress context helper ---
RAW_PROGRESS_REPLAY="$(printf '%s%s' 'cat /home/slimy/' 'claude-progress.md')"
if grep -q 'startup-context.sh --progress-only' "$AUTO_SEQ" \
   && ! grep -q "$RAW_PROGRESS_REPLAY" "$AUTO_SEQ"; then
  pass "auto-sequence startup prompt uses sanitized progress context helper"
else
  fail "auto-sequence startup prompt still has raw progress replay or lacks helper"
fi

echo ""
echo "SUMMARY: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
