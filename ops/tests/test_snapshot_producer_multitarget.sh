#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRODUCER="$ROOT_DIR/ops/snapshot-producer.sh"
SCHEDULE_REGISTRY="$ROOT_DIR/ops/schedules/schedule-registry.json"
WORKSPACE_REGISTRY="$ROOT_DIR/ops/workspaces/workspace-registry.json"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

STUB="$TEMP/harness-ops-stub"
STUB_CALL_LOG="$TEMP/stub-calls.log"
export STUB_CALL_LOG

cat > "$STUB" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$STUB_CALL_LOG"

case "${1:-} ${2:-}" in
  "notify status")
    printf '  report_url_base: https://harness.slimyai.xyz/reports\nRESULT=PASS warnings=0\n'
    ;;
  "notify dry-run")
    printf 'DRY RUN - NO MESSAGE SENT\nRESULT=PASS\n'
    ;;
  "notify dedupe-check")
    printf 'found 0 .sent marker(s):\nRESULT=OK\n'
    ;;
  "schedule inventory")
    printf '%s\n' '---' 'unit_or_job: fixture.timer' 'schedule_type: user_systemd_timer' 'risk: low' 'notes: fixture'
    ;;
  "schedule validate"|"schedule controls-validate")
    printf 'RESULT=PASS warnings=0\n'
    ;;
  "schedule plan")
    schedule_id="${3:-}"
    if [[ -n "${STUB_TIMEOUT_ID:-}" && "$schedule_id" == "$STUB_TIMEOUT_ID" ]]; then
      sleep "${STUB_SLEEP_SECONDS:-3}"
    fi
    printf 'schedule_id: %s\nCOPY_ONLY: --confirm\n' "$schedule_id"
    auth_word='Bear''er'
    printf 'sensitive_fixture: %s %s\n' "$auth_word" 'fixture-redaction-value-123456'
    if [[ "${STUB_OVERSIZE:-0}" == "1" ]]; then
      printf 'oversize_fixture: '
      head -c 4096 /dev/zero | tr '\0' X
      printf '\n'
    fi
    printf 'RESULT=PASS\n'
    ;;
  "schedule dry-run")
    schedule_id="${3:-}"
    action="${5:-unknown}"
    printf 'schedule_id: %s\naction: %s\n' "$schedule_id" "$action"
    if [[ -n "${STUB_REFUSED_ID:-}" && "$schedule_id" == "$STUB_REFUSED_ID" ]]; then
      printf 'RESULT=REFUSED\n'
      exit 1
    fi
    printf 'WOULD_RUN: fixture %s preview\nCOPY_ONLY: fixture safeguard\nRESULT=PASS\n' "$action"
    ;;
  "schedule run-once-dry-run")
    schedule_id="${3:-}"
    if [[ -n "${STUB_REFUSED_ID:-}" && "$schedule_id" == "$STUB_REFUSED_ID" ]]; then
      printf 'schedule_id: %s\nRESULT=REFUSED\n' "$schedule_id"
      exit 1
    fi
    printf 'schedule_id: %s\nWOULD_RUN: fixture run-once preview\nRESULT=PASS\n' "$schedule_id"
    ;;
  "tmux inventory")
    if [[ "${STUB_NO_TMUX:-0}" == "1" ]]; then
      printf '%s\n' '---' 'machine: nuc1' 'session_name: (none)' 'session_windows: 0' 'session_attached: n/a' 'window_index: none' 'pane_index: none' 'pane_current_command: unknown' 'pane_current_path: unknown' 'notes: no sessions' 'RESULT=WARN warnings=1'
    else
      printf '%s\n' \
        '---' 'machine: nuc1' 'session_name: ops6-harness' 'session_windows: 2' 'session_attached: attached' 'window_index: 0' 'window_name: shell' 'pane_index: 0' 'pane_current_command: bash' 'pane_current_path: /fixture' 'notes: metadata-only pane inventory' \
        '---' 'machine: nuc1' 'session_name: ops6-harness' 'session_windows: 2' 'session_attached: attached' 'window_index: 1' 'window_name: tests' 'pane_index: 0' 'pane_current_command: bash' 'pane_current_path: /fixture' 'notes: metadata-only pane inventory' \
        '---' 'machine: nuc1' 'session_name: ops6-harness-similar' 'session_windows: 1' 'session_attached: detached' 'window_index: 0' 'window_name: shell' 'pane_index: 0' 'pane_current_command: bash' 'pane_current_path: /fixture' 'notes: similar name only' \
        '---' 'machine: nuc1' 'session_name: loose-session' 'session_windows: 1' 'session_attached: detached' 'window_index: 0' 'window_name: shell' 'pane_index: 0' 'pane_current_command: sh' 'pane_current_path: /fixture' 'notes: no registry association' \
        'RESULT=PASS warnings=0'
    fi
    ;;
  "tmux validate")
    printf 'RESULT=PASS warnings=0\n'
    ;;
  "workspace plan")
    workspace_id="${3:-}"
    canonical="$(jq -r --arg id "$workspace_id" '.workspaces[]? | select(.workspace_id == $id) | .canonical_session_name' "$SNAPSHOT_WORKSPACE_REGISTRY" | head -1)"
    printf 'workspace_id: %s\ncanonical_session_name: %s\nRESULT=PASS\n' "$workspace_id" "${canonical:-unknown}"
    ;;
  "workspace dry-run")
    workspace_id="${3:-}"
    printf 'workspace_id: %s\nWOULD_RUN: fixture workspace preview\nCOPY_ONLY: fixture workspace command\nRESULT=PASS\n' "$workspace_id"
    ;;
  "workspace validate")
    printf 'RESULT=PASS warnings=0\n'
    ;;
  *)
    printf 'unexpected stub command\n' >&2
    exit 2
    ;;
esac
STUB
chmod 0700 "$STUB"

run_producer() {
  local output_dir="$1"
  local schedule_registry="$2"
  local workspace_registry="$3"
  shift 3
  mkdir -p "$output_dir"
  env \
    SNAPSHOT_OUTPUT_DIR="$output_dir" \
    SNAPSHOT_HARNESS_OPS_BIN="$STUB" \
    SNAPSHOT_SCHEDULE_REGISTRY="$schedule_registry" \
    SNAPSHOT_WORKSPACE_REGISTRY="$workspace_registry" \
    "$@" \
    bash "$PRODUCER"
}

grep -F 'timeout --foreground "$RUN_CLI_TIMEOUT_SECONDS" bash "$HARNESS_OPS_BIN" "$@"' "$PRODUCER" >/dev/null || fail "CLI argv timeout contract missing"
if grep -Eq 'eval|capture-pane|\$CLI_CMD[[:space:]]+\$cmd' "$PRODUCER"; then
  fail "producer contains forbidden evaluation or pane-capture path"
fi
pass "producer uses positional argv timeout and has no eval or pane capture"

fixture_output="$TEMP/fixture-output"
start_epoch="$(date +%s)"
run_producer "$fixture_output" "$SCHEDULE_REGISTRY" "$WORKSPACE_REGISTRY" \
  RUN_CLI_TIMEOUT_SECONDS=1 \
  MAX_SNAPSHOT_BYTES=524288 \
  STUB_TIMEOUT_ID=harness-watchdog-cron \
  STUB_SLEEP_SECONDS=3 \
  STUB_REFUSED_ID=nuc2-discord-push-cron \
  > "$TEMP/fixture.stdout" 2> "$TEMP/fixture.stderr"
elapsed="$(( $(date +%s) - start_epoch ))"
[[ "$elapsed" -lt 15 ]] || fail "timed-out CLI made producer exceed bounded tolerance"

fixture="$fixture_output/latest.json"
jq -e . "$fixture" >/dev/null || fail "fixture snapshot is not valid JSON"
schedule_count="$(jq '[.entries[] | select(
  type == "object" and (.schedule_id | type == "string") and
  (.schedule_id | test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) and
  (.target_machine | type == "string") and (.risk_level | type == "string") and
  (.managed_mode | type == "string") and (.live_enable_allowed | type == "boolean") and
  (.live_disable_allowed | type == "boolean") and (.live_run_once_allowed | type == "boolean")
)] | unique_by(.schedule_id) | length' "$SCHEDULE_REGISTRY")"
workspace_count="$(jq '[.workspaces[] | select(
  type == "object" and (.workspace_id | type == "string") and
  (.workspace_id | test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) and
  (.target_machine | type == "string") and (.canonical_session_name | type == "string")
)] | unique_by(.workspace_id) | length' "$WORKSPACE_REGISTRY")"

jq -e --argjson scheduleCount "$schedule_count" --argjson workspaceCount "$workspace_count" '
  .schemaVersion == 1 and .mode == "snapshot" and
  has("source") and has("freshness") and has("redaction") and has("safety") and
  has("notificationStatus") and has("scheduleInventory") and has("scheduleDryRun") and
  has("tmuxInventory") and has("workspaceDryRun") and has("harnessReports") and
  (.scheduleDryRuns | length) == $scheduleCount and
  (.workspaceDryRuns | length) == $workspaceCount and
  ([.scheduleDryRuns[].scheduleId] | unique | length) == $scheduleCount and
  ([.workspaceDryRuns[].workspaceId] | unique | length) == $workspaceCount and
  .scheduleDryRun.sampleTarget == "harness-watchdog-cron" and
  .workspaceDryRun.canonicalSessionPreview == "ops6-harness" and
  (.safety == {readOnly:true,dryRunOnly:true,noLiveMutation:true,snapshotMode:true,backendAdapterConnected:false,shellExecutionPresent:false}) and
  (.scheduleDryRuns[] | select(.scheduleId == "harness-watchdog-cron") | .planResult) == "WARN" and
  (.scheduleDryRuns[] | select(.scheduleId == "nuc2-discord-push-cron") | .enableResult) == "REFUSED" and
  (.tmuxSessions | length) == 3 and
  (.tmuxSessions[] | select(.sessionName == "ops6-harness") | .canonical == true and .workspaceId == "harness" and .paneCount == 2 and .windowCount == 2) and
  (.tmuxSessions[] | select(.sessionName == "ops6-harness-similar") | .canonical == false and .workspaceId == null) and
  (.tmuxSessions[] | select(.sessionName == "loose-session") | .canonical == false and .workspaceId == null)
' "$fixture" >/dev/null || fail "fixture multi-target contract validation failed"

jq -e --slurpfile registry "$SCHEDULE_REGISTRY" '
  (.scheduleDryRuns | map({
    scheduleId,
    targetMachine,
    risk,
    managedMode,
    liveEnableAllowed,
    liveDisableAllowed,
    liveRunOnceAllowed
  })) == ($registry[0].entries | map({
    scheduleId: .schedule_id,
    targetMachine: .target_machine,
    risk: .risk_level,
    managedMode: .managed_mode,
    liveEnableAllowed: .live_enable_allowed,
    liveDisableAllowed: .live_disable_allowed,
    liveRunOnceAllowed: .live_run_once_allowed
  }))
' "$fixture" >/dev/null || fail "schedule order, IDs, or registry metadata changed"
jq -e --slurpfile registry "$WORKSPACE_REGISTRY" '
  (.workspaceDryRuns | map(.workspaceId)) == ($registry[0].workspaces | map(.workspace_id))
' "$fixture" >/dev/null || fail "workspace order or registry IDs changed"

if rg -n 'fixture-redaction-value-123456|capture-pane|pane_content:' "$fixture" >/dev/null; then
  fail "fixture contains unredacted sensitive text or pane-content operations"
fi
[[ "$(wc -c < "$fixture")" -le 524288 ]] || fail "valid fixture exceeds configured size"
grep -F 'CLI timed out after 1s: schedule plan harness-watchdog-cron' "$TEMP/fixture.stderr" >/dev/null || fail "timeout warning not surfaced safely"
pass "fixture snapshot is dynamic, redacted, grouped, backward-compatible, and bounded"
pass "hung CLI target timed out and remaining targets completed"

if [[ -n "${FIXTURE_SNAPSHOT_OUTPUT:-}" ]]; then
  cp "$fixture" "$FIXTURE_SNAPSHOT_OUTPUT"
fi

malformed_schedule="$TEMP/schedule-malformed.json"
malformed_workspace="$TEMP/workspace-malformed.json"
jq '
  .entries[0] |= del(.notes) |
  .entries += [
    .entries[0],
    (.entries[0] | .schedule_id = "bad;touch-injection-marker"),
    {schedule_id:"missing-target"}
  ]
' "$SCHEDULE_REGISTRY" > "$malformed_schedule"
jq '
  .workspaces[0] |= del(.notes) |
  .workspaces += [
    .workspaces[0],
    (.workspaces[0] | .workspace_id = "bad;touch-workspace-marker"),
    {workspace_id:"missing-target"}
  ]
' "$WORKSPACE_REGISTRY" > "$malformed_workspace"
: > "$STUB_CALL_LOG"
malformed_output="$TEMP/malformed-output"
run_producer "$malformed_output" "$malformed_schedule" "$malformed_workspace" \
  RUN_CLI_TIMEOUT_SECONDS=2 MAX_SNAPSHOT_BYTES=524288 \
  > "$TEMP/malformed.stdout" 2> "$TEMP/malformed.stderr"
jq -e --argjson scheduleCount "$schedule_count" --argjson workspaceCount "$workspace_count" '
  (.scheduleDryRuns | length) == $scheduleCount and
  (.workspaceDryRuns | length) == $workspaceCount
' "$malformed_output/latest.json" >/dev/null || fail "malformed/duplicate entries changed valid coverage"
if rg -n 'bad;touch|missing-target' "$STUB_CALL_LOG" >/dev/null; then
  fail "malformed ID reached CLI argv"
fi
[[ ! -e "$ROOT_DIR/touch-injection-marker" && ! -e "$ROOT_DIR/touch-workspace-marker" ]] || fail "injection marker was created"
grep -F 'Skipping duplicate schedule registry ID' "$TEMP/malformed.stderr" >/dev/null || fail "duplicate schedule warning missing"
grep -F 'Skipping schedule registry entry with invalid ID' "$TEMP/malformed.stderr" >/dev/null || fail "invalid schedule warning missing"
grep -F 'Skipping malformed workspace registry entry' "$TEMP/malformed.stderr" >/dev/null || fail "malformed workspace warning missing"
pass "duplicates, invalid IDs, missing fields, and optional notes fail safely without injection"

empty_schedule="$TEMP/schedule-empty.json"
empty_workspace="$TEMP/workspace-empty.json"
printf '%s\n' '{"entries":[]}' > "$empty_schedule"
printf '%s\n' '{"workspaces":[]}' > "$empty_workspace"
empty_output="$TEMP/empty-output"
run_producer "$empty_output" "$empty_schedule" "$empty_workspace" \
  RUN_CLI_TIMEOUT_SECONDS=2 MAX_SNAPSHOT_BYTES=524288 STUB_NO_TMUX=1 \
  > "$TEMP/empty.stdout" 2> "$TEMP/empty.stderr"
jq -e '.scheduleDryRuns == [] and .workspaceDryRuns == [] and .tmuxSessions == []' "$empty_output/latest.json" >/dev/null || fail "empty registries/no-session fixture did not remain safe"
pass "empty registries and no tmux sessions produce empty arrays"

oversize_output="$TEMP/oversize-output"
mkdir -p "$oversize_output"
printf '%s\n' '{"prior":"byte-identical"}' > "$oversize_output/latest.json"
prior_hash="$(sha256sum "$oversize_output/latest.json" | awk '{print $1}')"
if run_producer "$oversize_output" "$SCHEDULE_REGISTRY" "$WORKSPACE_REGISTRY" \
  RUN_CLI_TIMEOUT_SECONDS=2 MAX_SNAPSHOT_BYTES=16384 STUB_OVERSIZE=1 \
  > "$TEMP/oversize.stdout" 2> "$TEMP/oversize.stderr"; then
  fail "oversized snapshot unexpectedly published"
fi
after_hash="$(sha256sum "$oversize_output/latest.json" | awk '{print $1}')"
[[ "$prior_hash" == "$after_hash" ]] || fail "oversize rejection changed prior latest.json"
jq -e '.prior == "byte-identical"' "$oversize_output/latest.json" >/dev/null || fail "prior latest.json became truncated or invalid"
if ! grep -F 'exceeds configured maximum' "$TEMP/oversize.stderr" >/dev/null; then
  grep -E '\[snapshot-producer\] (ERROR|WARN):' "$TEMP/oversize.stderr" | tail -10 >&2 || true
  fail "safe oversize error missing"
fi
if rg -n 'oversize_fixture: X{32}|fixture-redaction-value-123456' "$TEMP/oversize.stderr" >/dev/null; then
  fail "oversize error printed payload content"
fi
pass "oversized final JSON is rejected and prior latest.json remains byte-identical"

if rg -n '(^|[[:space:]])(ssh|systemctl|curl)([[:space:]]|$)' "$STUB_CALL_LOG" >/dev/null; then
  fail "test stub observed an external mutation/network command"
fi
pass "tests used only fixture paths and stubbed CLI calls"

printf 'SCHEDULE_TARGET_COUNT=%s\n' "$schedule_count"
printf 'WORKSPACE_TARGET_COUNT=%s\n' "$workspace_count"
printf 'TMUX_SESSION_COUNT=3\n'
printf 'RUN_CLI_TIMEOUT_SECONDS=1\n'
printf 'MAX_SNAPSHOT_BYTES=524288\n'
printf 'snapshot producer multi-target contract PASS\n'
