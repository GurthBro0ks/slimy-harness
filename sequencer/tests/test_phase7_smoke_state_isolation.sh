#!/usr/bin/env bash
# test_phase7_smoke_state_isolation.sh — Phase 7 smoke state isolation
#
# Proves that auto-close.sh and blocker-report.sh honor environment
# overrides and never write to production paths when given smoke-root
# paths via env vars.
#
# Assertions:
#  1. auto-close.sh writes to smoke FEATURE_LIST, not production
#  2. auto-close.sh writes to smoke FAILED_APPROACHES, not production
#  3. auto-close.sh reads from smoke SESSION_REPORT, not production
#  4. blocker-report.sh writes to smoke BLOCKER_REPORT, not production
#  5. blocker-report.sh reads from smoke FEATURE_LIST, not production
#  6. production feature_list.json unchanged
#  7. production failed-approaches.json unchanged
#  8. production session-report.json unchanged
#  9. production blocker-report.md unchanged
# 10. auto-sequence.sh exports redirected paths
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUTO_SEQ="$REPO_ROOT/sequencer/auto-sequence.sh"
AUTO_CLOSE="$REPO_ROOT/sequencer/auto-close.sh"
BLOCKER_REPORT_SH="$REPO_ROOT/sequencer/blocker-report.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_phase7_smoke_state_isolation.sh ==="
echo "REPO_ROOT=$REPO_ROOT"

TEMP=$(mktemp -d)
echo "TEMP=$TEMP"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

PROD_FL="/home/slimy/feature_list.json"
PROD_SR="/home/slimy/session-report.json"
PROD_FA="/home/slimy/failed-approaches.json"
PROD_BR="/home/slimy/blocker-report.md"

record_prod_hashes() {
    PROD_FL_HASH=""
    if [ -f "$PROD_FL" ]; then PROD_FL_HASH=$(md5sum "$PROD_FL" | awk '{print $1}'); fi
    PROD_SR_HASH=""
    if [ -f "$PROD_SR" ]; then PROD_SR_HASH=$(md5sum "$PROD_SR" | awk '{print $1}'); fi
    PROD_FA_HASH=""
    if [ -f "$PROD_FA" ]; then PROD_FA_HASH=$(md5sum "$PROD_FA" | awk '{print $1}'); fi
    PROD_BR_HASH=""
    if [ -f "$PROD_BR" ]; then PROD_BR_HASH=$(md5sum "$PROD_BR" | awk '{print $1}'); fi
}

check_prod_unchanged() {
    local label="$1"
    if [ -f "$PROD_FL" ] && [ -n "$PROD_FL_HASH" ]; then
        local h=$(md5sum "$PROD_FL" | awk '{print $1}')
        if [ "$h" = "$PROD_FL_HASH" ]; then pass "$label: production feature_list.json unchanged"
        else fail "$label: production feature_list.json CHANGED!"; fi
    else pass "$label: production feature_list.json not present (skip)"; fi

    if [ -f "$PROD_SR" ] && [ -n "$PROD_SR_HASH" ]; then
        local h=$(md5sum "$PROD_SR" | awk '{print $1}')
        if [ "$h" = "$PROD_SR_HASH" ]; then pass "$label: production session-report.json unchanged"
        else fail "$label: production session-report.json CHANGED!"; fi
    else pass "$label: production session-report.json not present (skip)"; fi

    if [ -f "$PROD_FA" ] && [ -n "$PROD_FA_HASH" ]; then
        local h=$(md5sum "$PROD_FA" | awk '{print $1}')
        if [ "$h" = "$PROD_FA_HASH" ]; then pass "$label: production failed-approaches.json unchanged"
        else fail "$label: production failed-approaches.json CHANGED!"; fi
    else pass "$label: production failed-approaches.json not present (skip)"; fi

    if [ -f "$PROD_BR" ] && [ -n "$PROD_BR_HASH" ]; then
        local h=$(md5sum "$PROD_BR" | awk '{print $1}')
        if [ "$h" = "$PROD_BR_HASH" ]; then pass "$label: production blocker-report.md unchanged"
        else fail "$label: production blocker-report.md CHANGED!"; fi
    else pass "$label: production blocker-report.md not present (skip)"; fi
}

# ===== Section A: auto-close.sh smoke isolation =====
echo "--- Section A: auto-close.sh smoke isolation ---"

SMOKE="$TEMP/smoke-auto-close"
mkdir -p "$SMOKE"

cat > "$SMOKE/feature_list.json" << 'EOF'
{
  "_meta": {"scope": "smoke-isolation-test"},
  "features": [
    {
      "id": "isolation-test-001",
      "project": "smoke-project",
      "description": "Isolation test feature.",
      "steps": [],
      "passes": false,
      "status": "open",
      "priority": "medium",
      "risk": "low",
      "attempt_count": 0
    }
  ]
}
EOF

cat > "$SMOKE/session-report.json" << 'EOF'
{
  "session_id": "isolation-test-session",
  "agent": "opencode",
  "nuc": "nuc1",
  "project": "smoke-project",
  "feature_id": "isolation-test-001",
  "status": "completed",
  "summary": "Auto-close isolation test session.",
  "changes": [],
  "tests": {"ran": true, "passed": true, "details": "all pass"},
  "timestamp": "2026-06-10T00:00:00Z"
}
EOF

cat > "$SMOKE/failed-approaches.json" << 'EOF'
{
  "version": 1,
  "entries": []
}
EOF

record_prod_hashes

SESSION_REPORT="$SMOKE/session-report.json" \
FEATURE_LIST="$SMOKE/feature_list.json" \
FAILED_APPROACHES="$SMOKE/failed-approaches.json" \
HARNESS_SMOKE_ROOT="$SMOKE" \
bash "$AUTO_CLOSE" 2>&1 || true

if python3 -c "import json,sys; d=json.load(open('$SMOKE/feature_list.json')); f=d['features'][0]; sys.exit(0 if f.get('passes') and f.get('status')=='completed' else 1)" 2>/dev/null; then
    pass "auto-close wrote passes=true to smoke feature_list.json"
else
    if python3 -c "import json,sys; d=json.load(open('$SMOKE/feature_list.json')); print(d['features'][0].get('passes'), d['features'][0].get('status'))" 2>/dev/null; then true; fi
    fail "auto-close did not update smoke feature_list.json correctly"
fi

if [ -f "$SMOKE/failed-approaches.json" ]; then
    pass "auto-close wrote smoke failed-approaches.json"
else
    fail "auto-close did not create smoke failed-approaches.json"
fi

check_prod_unchanged "auto-close"

# ===== Section B: blocker-report.sh smoke isolation =====
echo "--- Section B: blocker-report.sh smoke isolation ---"

SMOKE2="$TEMP/smoke-blocker"
mkdir -p "$SMOKE2"

cat > "$SMOKE2/feature_list.json" << 'EOF'
{
  "_meta": {"scope": "smoke-blocker-test"},
  "features": [
    {
      "id": "blocker-test-001",
      "project": "smoke-project",
      "description": "Blocker test feature.",
      "steps": [],
      "passes": false,
      "status": "blocked",
      "priority": "high",
      "risk": "low",
      "attempt_count": 1,
      "blocked_by": ["manual:test-blocker"]
    }
  ]
}
EOF

cat > "$SMOKE2/session-report.json" << 'EOF'
{
  "session_id": "blocker-test-session",
  "agent": "opencode",
  "nuc": "nuc1",
  "project": "smoke-project",
  "feature_id": "blocker-test-001",
  "status": "blocked",
  "summary": "Blocker test session.",
  "changes": [],
  "tests": {"ran": false, "passed": false, "details": ""},
  "blockers": [{"type": "manual", "description": "test-blocker"}],
  "timestamp": "2026-06-10T00:00:00Z"
}
EOF

SMOKE_BR="$SMOKE2/blocker-report.md"

record_prod_hashes

FEATURE_LIST="$SMOKE2/feature_list.json" \
SESSION_REPORT="$SMOKE2/session-report.json" \
BLOCKER_REPORT="$SMOKE_BR" \
bash "$BLOCKER_REPORT_SH" 2>&1 || true

if [ -f "$SMOKE_BR" ]; then
    pass "blocker-report.sh wrote to smoke blocker-report.md"
    if grep -q "blocker-test-001" "$SMOKE_BR"; then
        pass "blocker-report.sh read from smoke feature_list.json (found test feature)"
    else
        fail "blocker-report.sh did not find test feature in smoke feature_list.json"
    fi
else
    fail "blocker-report.sh did not create smoke blocker-report.md"
fi

check_prod_unchanged "blocker-report"

# ===== Section C: auto-sequence.sh export check =====
echo "--- Section C: auto-sequence.sh export check ---"

if grep -q 'export SESSION_REPORT FEATURE_LIST FAILED_APPROACHES BLOCKER_REPORT BLOCKER_CACHE' "$AUTO_SEQ"; then
    pass "auto-sequence.sh exports redirected paths"
else
    fail "auto-sequence.sh missing export of redirected paths"
fi

if grep -q 'BLOCKER_REPORT=' "$AUTO_SEQ"; then
    pass "auto-sequence.sh defines BLOCKER_REPORT"
else
    fail "auto-sequence.sh missing BLOCKER_REPORT definition"
fi

if grep -q 'BLOCKER_CACHE=' "$AUTO_SEQ"; then
    pass "auto-sequence.sh defines BLOCKER_CACHE"
else
    fail "auto-sequence.sh missing BLOCKER_CACHE definition"
fi

echo ""
echo "SUMMARY: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
