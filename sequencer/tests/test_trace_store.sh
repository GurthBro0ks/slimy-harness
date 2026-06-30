#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TRACE_STORE="$REPO_ROOT/sequencer/trace-store.py"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

TEMP=$(mktemp -d)
cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

mkdir -p "$TEMP/proof_pass" "$TEMP/proof_warn" "$TEMP/proof_fail" "$TEMP/proof_missing"

cat > "$TEMP/proof_pass/RESULT.md" <<'EOF'
PHASE=unit-pass
RESULT=PASS
TARGET_MACHINE=NUC2
TARGET_REPO=/home/slimy/slimy-harness
VALIDATION=unit tests passed
MANUAL_QA_STATUS=pending_owner_qa
DISCORD_SENT=no
REPORT_URL=https://harness.slimyai.xyz/reports/sessions/pass.json
CHANGED_FILES=sequencer/trace-store.py;docs/AGNT_CLEANROOM_FIRST_SLICE.md
COMMIT_SHA=abc123
PUSHED=no
EOF

cat > "$TEMP/proof_warn/RESULT.md" <<'EOF'
PHASE=unit-warn
RESULT=WARN
SUMMARY=manual QA pending
DISCORD_SENT=no
SECRETS_PRINTED=no
EOF

cat > "$TEMP/proof_fail/RESULT.md" <<'EOF'
PHASE=unit-fail
RESULT=FAIL
SUMMARY=contains redacted token sk-abcdefghijklmnopqrstuvwxyz
SERVICES_RESTARTED=no
EOF

OUT="$TEMP/proof-index.json"
python3 "$TRACE_STORE" --root "$TEMP" --output "$OUT" --now "2026-06-29T00:00:00Z" >/dev/null 2>&1
RC=$?
[ "$RC" = "0" ] && pass "trace-store exits 0" || fail "trace-store rc=$RC"

python3 - "$OUT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
proofs = {item["id"]: item for item in data["proofs"]}
assert data["schema_version"] == "slimy-proof-index/v1"
assert data["proof_count"] == 4
assert proofs["proof_pass"]["result"] == "PASS"
assert proofs["proof_pass"]["manual_qa_status"] == "pending_owner_qa"
assert proofs["proof_pass"]["pushed"] is False
assert proofs["proof_warn"]["result"] == "WARN"
assert "warn_result" in proofs["proof_warn"]["risk_flags"]
assert proofs["proof_fail"]["validation_summary"] == "contains redacted token [REDACTED]"
assert "redacted_secret_like_text" in proofs["proof_fail"]["risk_flags"]
assert proofs["proof_missing"]["result_file_present"] is False
assert "missing_result_md" in proofs["proof_missing"]["risk_flags"]
print("ok")
PY
[ "$?" = "0" ] && pass "parsed PASS/WARN/FAIL/missing/redaction" || fail "index assertions failed"

OUT2="$TEMP/proof-index-2.json"
python3 "$TRACE_STORE" --root "$TEMP" --output "$OUT2" --now "2026-06-29T00:00:00Z" >/dev/null 2>&1
cmp -s "$OUT" "$OUT2"
[ "$?" = "0" ] && pass "deterministic output with fixed timestamp" || fail "output differs with fixed timestamp"

echo "=== results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] && exit 0 || exit 1
