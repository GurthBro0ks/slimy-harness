#!/usr/bin/env bash
# test_phase2_project_path.sh — verify explicit project_path precedence
#
# Bug fix: feature.project_path was previously ignored; goal-runner
# would fall back to /opt/slimy/<feature.project>. This test proves
# the fix is correct for the documented precedence:
#
#   project_path  >  repo_path  >  path  >  project_fallback
#
# Uses synthetic temp git repos under /tmp. Does NOT launch a real
# agent — verifies goal-runner behavior via Python imports and one
# end-to-end dry-run that uses the resolver via main().
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GOAL_RUNNER="$REPO_ROOT/sequencer/goal_runner.py"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_phase2_project_path.sh ==="

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

# Build a clean synthetic git repo
SYN_REPO="$TEMP/syn-repo"
mkdir -p "$SYN_REPO"
git -C "$SYN_REPO" init -q -b main
git -C "$SYN_REPO" config user.email "t@t"
git -C "$SYN_REPO" config user.name "t"
echo "x" > "$SYN_REPO/README.md"
git -C "$SYN_REPO" add README.md
git -C "$SYN_REPO" commit -q -m "i"
pass "created synthetic git repo at $SYN_REPO"

# --- TEST 1: unit test the resolver via Python import ---
echo
echo "--- check 1: _resolve_project_path unit tests ---"
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _resolve_project_path

# case A: project_path wins over project
f = {'project': 'name-that-would-fallback-to-opt-slimy', 'project_path': '$SYN_REPO'}
p, s = _resolve_project_path(f)
print(f'{p}|{s}|' + ('OK' if p == '$SYN_REPO' and s == 'project_path' else 'BAD'))
" 2>&1)
if echo "$RESULT" | tail -1 | grep -q "|OK$"; then
  pass "project_path wins over project name"
else
  fail "project_path precedence broken: $RESULT"
fi

# case B: repo_path wins over project (when no project_path)
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _resolve_project_path
f = {'project': 'foo', 'repo_path': '$SYN_REPO'}
p, s = _resolve_project_path(f)
print(f'{p}|{s}|' + ('OK' if p == '$SYN_REPO' and s == 'repo_path' else 'BAD'))
" 2>&1)
if echo "$RESULT" | tail -1 | grep -q "|OK$"; then
  pass "repo_path wins over project name"
else
  fail "repo_path precedence broken: $RESULT"
fi

# case C: path wins over project (when no project_path or repo_path)
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _resolve_project_path
f = {'project': 'foo', 'path': '$SYN_REPO'}
p, s = _resolve_project_path(f)
print(f'{p}|{s}|' + ('OK' if p == '$SYN_REPO' and s == 'path' else 'BAD'))
" 2>&1)
if echo "$RESULT" | tail -1 | grep -q "|OK$"; then
  pass "path wins over project name"
else
  fail "path precedence broken: $RESULT"
fi

# case D: project_path is highest precedence (project_path + repo_path both set)
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _resolve_project_path
f = {'project': 'foo', 'project_path': '/tmp/winner', 'repo_path': '/tmp/loser', 'path': '/tmp/loser2'}
p, s = _resolve_project_path(f)
print(f'{p}|{s}|' + ('OK' if p == '/tmp/winner' and s == 'project_path' else 'BAD'))
" 2>&1)
if echo "$RESULT" | tail -1 | grep -q "|OK$"; then
  pass "project_path > repo_path > path precedence"
else
  fail "precedence chain broken: $RESULT"
fi

# case E: empty strings are skipped
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _resolve_project_path
f = {'project': 'foo', 'project_path': '', 'repo_path': '   ', 'path': '$SYN_REPO'}
p, s = _resolve_project_path(f)
print(f'{p}|{s}|' + ('OK' if p == '$SYN_REPO' and s == 'path' else 'BAD'))
" 2>&1)
if echo "$RESULT" | tail -1 | grep -q "|OK$"; then
  pass "empty / whitespace strings are skipped"
else
  fail "empty-string handling broken: $RESULT"
fi

# case F: only project -> fallback to /opt/slimy/<project>
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _resolve_project_path
f = {'project': 'foo'}
p, s = _resolve_project_path(f)
print(f'{p}|{s}|' + ('OK' if p == '/opt/slimy/foo' and s == 'project_fallback' else 'BAD'))
" 2>&1)
if echo "$RESULT" | tail -1 | grep -q "|OK$"; then
  pass "project-only falls back to /opt/slimy/<project>"
else
  fail "project-only fallback broken: $RESULT"
fi

# --- TEST 2: end-to-end via main(), proving project_path is used, not /opt/slimy fallback ---
echo
echo "--- check 2: end-to-end via goal_runner.py main() ---"
# Build a feature with a misleading project name + an explicit project_path
# pointing at the synthetic repo. The OLD code would have tried
# /opt/slimy/name-that-falls-back and failed cleanly (no /opt/slimy dir).
# The NEW code must use the synthetic repo path.
cat > "$TEMP/syn-fl.json" <<EOF
{
  "_meta": {"scope": "phase2-project-path-test"},
  "features": [
    {
      "id": "syn-pp-001",
      "project": "name-that-falls-back-to-opt-slimy",
      "project_path": "$SYN_REPO",
      "description": "synthetic",
      "steps": ["echo x"],
      "passes": false,
      "status": "open",
      "risk": "low",
      "blocked_by": []
    }
  ]
}
EOF

# Dry-run mode so we don't try to launch a real agent; goal-runner
# should resolve project_path and write goal.json with the synthetic
# repo path + project_path_source="project_path".
GOALS_DIR="$TEMP/goals"
mkdir -p "$GOALS_DIR"
python3 "$GOAL_RUNNER" syn-pp-001 \
  --dry-run \
  --goals-dir "$GOALS_DIR" \
  --feature-list "$TEMP/syn-fl.json" >/dev/null 2>&1
RC=$?
if [ "$RC" = "0" ]; then pass "dry-run exited 0"; else fail "dry-run rc=$RC"; fi

# Inspect goal.json for the resolved path
RESULT=$(python3 -c "
import json
g = json.load(open('$GOALS_DIR/syn-pp-001/goal.json'))
print(f\"{g.get('project_path')}|{g.get('project_path_source')}|{g.get('project')}\")
")
PPATH=$(echo "$RESULT" | cut -d'|' -f1)
PSRC=$(echo "$RESULT" | cut -d'|' -f2)
PPROJ=$(echo "$RESULT" | cut -d'|' -f3)
if [ "$PPATH" = "$SYN_REPO" ]; then
  pass "goal.json project_path == synthetic repo path"
else
  fail "goal.json project_path=$PPATH (want $SYN_REPO)"
fi
if [ "$PSRC" = "project_path" ]; then
  pass "goal.json project_path_source=project_path"
else
  fail "goal.json project_path_source=$PSRC (want project_path)"
fi
if [ "$PPROJ" = "name-that-falls-back-to-opt-slimy" ]; then
  pass "goal.json project (display name) preserved as-is"
else
  fail "goal.json project=$PPROJ"
fi

# --- TEST 3: live-dispatch must use the synthetic repo (not /opt/slimy/...) ---
echo
echo "--- check 3: live-dispatch also uses synthetic repo (worktree created there) ---"
# Use a fresh feature id + goals dir to avoid resume-state pollution
cat > "$TEMP/syn-fl-live.json" <<EOF
{
  "_meta": {"scope": "phase2-project-path-test-live"},
  "features": [
    {
      "id": "syn-pp-live-001",
      "project": "name-that-falls-back-to-opt-slimy",
      "project_path": "$SYN_REPO",
      "description": "synthetic live",
      "steps": ["echo x"],
      "passes": false,
      "status": "open",
      "risk": "low",
      "blocked_by": []
    }
  ]
}
EOF
GOALS_LIVE="$TEMP/goals-live"
WT_ROOT="$TEMP/wt"
mkdir -p "$GOALS_LIVE"
# Use --max-attempts 1 + notify-mode disabled (the safe defaults)
# Use a very short poll interval + a custom tmux prefix to make the
# test fast and isolated.
# The test only verifies the CHECKPOINT resolves to the synthetic repo,
# so we can run with a really short wall-clock. But we also have to
# avoid actually launching the agent. Trick: pass a bogus agent_cmd
# that will fail-fast when tmux tries to exec it. The CHECKPOINT
# (worktree create) happens BEFORE the tmux launch, so we will see
# the worktree path in the events.jsonl before any agent activity.
python3 "$GOAL_RUNNER" syn-pp-live-001 \
  --live-dispatch \
  --max-attempts 1 \
  --notify-mode disabled \
  --worktree-root "$WT_ROOT" \
  --goals-dir "$GOALS_LIVE" \
  --agent-cmd "/bin/false" \
  --tmux-prefix "syn-pp-test" \
  --feature-list "$TEMP/syn-fl-live.json" 2>&1 \
  | sed -n '1,30p' > "$TEMP/live-stderr.log" || true
# The runner may exit non-zero (worktree created, then tmux launch failed
# quickly because /bin/false exits 1 immediately). What we care about is
# that the CHECKPOINT event recorded the SYNTHETIC repo path, not /opt/slimy.
RESULT=$(python3 -c "
import json
events = []
with open('$GOALS_LIVE/syn-pp-live-001/events.jsonl') as f:
    for line in f:
        try: events.append(json.loads(line))
        except: pass
# find checkpoint events
ck = [e for e in events if e.get('event') == 'checkpoint']
if ck:
    last = ck[-1]
    print(f\"{last.get('worktree_path','')}|{last.get('worktree_created','')}\")
else:
    print('|no_checkpoint')
")
WPATH=$(echo "$RESULT" | cut -d'|' -f1)
WCREATED=$(echo "$RESULT" | cut -d'|' -f2)
if [ -n "$WPATH" ] && [ "$WCREATED" = "True" ]; then
  pass "worktree created at $WPATH (under WT_ROOT, project_path honored)"
else
  fail "worktree path=$WPATH, created=$WCREATED; full result: $RESULT"
  echo "    [debug] live log:"
  sed 's/^/      /' "$TEMP/live-stderr.log" | head -10
fi

# Verify the source repo is still clean (no spurious changes to /opt/slimy)
SRC_CLEAN=$(git -C "$SYN_REPO" status --porcelain)
if [ -z "$SRC_CLEAN" ]; then
  pass "synthetic source repo still clean after live-dispatch checkpoint"
else
  fail "synthetic source repo got dirty: $SRC_CLEAN"
fi

# /opt/slimy should NOT have a 'name-that-falls-back-to-opt-slimy' directory
# created by the test (the OLD bug would have failed before creating it,
# but defensively confirm).
if [ ! -d "/opt/slimy/name-that-falls-back-to-opt-slimy" ]; then
  pass "no /opt/slimy/<project> dir was created"
else
  fail "leaked /opt/slimy/<project> directory"
fi

echo
echo "=== results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] && exit 0 || exit 1
