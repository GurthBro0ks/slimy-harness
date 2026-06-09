#!/usr/bin/env bash
# test_stuck_detection.sh — exercise count_stuck_signals() in goal_runner.py
#
# Builds a fake goal structure with two attempt qa-results and asserts the
# signal count matches expectations across three scenarios.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GOAL_RUNNER="$REPO_ROOT/sequencer/goal_runner.py"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_stuck_detection.sh ==="

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

# Build a goal skeleton
mkdir -p "$TEMP/attempt-1" "$TEMP/attempt-2"

cat > "$TEMP/goal.json" << 'EOF'
{
  "feature_id": "test-feature-001",
  "status": "running",
  "started": "2026-06-09T00:00:00Z",
  "current_attempt": 2,
  "max_attempts": 3,
  "wall_clock_limit_minutes": 90,
  "attempts": []
}
EOF

# Scenario A: stuck — identical error signatures, empty changed_files
cat > "$TEMP/attempt-1/qa-result.json" << 'EOF'
{
  "feature_id": "test-feature-001",
  "attempt": 1,
  "verdict": "fail",
  "session_status": "completed",
  "tests_passed": false,
  "test_pass_count": 5,
  "changed_files": [],
  "error_signatures": ["aaaa1111", "bbbb2222"],
  "failing_commands": [{"command": "echo step-1", "signature": "aaaa1111"}]
}
EOF

cat > "$TEMP/attempt-2/qa-result.json" << 'EOF'
{
  "feature_id": "test-feature-001",
  "attempt": 2,
  "verdict": "fail",
  "session_status": "completed",
  "tests_passed": false,
  "test_pass_count": 4,
  "changed_files": [],
  "error_signatures": ["aaaa1111", "bbbb2222"],
  "failing_commands": [{"command": "echo step-1", "signature": "aaaa1111"}]
}
EOF

echo
echo "--- scenario A: stuck (overlap + empty + same + regression) ---"
RESULT=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import count_stuck_signals
prev = json.load(open('$TEMP/attempt-1/qa-result.json'))
curr = json.load(open('$TEMP/attempt-2/qa-result.json'))
print(count_stuck_signals(curr, prev))
")
echo "  signals=$RESULT"
if [ "$RESULT" -ge 3 ]; then
  pass "stuck signals >= 3 (got $RESULT)"
else
  fail "expected >= 3, got $RESULT"
fi

# Scenario B: blocked -> +2
cat > "$TEMP/attempt-2/qa-result.json" << 'EOF'
{
  "feature_id": "test-feature-001",
  "attempt": 2,
  "verdict": "fail",
  "session_status": "blocked",
  "tests_passed": false,
  "test_pass_count": null,
  "changed_files": [],
  "error_signatures": ["xxxx9999"],
  "failing_commands": []
}
EOF
cat > "$TEMP/attempt-1/qa-result.json" << 'EOF'
{
  "feature_id": "test-feature-001",
  "attempt": 1,
  "verdict": "fail",
  "session_status": "completed",
  "tests_passed": false,
  "test_pass_count": 5,
  "changed_files": ["foo.py"],
  "error_signatures": ["yyyy8888"],
  "failing_commands": []
}
EOF

echo
echo "--- scenario B: blocked status -> +2 ---"
RESULT=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import count_stuck_signals
prev = json.load(open('$TEMP/attempt-1/qa-result.json'))
curr = json.load(open('$TEMP/attempt-2/qa-result.json'))
print(count_stuck_signals(curr, prev))
")
echo "  signals=$RESULT"
if [ "$RESULT" -ge 2 ]; then
  pass "blocked status signals >= 2 (got $RESULT)"
else
  fail "expected >= 2 (blocked adds 2), got $RESULT"
fi

# Scenario C: different sigs, different changed files, no test_pass_count -> 0
cat > "$TEMP/attempt-1/qa-result.json" << 'EOF'
{
  "feature_id": "test-feature-001",
  "attempt": 1,
  "verdict": "fail",
  "session_status": "completed",
  "tests_passed": false,
  "test_pass_count": 3,
  "changed_files": ["foo.py"],
  "error_signatures": ["aaaa1111"],
  "failing_commands": []
}
EOF
cat > "$TEMP/attempt-2/qa-result.json" << 'EOF'
{
  "feature_id": "test-feature-001",
  "attempt": 2,
  "verdict": "fail",
  "session_status": "completed",
  "tests_passed": false,
  "test_pass_count": null,
  "changed_files": ["bar.py"],
  "error_signatures": ["zzzz5555"],
  "failing_commands": []
}
EOF

echo
echo "--- scenario C: different sigs, different files, no test_pass_count -> 0 ---"
RESULT=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import count_stuck_signals
prev = json.load(open('$TEMP/attempt-1/qa-result.json'))
curr = json.load(open('$TEMP/attempt-2/qa-result.json'))
print(count_stuck_signals(curr, prev))
")
echo "  signals=$RESULT"
if [ "$RESULT" = "0" ]; then
  pass "zero signals when truly different (got 0)"
else
  fail "expected 0, got $RESULT"
fi

echo
echo "=== results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] && exit 0 || exit 1
