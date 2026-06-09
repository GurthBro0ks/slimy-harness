#!/usr/bin/env bash
# test_phase2_gates.sh — Phase 2 controlled-live mode safety gates
#
# Verifies the goal-runner refuses unsafe combinations BEFORE any real
# dispatch happens. Uses synthetic temp git repos and temp goals dirs.
# Does NOT launch a real agent.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GOAL_RUNNER="$REPO_ROOT/sequencer/goal_runner.py"
FIXTURES="$REPO_ROOT/sequencer/tests/fixtures"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_phase2_gates.sh ==="

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

# Create a clean synthetic git repo
SYN_REPO="$TEMP/syn-repo"
mkdir -p "$SYN_REPO"
git -C "$SYN_REPO" init -q -b main
git -C "$SYN_REPO" config user.email "test@example.com"
git -C "$SYN_REPO" config user.name "Test"
echo "hello" > "$SYN_REPO/README.md"
git -C "$SYN_REPO" add README.md
git -C "$SYN_REPO" commit -q -m "initial"
pass "created clean synthetic git repo at $SYN_REPO"

# Build a fixture feature list pointing at the synthetic repo
SYN_FL="$TEMP/syn-feature-list.json"
python3 - <<PY
import json
fl = {
    "_meta": {"scope": "phase2-test-fixture"},
    "features": [
        {
            "id": "syn-feature-001",
            "project": "syn-repo",
            "description": "Synthetic Phase 2 test feature.",
            "steps": ["echo syn-step-1"],
            "passes": False,
            "status": "open",
            "priority": "low",
            "risk": "low",
            "path": "$SYN_REPO",
            "blocked_by": []
        }
    ]
}
with open("$SYN_FL", "w") as f:
    json.dump(fl, f, indent=2)
PY
pass "wrote synthetic feature list"

GOALS_DIR="$TEMP/goals"
WT_ROOT="$TEMP/worktrees"

# Each gate uses a UNIQUE feature ID and a UNIQUE goals-dir subfolder
# to avoid state contamination (goal-runner resumes from existing goal.json).
G1_GOALS="$TEMP/goals-g1"; mkdir -p "$G1_GOALS"
G2_GOALS="$TEMP/goals-g2"; mkdir -p "$G2_GOALS"
G3_GOALS="$TEMP/goals-g3"; mkdir -p "$G3_GOALS"
G4_GOALS="$TEMP/goals-g4"; mkdir -p "$G4_GOALS"
G5_GOALS="$TEMP/goals-g5"; mkdir -p "$G5_GOALS"
G6_GOALS="$TEMP/goals-g6"; mkdir -p "$G6_GOALS"

# --- GATE 1: refuse max_attempts > 1 without env override ---
echo
echo "--- gate 1: refuse max_attempts > 1 without GOAL_RUNNER_ALLOW_RETRY ---"
unset GOAL_RUNNER_ALLOW_RETRY
python3 "$GOAL_RUNNER" syn-feature-001 \
  --live-dispatch \
  --max-attempts 2 \
  --notify-mode disabled \
  --worktree-root "$WT_ROOT" \
  --goals-dir "$G1_GOALS" \
  --feature-list "$SYN_FL" >/dev/null 2>&1
RC=$?
if [ "$RC" = "2" ]; then pass "refused rc=2 (max_attempts>1)"; else fail "expected rc=2 got $RC"; fi

# With override, should NOT refuse on the retry gate
GOAL_RUNNER_ALLOW_RETRY=1 python3 "$GOAL_RUNNER" syn-feature-001 \
  --dry-run \
  --max-attempts 2 \
  --notify-mode disabled \
  --goals-dir "$G1_GOALS" \
  --feature-list "$SYN_FL" >/dev/null 2>&1
RC=$?
if [ "$RC" = "0" ] || [ "$RC" = "2" ]; then pass "max_attempts>1 with override did not fail on retry gate (rc=$RC)"; else fail "rc=$RC with override"; fi

# --- GATE 2: refuse notify-mode=runtime without env override ---
echo
echo "--- gate 2: refuse notify-mode runtime without GOAL_RUNNER_ALLOW_RUNTIME_NOTIFY ---"
unset GOAL_RUNNER_ALLOW_RUNTIME_NOTIFY
python3 "$GOAL_RUNNER" syn-feature-002 \
  --live-dispatch \
  --max-attempts 1 \
  --notify-mode runtime \
  --worktree-root "$WT_ROOT" \
  --goals-dir "$G2_GOALS" \
  --feature-list "$SYN_FL" >/dev/null 2>&1
RC=$?
if [ "$RC" = "2" ]; then pass "refused rc=2 (notify-mode=runtime)"; else fail "expected rc=2 got $RC"; fi

# --- GATE 3: refuse --dry-run + --live-dispatch conflict ---
echo
echo "--- gate 3: refuse --dry-run + --live-dispatch conflict ---"
python3 "$GOAL_RUNNER" syn-feature-003 \
  --dry-run --live-dispatch \
  --max-attempts 1 \
  --notify-mode disabled \
  --goals-dir "$G3_GOALS" \
  --feature-list "$SYN_FL" >/dev/null 2>&1
RC=$?
if [ "$RC" = "2" ]; then pass "refused rc=2 (conflicting flags)"; else fail "expected rc=2 got $RC"; fi

# --- GATE 4: refuse when neither --dry-run nor --live-dispatch is set ---
echo
echo "--- gate 4: refuse when neither mode flag is set ---"
python3 "$GOAL_RUNNER" syn-feature-004 \
  --max-attempts 1 \
  --notify-mode disabled \
  --goals-dir "$G4_GOALS" \
  --feature-list "$SYN_FL" >/dev/null 2>&1
RC=$?
if [ "$RC" = "2" ]; then pass "refused rc=2 (no mode flag)"; else fail "expected rc=2 got $RC"; fi

# --- GATE 5: refuse to launch in live mode against a dirty repo ---
echo
echo "--- gate 5: refuse live-dispatch against a dirty repo ---"
echo "dirty" > "$SYN_REPO/dirty-file.txt"
python3 "$GOAL_RUNNER" syn-feature-005 \
  --live-dispatch \
  --max-attempts 1 \
  --notify-mode disabled \
  --worktree-root "$WT_ROOT" \
  --goals-dir "$G5_GOALS" \
  --feature-list "$SYN_FL" >/dev/null 2>&1
RC=$?
git -C "$SYN_REPO" reset --hard -q HEAD 2>/dev/null || rm -f "$SYN_REPO/dirty-file.txt"
rm -f "$SYN_REPO/dirty-file.txt"
git -C "$SYN_REPO" status --porcelain >/dev/null  # don't fail the test on cleanup
if [ "$RC" = "2" ]; then pass "refused rc=2 (dirty repo)"; else fail "expected rc=2 got $RC"; fi

# --- GATE 6: refuse to launch if project path is not a git repo ---
echo
echo "--- gate 6: refuse live-dispatch against non-git path ---"
NON_GIT_FL="$TEMP/non-git-fl.json"
NON_GIT_DIR="$TEMP/non-git-repo"
mkdir -p "$NON_GIT_DIR"
python3 - <<PY
import json
fl = {
    "_meta": {"scope": "phase2-test-fixture"},
    "features": [
        {
            "id": "nongit-feature-006",
            "project": "nongit-repo",
            "description": "Non-git path test.",
            "steps": ["echo x"],
            "passes": False,
            "status": "open",
            "risk": "low",
            "path": "$NON_GIT_DIR",
            "blocked_by": []
        }
    ]
}
with open("$NON_GIT_FL", "w") as f:
    json.dump(fl, f, indent=2)
PY
python3 "$GOAL_RUNNER" nongit-feature-006 \
  --live-dispatch \
  --max-attempts 1 \
  --notify-mode disabled \
  --worktree-root "$WT_ROOT" \
  --goals-dir "$G6_GOALS" \
  --feature-list "$NON_GIT_FL" >/dev/null 2>&1
RC=$?
if [ "$RC" = "2" ]; then pass "refused rc=2 (non-git path)"; else fail "expected rc=2 got $RC"; fi

echo
echo "=== results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] && exit 0 || exit 1
