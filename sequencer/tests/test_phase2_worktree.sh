#!/usr/bin/env bash
# test_phase2_worktree.sh — Phase 2 worktree creation + live-prompt shape
#
# Verifies:
#   - _create_worktree() makes an isolated worktree from a clean repo
#   - The worktree has the same HEAD SHA as the source
#   - The worktree is a separate working tree (different HEAD path)
#   - The build_attempt_prompt + live-preamble injection still starts
#     with the exact 3-line harness context block
#   - The injected live preamble contains the safety rules
#
# This test does NOT launch a real agent. It only exercises the
# worktree helper and the prompt-builder logic via Python import.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GOAL_RUNNER="$REPO_ROOT/sequencer/goal_runner.py"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_phase2_worktree.sh ==="

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

# Create a clean synthetic git repo with one commit
SYN_REPO="$TEMP/syn-repo"
mkdir -p "$SYN_REPO"
git -C "$SYN_REPO" init -q -b main
git -C "$SYN_REPO" config user.email "test@example.com"
git -C "$SYN_REPO" config user.name "Test"
echo "phase 2 worktree test" > "$SYN_REPO/README.md"
git -C "$SYN_REPO" add README.md
git -C "$SYN_REPO" commit -q -m "init"
pass "created synthetic git repo"

WT_PATH="$TEMP/wt"
SOURCE_SHA=$(git -C "$SYN_REPO" rev-parse HEAD)
echo "source SHA=$SOURCE_SHA"

# --- TEST 1: _create_worktree works ---
echo
echo "--- test 1: _create_worktree helper ---"
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _create_worktree
ok, msg = _create_worktree('$SYN_REPO', '$WT_PATH')
print('OK' if ok else 'FAIL')
print(msg)
")
echo "$RESULT" | head -1 | grep -q "^OK$" && pass "_create_worktree returned ok" || fail "_create_worktree failed: $RESULT"
[ -d "$WT_PATH" ] && pass "worktree directory exists at $WT_PATH" || fail "worktree dir not created"
[ -d "$WT_PATH/.git" ] || [ -f "$WT_PATH/.git" ] && pass "worktree is a git worktree" || fail "worktree is not git"

# --- TEST 2: worktree has same HEAD as source ---
WT_SHA=$(git -C "$WT_PATH" rev-parse HEAD 2>/dev/null || echo "missing")
if [ "$WT_SHA" = "$SOURCE_SHA" ]; then
  pass "worktree HEAD == source HEAD ($WT_SHA)"
else
  fail "worktree HEAD=$WT_SHA != source SHA=$SOURCE_SHA"
fi

# --- TEST 3: source repo is untouched ---
SRC_DIRTY=$(git -C "$SYN_REPO" status --porcelain)
if [ -z "$SRC_DIRTY" ]; then
  pass "source repo still clean after worktree create"
else
  fail "source repo got dirty:\n$SRC_DIRTY"
fi

# --- TEST 4: refuse to overwrite an existing worktree path ---
echo
echo "--- test 4: refuse to overwrite existing worktree path ---"
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import _create_worktree
ok, msg = _create_worktree('$SYN_REPO', '$WT_PATH')
print('OK' if ok else 'REFUSED')
print(msg)
" 2>&1)
if echo "$RESULT" | grep -q "REFUSED"; then
  pass "_create_worktree refused to overwrite existing path"
else
  fail "_create_worktree did not refuse overwrite: $RESULT"
fi

# --- TEST 5: prompt preamble injection still starts with 3-line block ---
echo
echo "--- test 5: live prompt preamble preserves 3-line start block ---"
RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT/sequencer')
from goal_runner import build_attempt_prompt, _build_live_prompt_preamble
from pathlib import Path
fake_attempt = Path('$TEMP/attempt-1')
fake_attempt.mkdir(exist_ok=True)
feature = {
    'id': 'syn-feature-001',
    'project': 'syn-repo',
    'description': 'syn test',
    'steps': ['echo hi'],
}
base_prompt = build_attempt_prompt(feature, 1, None, 1)
# Same injection logic as main()
base_lines = base_prompt.splitlines()
insert_at = 0
if len(base_lines) >= 3 and base_lines[0].startswith('cat /home/slimy/AGENTS.md'):
    insert_at = 3
    if len(base_lines) > insert_at and base_lines[insert_at].strip() == '':
        insert_at += 1
preamble = _build_live_prompt_preamble(fake_attempt, '$SYN_REPO', 'syn-feature-001')
new_lines = base_lines[:insert_at] + [''] + preamble + base_lines[insert_at:]
final = '\n'.join(new_lines)
print(final)
" 2>&1)

# Check the first 3 lines are exactly the required block
LINE1=$(echo "$RESULT" | sed -n '1p')
LINE2=$(echo "$RESULT" | sed -n '2p')
LINE3=$(echo "$RESULT" | sed -n '3p')
if [ "$LINE1" = "cat /home/slimy/AGENTS.md" ] \
   && [ "$LINE2" = "cat /home/slimy/claude-progress.md" ] \
   && [ "$LINE3" = "source /home/slimy/init.sh" ]; then
  pass "live prompt still starts with exact 3-line block"
else
  fail "live prompt first 3 lines wrong: '$LINE1' / '$LINE2' / '$LINE3'"
fi

# Check the preamble is present
if echo "$RESULT" | grep -q "PHASE 2 CONTROLLED LIVE SINGLE-ATTEMPT"; then
  pass "preamble contains 'PHASE 2 CONTROLLED LIVE SINGLE-ATTEMPT'"
else
  fail "preamble missing"
fi
if echo "$RESULT" | grep -q "DO NOT push to any remote"; then
  pass "preamble contains 'DO NOT push' rule"
else
  fail "preamble missing 'DO NOT push' rule"
fi
if echo "$RESULT" | grep -q "DO NOT use git reset --hard, git clean, or git stash"; then
  pass "preamble contains 'no git reset/clean/stash' rule"
else
  fail "preamble missing git-reset rule"
fi

echo
echo "=== results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] && exit 0 || exit 1
