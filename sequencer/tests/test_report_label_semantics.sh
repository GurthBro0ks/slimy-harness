#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RENDERER="$REPO_ROOT/sequencer/render-session-report-html.py"
NOTIFIER="$REPO_ROOT/sequencer/notify-proof-dir-complete.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

write_report() {
  local path="$1"
  local ran="$2"
  local passed="$3"
  local label="${4:-}"
  local details="${5:-}"
  python3 - "$path" "$ran" "$passed" "$label" "$details" <<'PY'
import json
import sys

path, ran, passed, label, details = sys.argv[1:6]
tests = {
    "ran": ran == "true",
    "passed": passed == "true",
    "details": details,
}
if label:
    tests["label"] = label

report = {
    "session_id": "2026-06-27T00:00:00Z",
    "agent": "opencode",
    "nuc": "nuc1",
    "project": "slimy-harness",
    "feature_id": "report-label-semantics-test",
    "prompt_type": "direct",
    "status": "completed" if passed == "true" else "failed",
    "summary": "Synthetic report label semantics fixture.",
    "changes": [],
    "tests": tests,
    "blockers": [],
    "recommendation": {"next_feature_id": None, "reasoning": "", "risk_notes": ""},
    "kb_learnings": [],
    "duration_minutes": 0,
    "timestamp": "2026-06-27T00:00:00Z",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
PY
}

assert_render_label() {
  local expected="$1"
  shift
  local report="$TEMP/${expected// /_}.json"
  local html="$TEMP/${expected// /_}.html"
  write_report "$report" "$@"
  python3 "$RENDERER" "$report" "$html" >/dev/null
  grep -q "<span class=\"test-label\">$expected</span>" "$html" \
    && pass "renderer label $expected" \
    || fail "renderer missing $expected"
}

assert_render_label "SMOKE ONLY" false false "SMOKE ONLY" "route smoke only"
assert_render_label "TESTS NOT RUN" false false "" "no tests run"
assert_render_label "TESTS FAIL" true false "" "unit test failure"
assert_render_label "TESTS PASS" true true "" "unit tests passed"

assert_proof_adapter_label() {
  local expected="$1"
  local validation="$2"
  local result="${3:-PASS}"
  local proof="$TEMP/proof_${expected// /_}"
  local archive="$TEMP/archive_${expected// /_}"
  mkdir -p "$proof" "$archive"
  cat > "$proof/RESULT.md" <<EOF
PHASE=report-label-semantics-fixture
RESULT=$result
VALIDATION=$validation
SUMMARY=Synthetic proof adapter fixture.
EOF
  HARNESS_KB_SESSIONS="$archive" \
  HARNESS_ENV_FILE="$TEMP/no-env-file" \
  "$NOTIFIER" --dry-run --proof-dir "$proof" --repo-path "$REPO_ROOT" --repo-name slimy-harness \
    --feature-id report-label-semantics-fixture --agent opencode >/dev/null
  local report
  report="$(find "$archive" -type f -name 'report-proof-*.json' | head -1)"
  [ -n "$report" ] || fail "proof adapter did not archive report for $expected"
  python3 - "$report" "$expected" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    report = json.load(f)
expected = sys.argv[2]
actual = report.get("tests", {}).get("label")
if actual != expected:
    raise SystemExit(f"expected {expected}, got {actual}")
PY
  pass "proof adapter label $expected"
}

assert_proof_adapter_label "SMOKE ONLY" "route_smoke_pass;logged_out_routes_checked" PASS
assert_proof_adapter_label "TESTS NOT RUN" "not_required_read_only" PASS
assert_proof_adapter_label "TESTS FAIL" "test_fail" FAIL
assert_proof_adapter_label "TESTS PASS" "lint_pass;typecheck_pass;test_pass" PASS

echo "report-label-semantics PASS"
