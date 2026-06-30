#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GOAL_REGISTRY="$REPO_ROOT/sequencer/goal-registry.py"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

TEMP=$(mktemp -d)
cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

RECORD="$TEMP/goal-records.jsonl"
SUMMARY="$TEMP/goal-record-summary.json"

python3 "$GOAL_REGISTRY" append \
  --record "$RECORD" \
  --goal-id agnt-cleanroom-first-slice \
  --phase agnt-cleanroom-first-slice-proof-goal-habitat \
  --state running \
  --reason "implementation started" \
  --target-machine NUC2 \
  --target-repo "/home/slimy/slimy-harness;/opt/slimy/gh-tracker" \
  --proof-dir "$TEMP/proof" \
  --manual-qa-status pending_owner_qa \
  --now "2026-06-29T00:00:00Z" >/dev/null 2>&1
[ "$?" = "0" ] && pass "append running event" || fail "append running failed"

python3 "$GOAL_REGISTRY" append \
  --record "$RECORD" \
  --goal-id agnt-cleanroom-first-slice \
  --state warn \
  --reason "manual QA remains pending" \
  --manual-qa-status pending_owner_qa \
  --now "2026-06-29T00:05:00Z" >/dev/null 2>&1
[ "$?" = "0" ] && pass "append warn event" || fail "append warn failed"

python3 "$GOAL_REGISTRY" append --record "$RECORD" --goal-id bad --state running --reason "" >/dev/null 2>&1
[ "$?" != "0" ] && pass "empty reason rejected" || fail "empty reason accepted"

python3 "$GOAL_REGISTRY" append --record "$RECORD" --goal-id bad --state auto_pass --reason "bad state" >/dev/null 2>&1
[ "$?" != "0" ] && pass "invalid state rejected" || fail "invalid state accepted"

printf '%s\n' '{"goal_id":"bad","state":"running","reason":"bad","passes":true}' > "$TEMP/bad-passes.jsonl"
python3 "$GOAL_REGISTRY" validate --record "$TEMP/bad-passes.jsonl" >/dev/null 2>&1
[ "$?" != "0" ] && pass "passes field rejected" || fail "passes field accepted"

python3 "$GOAL_REGISTRY" validate --record "$RECORD" >/dev/null 2>&1
[ "$?" = "0" ] && pass "valid record validates" || fail "valid record rejected"

python3 "$GOAL_REGISTRY" export --record "$RECORD" --output "$SUMMARY" >/dev/null 2>&1
[ "$?" = "0" ] && pass "summary export exits 0" || fail "summary export failed"

python3 - "$SUMMARY" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["schema_version"] == "slimy-goal-record-summary/v1"
assert data["record_count"] == 2
assert data["active_count"] == 1
assert data["latest_goals"][0]["state"] == "warn"
assert data["latest_goals"][0]["reason"] == "manual QA remains pending"
assert "passes" not in data["latest_goals"][0]
print("ok")
PY
[ "$?" = "0" ] && pass "summary content is valid" || fail "summary assertions failed"

echo "=== results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] && exit 0 || exit 1
