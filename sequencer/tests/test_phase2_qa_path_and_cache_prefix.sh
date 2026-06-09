#!/usr/bin/env bash
# test_phase2_qa_path_and_cache_prefix.sh — verify qa-gate path precedence
#                                              + Python cache redirect
#
# Proves:
#   1. qa-gate.sh uses feature.project_path (or repo_path / path) when
#      present, NOT the /opt/slimy/<project> fallback.
#   2. The qa-gate resolver stays in SYNC with goal_runner.py's
#      _resolve_project_path helper (same input -> same answer).
#   3. qa-gate.sh sets PYTHONDONTWRITEBYTECODE=1 AND PYTHONPYCACHEPREFIX
#      on the subprocess.run env for real-mode truth gates.
#   4. `python3 -m py_compile <file>` running under qa-gate's real-mode
#      env does NOT create __pycache__/ in the worktree; bytecode is
#      redirected to <attempt_dir>/python-cache/.
#   5. goal_runner.py _launch_tmux_session includes PYTHONPYCACHEPREFIX
#      in the tmux env-prefix.
#   6. Preamble mentions the cache-redirect line.
#
# Uses synthetic temp git repos under /tmp. Does NOT launch a real agent.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GOAL_RUNNER="$REPO_ROOT/sequencer/goal_runner.py"
QA_GATE="$REPO_ROOT/sequencer/qa-gate.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_phase2_qa_path_and_cache_prefix.sh ==="

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

# Build a clean synthetic git repo with a Python module
SYN_REPO="$TEMP/syn-repo"
mkdir -p "$SYN_REPO/src"
git -C "$SYN_REPO" init -q -b main
git -C "$SYN_REPO" config user.email "t@t"
git -C "$SYN_REPO" config user.name "t"
cat > "$SYN_REPO/src/main.py" <<'PY'
def hello():
    return "hello"
PY
cat > "$SYN_REPO/run_compile.py" <<'PY'
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "src"))
# py_compile writes bytecode regardless of PYTHONDONTWRITEBYTECODE,
# so the cache-prefix redirect is the only way to keep __pycache__/
# out of the source tree when this command runs.
import py_compile
py_compile.compile(os.path.join(os.path.dirname(__file__), "src", "main.py"),
                  doraise=True)
print("compile_ok")
PY
git -C "$SYN_REPO" add src/main.py run_compile.py
git -C "$SYN_REPO" commit -q -m "i"
pass "created synthetic git repo at $SYN_REPO"

# Build a feature with a misleading project name + explicit project_path
cat > "$TEMP/syn-fl.json" <<EOF
{
  "_meta": {"scope": "phase2-qa-path-and-cache-prefix"},
  "features": [
    {
      "id": "syn-qap-001",
      "project": "name-that-would-fallback-to-opt-slimy",
      "project_path": "$SYN_REPO",
      "description": "synthetic py_compile test",
      "steps": ["python3 $SYN_REPO/run_compile.py"],
      "passes": false,
      "status": "open",
      "risk": "low",
      "blocked_by": []
    }
  ]
}
EOF

# Set up attempt dir with a synthetic session report
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

# --- TEST 1: qa-gate source has the precedence logic ---
echo
echo "--- check 1: qa-gate.sh source contains _resolve_project_path_qa ---"
if grep -q "_resolve_project_path_qa" "$QA_GATE"; then
  pass "qa-gate.sh has _resolve_project_path_qa helper"
else
  fail "qa-gate.sh missing _resolve_project_path_qa"
fi
# Check the precedence order in the source
if grep -A 4 "def _resolve_project_path_qa" "$QA_GATE" | grep -q '"project_path"'; then
  pass "qa-gate.sh checks project_path first"
else
  fail "qa-gate.sh does not check project_path first"
fi
if grep -A 4 "def _resolve_project_path_qa" "$QA_GATE" | grep -q '"repo_path"'; then
  pass "qa-gate.sh checks repo_path"
else
  fail "qa-gate.sh does not check repo_path"
fi
if grep -A 4 "def _resolve_project_path_qa" "$QA_GATE" | grep -q '"path"'; then
  pass "qa-gate.sh checks path"
else
  fail "qa-gate.sh does not check path"
fi

# --- TEST 2: qa-gate resolver stays in sync with goal_runner.py's helper ---
echo
echo "--- check 2: goal_runner + qa-gate resolvers agree on a battery of inputs ---"
SYNC_OUT=$(python3 - <<PY
import subprocess, sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _resolve_project_path

# A battery of features to test. Each tuple is
# (label, feature_dict, expected_path, expected_source).
cases = [
    ("project_path wins", {"project": "foo", "project_path": "/tmp/winner"}, "/tmp/winner", "project_path"),
    ("repo_path wins when no project_path", {"project": "foo", "repo_path": "/tmp/r"}, "/tmp/r", "repo_path"),
    ("path wins when no project_path/repo_path", {"project": "foo", "path": "/tmp/p"}, "/tmp/p", "path"),
    ("empty strings skipped", {"project": "foo", "project_path": "", "repo_path": "  ", "path": "/tmp/p"}, "/tmp/p", "path"),
    ("only project -> fallback", {"project": "foo"}, "/opt/slimy/foo", "project_fallback"),
    ("no project, no path -> /opt/slimy/unknown", {}, "/opt/slimy/unknown", "project_fallback"),
]

# For each case, call qa-gate.sh in dry-run with a synthetic feature
# and inspect qa-result.json to see if project_path matches.
import json, os, tempfile, shutil
qa_gate = "$QA_GATE"
mismatches = []
for label, feat, exp_path, exp_src in cases:
    tmp = tempfile.mkdtemp()
    feat_id = f"sync-{label.replace(' ','-')}"[:40]
    # Only feed fields the helper uses
    fl = {"_meta": {"scope": "sync"}, "features": [dict(feat, id=feat_id, steps=["echo x"],
                                                          status="open", risk="low", passes=False)]}
    fl_path = os.path.join(tmp, "fl.json")
    with open(fl_path, "w") as f:
        json.dump(fl, f)
    attempt_dir = os.path.join(tmp, "attempt-1")
    os.makedirs(attempt_dir)
    with open(os.path.join(attempt_dir, "session-report.json"), "w") as f:
        json.dump({"status": "completed", "summary": "x",
                   "tests": {"ran": True, "passed": True, "count": 1, "failed_count": 0},
                   "changes": []}, f)
    # dry-run mode: the project_path logic still records project_path and
    # project_path_source (because we set them as None defaults and the
    # real-mode branch sets them; dry-run keeps them as None and qa-result
    # records them as None). For the sync test we want to verify the
    # _resolver_ in goal_runner.py matches what qa-gate would compute.
    # Compute the expected value the same way _resolve_project_path does.
    gr_path, gr_src = _resolve_project_path(fl["features"][0])
    # Now we also know what qa-gate WOULD compute (since the helper logic
    # is identical). Compare to gr_path / gr_src.
    if gr_path != exp_path or gr_src != exp_src:
        mismatches.append(f"{label}: goal_runner resolver returned ({gr_path!r}, {gr_src!r}), expected ({exp_path!r}, {exp_src!r})")
    shutil.rmtree(tmp)

# Also confirm that qa-gate's own _resolve_project_path_qa function (embedded
# in the heredoc) matches by running it in isolation through Python.
# We can read the helper out of qa-gate.sh and re-execute it.
import re
src = open(qa_gate).read()
m = re.search(r"def _resolve_project_path_qa\(feat\):\s*\n((?:\s+.*\n)+?)\n    project_path,", src)
if m:
    helper_body = m.group(1)
    # Build a synthetic module from the helper body
    helper_src = "def _resolve_project_path_qa(feat):\n" + helper_body
    # The body ends with a return. Extract just the body lines.
    mod = {}
    try:
        exec(helper_src, mod)
        helper_fn = mod["_resolve_project_path_qa"]
        # Test on the same battery
        for label, feat, exp_path, exp_src in cases:
            qp, qs = helper_fn(feat)
            if qp != exp_path or qs != exp_src:
                mismatches.append(f"{label}: qa-gate embedded helper returned ({qp!r}, {qs!r}), expected ({exp_path!r}, {exp_src!r})")
    except Exception as e:
        mismatches.append(f"could not exec qa-gate helper: {e}")
else:
    mismatches.append("could not extract _resolve_project_path_qa from qa-gate.sh")

if mismatches:
    for m in mismatches:
        print("MISMATCH:", m)
    print("MISMATCH")
else:
    print("SYNC_OK")
PY
)
if echo "$SYNC_OUT" | tail -1 | grep -q "^SYNC_OK$"; then
  pass "goal_runner + qa-gate resolvers agree on 6 input cases"
else
  echo "    [debug] sync output:"
  echo "$SYNC_OUT" | sed 's/^/      /'
  fail "resolver sync check failed"
fi

# --- TEST 3: qa-gate.sh sets PYTHONPYCACHEPREFIX on the subprocess env ---
echo
echo "--- check 3: qa-gate.sh sets PYTHONPYCACHEPREFIX on subprocess env ---"
if grep -q "PYTHONPYCACHEPREFIX" "$QA_GATE"; then
  pass "qa-gate.sh references PYTHONPYCACHEPREFIX"
else
  fail "qa-gate.sh missing PYTHONPYCACHEPREFIX"
fi
if grep -B 1 -A 1 "PYTHONPYCACHEPREFIX" "$QA_GATE" | grep -q "clean_env"; then
  pass "qa-gate.sh sets PYTHONPYCACHEPREFIX on clean_env"
else
  fail "qa-gate.sh does not put PYTHONPYCACHEPREFIX on clean_env"
fi

# --- TEST 4: goal_runner.py _launch_tmux_session includes PYTHONPYCACHEPREFIX ---
echo
echo "--- check 4: goal_runner _launch_tmux_session includes PYTHONPYCACHEPREFIX ---"
RESULT=$(python3 -c "
import sys, inspect
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _launch_tmux_session
src = inspect.getsource(_launch_tmux_session)
print('YES' if 'PYTHONPYCACHEPREFIX' in src and 'cache_prefix' in src else 'NO')
")
if [ "$RESULT" = "YES" ]; then
  pass "_launch_tmux_session includes PYTHONPYCACHEPREFIX + cache_prefix"
else
  fail "_launch_tmux_session missing PYTHONPYCACHEPREFIX"
fi

# --- TEST 5: end-to-end — qa-gate real mode runs py_compile cleanly ---
echo
echo "--- check 5: end-to-end — py_compile under qa-gate does NOT dirty worktree ---"
# Run qa-gate.sh in REAL mode (no QA_GATE_DRY_RUN) with the synthetic
# truth-gate command. Expect:
#   - qa-result verdict=pass
#   - truth_gate=pass
#   - no __pycache__ or .pyc in the SYN_REPO
#   - PYTHONPYCACHEPREFIX produced files in <attempt_dir>/python-cache/
QA_GATE_DRY_RUN=0 bash "$QA_GATE" syn-qap-001 \
  "$ATTEMPT_DIR/session-report.json" \
  "$ATTEMPT_DIR" \
  "$TEMP/syn-fl.json" >"$TEMP/qa-gate.log" 2>&1
RC=$?
echo "    [debug] qa-gate log:"
sed 's/^/      /' "$TEMP/qa-gate.log" | head -10
if [ "$RC" = "0" ]; then pass "qa-gate exit 0"; else fail "qa-gate rc=$RC"; fi

# Verify qa-result.json verdict=pass and the resolved project_path is the synthetic repo
if [ -f "$ATTEMPT_DIR/qa-result.json" ]; then
  python3 - "$SYN_REPO" "$ATTEMPT_DIR" <<'PY'
import json, sys
exp_repo = sys.argv[1]
attempt_dir = sys.argv[2]
r = json.load(open(f"{attempt_dir}/qa-result.json"))
fails = []
if r.get("verdict") != "pass":
    fails.append(f"verdict={r.get('verdict')} (want pass)")
if r.get("project_path") != exp_repo:
    fails.append(f"project_path={r.get('project_path')!r} (want {exp_repo!r})")
if r.get("project_path_source") != "project_path":
    fails.append(f"project_path_source={r.get('project_path_source')!r} (want 'project_path')")
expected_prefix = f"{attempt_dir}/python-cache"
if r.get("python_cache_prefix") != expected_prefix:
    fails.append(f"python_cache_prefix={r.get('python_cache_prefix')!r} (want {expected_prefix!r})")
if fails:
    for f in fails:
        print("FAIL:", f)
    sys.exit(1)
print("QA_RESULT_OK")
PY
  if [ $? -eq 0 ]; then
    pass "qa-result.json has verdict=pass, project_path=$SYN_REPO, project_path_source=project_path, python_cache_prefix=expected"
  else
    fail "qa-result.json check failed"
  fi
else
  fail "qa-result.json missing"
fi

# The KEY check: no __pycache__ or .pyc in the synthetic worktree
PYCACHE_DIRS=$(find "$SYN_REPO" -type d -name "__pycache__" 2>/dev/null || true)
PYC_FILES=$(find "$SYN_REPO" -name "*.pyc" 2>/dev/null || true)
if [ -z "$PYCACHE_DIRS" ] && [ -z "$PYC_FILES" ]; then
  pass "no __pycache__ or .pyc files in synthetic worktree after py_compile"
else
  echo "    [debug] __pycache__ dirs found:"
  echo "$PYCACHE_DIRS" | sed 's/^/      /'
  echo "    [debug] .pyc files found:"
  echo "$PYC_FILES" | sed 's/^/      /'
  fail "worktree got dirty with __pycache__ or .pyc files"
fi

# The cache SHOULD exist under the attempt dir (proves redirect works)
CACHE_DIR="$ATTEMPT_DIR/python-cache"
if [ -d "$CACHE_DIR" ]; then
  pass "cache redirect directory exists at $CACHE_DIR"
  CACHE_PYC=$(find "$CACHE_DIR" -name "*.pyc" 2>/dev/null | head -3)
  if [ -n "$CACHE_PYC" ]; then
    pass "cache redirect contains .pyc files (py_compile output went here)"
    echo "    [debug] sample cache files:"
    echo "$CACHE_PYC" | sed 's/^/      /'
  else
    fail "cache redirect dir exists but has no .pyc files (redirect ineffective?)"
  fi
else
  fail "cache redirect directory NOT created at $CACHE_DIR"
fi

# Sanity: synthetic source repo still clean
SRC_DIRTY=$(git -C "$SYN_REPO" status --porcelain)
if [ -z "$SRC_DIRTY" ]; then
  pass "synthetic source repo still clean after qa-gate real-mode run"
else
  fail "synthetic source repo got dirty:\n$SRC_DIRTY"
fi

# --- TEST 6: preamble mentions cache redirect ---
echo
echo "--- check 6: live prompt preamble mentions cache redirect ---"
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _build_live_prompt_preamble
from pathlib import Path
preamble = _build_live_prompt_preamble(Path('$TEMP/x'), '/tmp/syn', 'syn-001')
text = '\n'.join(preamble)
print('YES' if 'Python bytecode caches are redirected' in text and 'outside the worktree' in text else 'NO')
")
if [ "$RESULT" = "YES" ]; then
  pass "preamble mentions cache redirect rule"
else
  fail "preamble missing cache redirect rule"
fi

echo
echo "=== results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] && exit 0 || exit 1
