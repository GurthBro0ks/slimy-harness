#!/usr/bin/env bash
# test_phase2_no_pycache.sh — verify Python bytecode cache prevention
#
# Proves:
#   1. The Phase 2 preamble mentions PYTHONDONTWRITEBYTECODE=1
#   2. Live prompt still starts with the exact 3-line harness block
#   3. qa-gate.sh runs truth-gate Python commands with
#      PYTHONDONTWRITEBYTECODE=1 set in the env
#   4. Running a synthetic truth-gate command that imports a Python
#      module under the qa-gate's clean env does NOT create a
#      __pycache__ directory inside the synthetic worktree
#
# Does NOT launch a real agent. Uses temp git repos under /tmp.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GOAL_RUNNER="$REPO_ROOT/sequencer/goal_runner.py"
QA_GATE="$REPO_ROOT/sequencer/qa-gate.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_phase2_no_pycache.sh ==="

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

# --- 1. Verify preamble mentions PYTHONDONTWRITEBYTECODE=1 ---
echo
echo "--- check 1: preamble mentions PYTHONDONTWRITEBYTECODE=1 ---"
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _build_live_prompt_preamble
from pathlib import Path
fake = Path('$TEMP/a')
fake.mkdir(exist_ok=True)
preamble = _build_live_prompt_preamble(fake, '/tmp/syn', 'syn-001')
text = '\n'.join(preamble)
ok = ('PYTHONDONTWRITEBYTECODE=1' in text
      and 'Python bytecode caches' in text
      and 'goal-runner' in text)
print('YES' if ok else 'NO')
")
if [ "$RESULT" = "YES" ]; then
  pass "preamble contains pycache rule and PYTHONDONTWRITEBYTECODE=1"
else
  fail "preamble missing pycache rule"
fi

# --- 2. Verify live prompt still starts with sanitized 3-line block ---
echo
echo "--- check 2: live prompt still starts with sanitized 3-line block ---"
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import build_attempt_prompt, _build_live_prompt_preamble
from pathlib import Path
feature = {'id': 'syn-001', 'project': 'syn', 'description': 'x', 'steps': ['echo y']}
base = build_attempt_prompt(feature, 1, None, 1)
base_lines = base.splitlines()
insert_at = 3
if len(base_lines) > insert_at and base_lines[insert_at].strip() == '':
    insert_at += 1
preamble = _build_live_prompt_preamble(Path('$TEMP/a'), '/tmp/syn', 'syn-001')
new_lines = base_lines[:insert_at] + [''] + preamble + base_lines[insert_at:]
final = '\n'.join(new_lines)
lines = final.splitlines()
print(lines[0])
print(lines[1])
print(lines[2])
")
LINE1=$(echo "$RESULT" | sed -n '1p')
LINE2=$(echo "$RESULT" | sed -n '2p')
LINE3=$(echo "$RESULT" | sed -n '3p')
if [ "$LINE1" = "cat /home/slimy/AGENTS.md" ] \
   && [ "$LINE2" = "bash /home/slimy/slimy-harness/sequencer/startup-context.sh --progress-only" ] \
   && [ "$LINE3" = "source /home/slimy/init.sh" ]; then
  pass "preamble injection still preserves sanitized 3-line start block"
else
  fail "sanitized 3-line start block broken: '$LINE1' / '$LINE2' / '$LINE3'"
fi

# --- 3. Verify _launch_tmux_session prefixes PYTHONDONTWRITEBYTECODE=1 ---
echo
echo "--- check 3: tmux launch command includes PYTHONDONTWRITEBYTECODE=1 prefix ---"
# Use Python to inspect the source code of _launch_tmux_session
RESULT=$(python3 -c "
import sys, inspect
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _launch_tmux_session
src = inspect.getsource(_launch_tmux_session)
print('YES' if 'PYTHONDONTWRITEBYTECODE=1' in src and 'env_prefix' in src else 'NO')
")
if [ "$RESULT" = "YES" ]; then
  pass "_launch_tmux_session sets PYTHONDONTWRITEBYTECODE=1 in tmux env"
else
  fail "_launch_tmux_session missing PYTHONDONTWRITEBYTECODE=1"
fi

# --- 4. Verify qa-gate.sh applies PYTHONDONTWRITEBYTECODE=1 in its real-mode env ---
echo
echo "--- check 4: qa-gate.sh real-mode env includes PYTHONDONTWRITEBYTECODE=1 ---"
if grep -q 'PYTHONDONTWRITEBYTECODE' "$QA_GATE"; then
  pass "qa-gate.sh references PYTHONDONTWRITEBYTECODE"
else
  fail "qa-gate.sh missing PYTHONDONTWRITEBYTECODE"
fi
# Confirm it's the right context (set in the env passed to subprocess.run, not just any mention)
if grep -B 1 -A 2 'PYTHONDONTWRITEBYTECODE' "$QA_GATE" | grep -q 'clean_env'; then
  pass "qa-gate.sh sets PYTHONDONTWRITEBYTECODE on the subprocess.run env"
else
  fail "qa-gate.sh does not set PYTHONDONTWRITEBYTECODE on subprocess.run env"
fi

# --- 5. End-to-end: run a synthetic truth gate with a Python import ---
echo
echo "--- check 5: synthetic truth-gate Python command does NOT create __pycache__ ---"
# Build a synthetic git repo with a Python module + a script that imports it
SYN_REPO="$TEMP/syn-repo"
mkdir -p "$SYN_REPO"
git -C "$SYN_REPO" init -q -b main
git -C "$SYN_REPO" config user.email "t@t"
git -C "$SYN_REPO" config user.name "t"
mkdir -p "$SYN_REPO/src"
cat > "$SYN_REPO/src/mymod.py" <<'PY'
def hello():
    return "hello"
PY
cat > "$SYN_REPO/run.py" <<'PY'
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "src"))
from mymod import hello
assert hello() == "hello"
print("ok")
PY
git -C "$SYN_REPO" add src/mymod.py run.py
git -C "$SYN_REPO" commit -q -m "init"

# Build a feature list with a Python truth-gate command
SYN_FL="$TEMP/syn-fl.json"
cat > "$SYN_FL" <<EOF
{
  "_meta": {"scope": "phase2-no-pycache-test"},
  "features": [
    {
      "id": "syn-nopyc-001",
      "project": "syn-repo",
      "description": "Python truth-gate test.",
      "steps": ["python3 $SYN_REPO/run.py"],
      "passes": false,
      "status": "open",
      "risk": "low",
      "path": "$SYN_REPO",
      "blocked_by": []
    }
  ]
}
EOF

# Set up attempt dir + a fake session report (completed) so qa-gate has data to evaluate
ATTEMPT_DIR="$TEMP/attempt-1"
mkdir -p "$ATTEMPT_DIR"
cat > "$ATTEMPT_DIR/session-report.json" <<'JSON'
{
  "status": "completed",
  "summary": "synthetic",
  "tests": {"ran": true, "passed": true, "count": 1, "failed_count": 0},
  "changes": []
}
JSON

# Run qa-gate WITHOUT QA_GATE_DRY_RUN (real mode) with the Python truth gate
# This will run 'python3 run.py' inside the synthetic repo. If PYTHONDONTWRITEBYTECODE
# is not propagated correctly, the import will create src/__pycache__.
QA_GATE_DRY_RUN=0 bash "$QA_GATE" syn-nopyc-001 \
  "$ATTEMPT_DIR/session-report.json" \
  "$ATTEMPT_DIR" \
  "$SYN_FL" >"$TEMP/qa-gate.log" 2>&1
RC=$?
echo "    [debug] qa-gate log:"
sed 's/^/      /' "$TEMP/qa-gate.log" | head -10
if [ "$RC" = "0" ]; then
  pass "qa-gate exit 0 (truth gate passed)"
else
  fail "qa-gate exit $RC"
fi

# Verify qa-result.json verdict=pass
if [ -f "$ATTEMPT_DIR/qa-result.json" ]; then
  VERDICT=$(python3 -c "import json; print(json.load(open('$ATTEMPT_DIR/qa-result.json')).get('verdict',''))")
  if [ "$VERDICT" = "pass" ]; then
    pass "qa-result.json verdict=pass"
  else
    fail "qa-result.json verdict=$VERDICT (want pass)"
  fi
else
  fail "qa-result.json missing"
fi

# THE KEY CHECK: did Python create __pycache__ in the worktree?
# Scan recursively
PYCACHE_DIRS=$(find "$SYN_REPO" -type d -name "__pycache__" 2>/dev/null || true)
PYC_FILES=$(find "$SYN_REPO" -name "*.pyc" 2>/dev/null || true)
if [ -z "$PYCACHE_DIRS" ] && [ -z "$PYC_FILES" ]; then
  pass "no __pycache__ or .pyc files in synthetic worktree"
else
  echo "    [debug] found __pycache__ dirs:"
  echo "$PYCACHE_DIRS" | sed 's/^/      /'
  echo "    [debug] found .pyc files:"
  echo "$PYC_FILES" | sed 's/^/      /'
  fail "__pycache__ or .pyc files were created in worktree"
fi

# Sanity check: the source repo should also still be clean
SRC_DIRTY=$(git -C "$SYN_REPO" status --porcelain)
if [ -z "$SRC_DIRTY" ]; then
  pass "synthetic source repo still clean after qa-gate run"
else
  fail "synthetic source repo got dirty:\n$SRC_DIRTY"
fi

echo
echo "=== results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] && exit 0 || exit 1
