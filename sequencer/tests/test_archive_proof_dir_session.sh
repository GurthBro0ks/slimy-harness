#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARCHIVER="$REPO_ROOT/sequencer/archive-proof-dir-session.sh"
NOTIFIER="$REPO_ROOT/sequencer/notify-proof-dir-complete.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

write_proof() {
  local proof="$1"
  local phase="$2"
  local result="$3"
  local validation="$4"
  local notify_mode="${5:-archive_only}"
  mkdir -p "$proof"
  cat > "$proof/RESULT.md" <<EOF
PHASE=$phase
RESULT=$result
TARGET_MACHINE=NUC1
TARGET_REPO=$REPO_ROOT
VALIDATION=$validation
MANUAL_QA_STATUS=not_required_read_only
DISCORD_SENT=no
NOTIFY_MODE=$notify_mode
DEDUPE_RESULT=not_checked
SERVICES_RESTARTED=no
CADDY_CHANGED=no
DNS_CHANGED=no
CRON_CHANGED=no
TIMER_CHANGED=no
TMUX_CHANGED=no
SECRETS_PRINTED=no
SUMMARY=Synthetic archive-only fixture for $phase.
NEXT_STEP=none
EOF
  printf 'safe machine metadata\n' > "$proof/machine.txt"
}

archive_proof() {
  local proof="$1"
  local sessions="$2"
  local index="$3"
  env -u DISCORD_HARNESS_WEBHOOK_URL \
    "$ARCHIVER" --proof-dir "$proof" --repo-path "$REPO_ROOT" \
    --repo-name slimy-harness --agent codex --sessions-dir "$sessions" \
    --index-output "$index" > "$TEMP/archive.out"
}

assert_index_shape() {
  local index="$1"
  local expected_count="$2"
  python3 - "$index" "$expected_count" <<'PY'
import datetime as dt
import json
import sys

index_path, expected_count = sys.argv[1], int(sys.argv[2])
with open(index_path, encoding="utf-8") as handle:
    index = json.load(handle)

assert index["schema_version"] == "harness-session-index/v1"
dt.datetime.fromisoformat(index["generated_at"].replace("Z", "+00:00"))
assert index["generated_by"] == "sequencer/export-session-index.sh"
assert index["session_count"] == expected_count
assert len(index["sessions"]) == expected_count
for session in index["sessions"]:
    dt.datetime.fromisoformat(session["created_at"].replace("Z", "+00:00"))
    assert session["report_url"], session
PY
}

sessions="$TEMP/sessions"
index="$TEMP/sessions/harness-session-index.json"
mkdir -p "$sessions"

proof_one="$TEMP/proof_archive_only_20260627T000000Z"
write_proof "$proof_one" "archive-only-fixture" "PASS" "lint_pass;typecheck_pass;test_pass"
archive_proof "$proof_one" "$sessions" "$index"
report_count="$(find "$sessions" -maxdepth 1 -type f -name 'report-proof-*.json' | wc -l | tr -d ' ')"
[[ "$report_count" == "1" ]] || fail "expected one archived report, got $report_count"
assert_index_shape "$index" 1
pass "archive-only works without Discord env"

archive_proof "$proof_one" "$sessions" "$index"
report_count="$(find "$sessions" -maxdepth 1 -type f -name 'report-proof-*.json' | wc -l | tr -d ' ')"
[[ "$report_count" == "1" ]] || fail "archive-only duplicated report"
assert_index_shape "$index" 1
pass "archive-only is idempotent"

proof_smoke="$TEMP/proof_smoke_only_20260627T000001Z"
write_proof "$proof_smoke" "archive-smoke-fixture" "PASS" "route_smoke_pass;logged_out_routes_checked"
archive_proof "$proof_smoke" "$sessions" "$index"
proof_not_run="$TEMP/proof_tests_not_run_20260627T000002Z"
write_proof "$proof_not_run" "archive-tests-not-run-fixture" "PASS" "not_required_read_only"
archive_proof "$proof_not_run" "$sessions" "$index"
assert_index_shape "$index" 3
python3 - "$sessions" <<'PY'
import json
import sys
from pathlib import Path

labels = {}
for report_path in Path(sys.argv[1]).glob("report-proof-*.json"):
    data = json.loads(report_path.read_text())
    labels[data["feature_id"]] = data["tests"]["label"]

assert labels["archive-smoke-fixture"] == "SMOKE ONLY", labels
assert labels["archive-tests-not-run-fixture"] == "TESTS NOT RUN", labels
PY
pass "report label semantics preserved"

disabled_sessions="$TEMP/disabled-sessions"
disabled_index="$TEMP/disabled-sessions/harness-session-index.json"
disabled_proof="$TEMP/proof_disabled_notify_20260627T000003Z"
mkdir -p "$disabled_sessions"
write_proof "$disabled_proof" "disabled-notify-fixture" "PASS" "lint_pass;test_pass" "disabled"
HARNESS_KB_SESSIONS="$disabled_sessions" \
HARNESS_SESSION_INDEX_OUTPUT="$disabled_index" \
HARNESS_ENV_FILE="$TEMP/no-harness-env" \
  "$NOTIFIER" --proof-dir "$disabled_proof" --repo-path "$REPO_ROOT" \
  --repo-name slimy-harness --feature-id disabled-notify-fixture --agent codex \
  > "$TEMP/disabled.out" 2>"$TEMP/disabled.err"
assert_index_shape "$disabled_index" 1
pass "disabled/no-webhook notifier path still archives and indexes"

failure_sessions="$TEMP/failure-sessions"
failure_index="$TEMP/failure-sessions/harness-session-index.json"
failure_proof="$TEMP/proof_send_failure_20260627T000004Z"
failure_env="$TEMP/fake-harness-env"
mkdir -p "$failure_sessions"
write_proof "$failure_proof" "send-failure-fixture" "PASS" "lint_pass;test_pass" "runtime"
printf '%s\n' 'DISCORD_HARNESS_WEBHOOK_URL=http://127.0.0.1:9/not-discord' > "$failure_env"
set +e
HARNESS_KB_SESSIONS="$failure_sessions" \
HARNESS_SESSION_INDEX_OUTPUT="$failure_index" \
HARNESS_ENV_FILE="$failure_env" \
  "$NOTIFIER" --proof-dir "$failure_proof" --repo-path "$REPO_ROOT" \
  --repo-name slimy-harness --feature-id send-failure-fixture --agent codex \
  --force > "$TEMP/failure.out" 2>"$TEMP/failure.err"
failure_rc=$?
set -e
[[ "$failure_rc" -ne 0 ]] || fail "expected local send failure to exit non-zero"
assert_index_shape "$failure_index" 1
failure_report="$(find "$failure_sessions" -maxdepth 1 -type f -name 'report-proof-*.json' | head -1)"
[[ -n "$failure_report" ]] || fail "send failure skipped archive metadata"
pass "send failure leaves archive and index metadata intact"

encoded="$(python3 - "$sessions" "$disabled_sessions" "$failure_sessions" <<'PY'
import json
import sys
from pathlib import Path

payload = []
for directory in sys.argv[1:]:
    for report_path in Path(directory).glob("*.json"):
        payload.append(json.loads(report_path.read_text()))
print(json.dumps(payload, sort_keys=True))
PY
)"
if echo "$encoded" | grep -Ei 'api/webhooks|not-discord|TOKEN=|SECRET=|PASSWORD=' >/dev/null; then
  fail "generated archive/index contains forbidden secret-shaped content"
fi
pass "generated archive/index safety scan"

echo "archive-proof-dir-session PASS"
