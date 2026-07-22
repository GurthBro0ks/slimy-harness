#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRODUCER="$ROOT_DIR/ops/snapshot-producer.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

assert_source_token() {
  local file="$1"
  local token="$2"
  local description="$3"
  grep -F -- "$token" "$file" >/dev/null || fail "$description token changed or disappeared: $token"
}

# Pin both sides of the human-readable producer/CLI boundary. These checks are
# intentionally source-level so renaming an emitted label fails immediately.
assert_source_token "$PRODUCER" "grep -c 'schedule_type: user_crontab'" "schedule cron parser"
assert_source_token "$PRODUCER" "grep -cE 'schedule_type: (system_systemd_timer|user_systemd_timer)'" "schedule timer parser"
assert_source_token "$PRODUCER" "grep -c '^---$'" "read-only schedule entry parser"
assert_source_token "$PRODUCER" "grep -c 'session_name:'" "tmux session parser"
assert_source_token "$PRODUCER" "grep -c 'window_index:'" "tmux window parser"
assert_source_token "$PRODUCER" "grep -c 'pane_index:'" "tmux pane parser"
assert_source_token "$PRODUCER" 'started && /^machine:/' "tmux machine parser"
assert_source_token "$PRODUCER" 'started && /^session_windows:/' "tmux session window-count parser"
assert_source_token "$PRODUCER" 'started && /^session_attached:/' "tmux attached-state parser"
assert_source_token "$PRODUCER" 'started && /^notes:/' "tmux notes parser"
assert_source_token "$PRODUCER" "grep -q 'RESULT=REFUSED'" "generic refused-result parser"
assert_source_token "$PRODUCER" "grep -q 'RESULT=PASS'" "generic pass-result parser"
assert_source_token "$PRODUCER" 'grep -qi "RESULT=FAIL"' "notification failure parser"
assert_source_token "$PRODUCER" 'grep -qi "RESULT=WARN"' "notification warning parser"
assert_source_token "$PRODUCER" "grep -i 'report_url_base:'" "notification report URL parser"
assert_source_token "$PRODUCER" "grep -c '\\.sent marker'" "notification dedupe parser"
assert_source_token "$PRODUCER" 'extract_field "$plan_output" "canonical_session_name"' "workspace canonical-name parser"
assert_source_token "$PRODUCER" "grep 'COPY_ONLY:'" "workspace copy-only parser"

assert_source_token "$ROOT_DIR/ops/schedules/discover-schedules.sh" 'echo "schedule_type: $schedule_type"' "schedule type emitter"
assert_source_token "$ROOT_DIR/ops/schedules/discover-schedules.sh" 'echo "unit_or_job: $job_name"' "schedule highlight emitter"
assert_source_token "$ROOT_DIR/ops/schedules/discover-schedules.sh" 'echo "risk: $risk"' "schedule risk emitter"
assert_source_token "$ROOT_DIR/ops/schedules/discover-schedules.sh" 'echo "notes: ${notes:-none}"' "schedule record terminator"
assert_source_token "$ROOT_DIR/ops/tmux/tmux-inventory.sh" 'echo "session_name: ${session_name:-none}"' "tmux session emitter"
assert_source_token "$ROOT_DIR/ops/tmux/tmux-inventory.sh" 'echo "machine: $machine"' "tmux machine emitter"
assert_source_token "$ROOT_DIR/ops/tmux/tmux-inventory.sh" 'echo "session_windows: ${session_windows:-0}"' "tmux session window-count emitter"
assert_source_token "$ROOT_DIR/ops/tmux/tmux-inventory.sh" 'echo "session_attached: ${session_attached:-unknown}"' "tmux attached-state emitter"
assert_source_token "$ROOT_DIR/ops/tmux/tmux-inventory.sh" 'echo "window_index: ${window_index:-none}"' "tmux window emitter"
assert_source_token "$ROOT_DIR/ops/tmux/tmux-inventory.sh" 'echo "pane_index: ${pane_index:-none}"' "tmux pane emitter"
assert_source_token "$ROOT_DIR/ops/tmux/tmux-inventory.sh" 'echo "pane_current_command: ${pane_command:-unknown}"' "tmux highlight command emitter"
assert_source_token "$ROOT_DIR/ops/tmux/tmux-inventory.sh" 'echo "pane_current_path: ${pane_path:-unknown}"' "tmux record terminator"
assert_source_token "$ROOT_DIR/ops/notifications/notify-status.sh" 'log "  report_url_base: $report_base"' "notification report URL emitter"
assert_source_token "$ROOT_DIR/ops/notifications/notify-status.sh" 'log "RESULT=FAIL fails=$fail_count warnings=$warn_count"' "notification FAIL emitter"
assert_source_token "$ROOT_DIR/ops/notifications/notify-status.sh" 'log "RESULT=WARN warnings=$warn_count"' "notification WARN emitter"
assert_source_token "$ROOT_DIR/ops/notifications/notify-status.sh" 'log "RESULT=PASS warnings=0"' "notification PASS emitter"
assert_source_token "$ROOT_DIR/ops/notifications/dedupe-check.sh" '.sent marker(s):' "dedupe marker emitter"
assert_source_token "$ROOT_DIR/ops/schedules/schedule-dry-run.sh" 'echo "WOULD_RUN:' "schedule dry-run summary"
assert_source_token "$ROOT_DIR/ops/schedules/schedule-dry-run.sh" 'echo "COPY_ONLY:' "schedule safeguard summary"
assert_source_token "$ROOT_DIR/ops/schedules/schedule-dry-run.sh" 'echo "RESULT=PASS"' "schedule dry-run result"
assert_source_token "$ROOT_DIR/ops/schedules/schedule-dry-run.sh" 'echo "RESULT=REFUSED"' "schedule refused result"
assert_source_token "$ROOT_DIR/ops/workspaces/workspace-plan.sh" 'echo "canonical_session_name: $CANONICAL_SESSION"' "workspace canonical-name emitter"
assert_source_token "$ROOT_DIR/ops/workspaces/workspace-dry-run.sh" 'echo "COPY_ONLY: $(redact_text "$cmd")"' "workspace copy-only emitter"
assert_source_token "$ROOT_DIR/ops/workspaces/workspace-dry-run.sh" 'echo "RESULT=PASS"' "workspace dry-run result"
pass "human-readable CLI tokens are pinned on both sides of the parser boundary"

# Sourcing is safe: the producer's main guard prevents any snapshot writes.
source "$PRODUCER"

notification_result="WARN"
run_cli() {
  case "$*" in
    "notify status")
      printf '  report_url_base: https://harness.slimyai.xyz/reports\nRESULT=%s\n' "$notification_result"
      ;;
    "notify dry-run")
      printf 'DRY RUN - NO MESSAGE SENT\n'
      ;;
    "notify dedupe-check snapshot-producer-placeholder")
      printf 'found 1 .sent marker(s):\nRESULT=OK\n'
      ;;
    "schedule inventory")
      printf '%s\n' \
        '---' 'unit_or_job: cron-one' 'schedule_type: user_crontab' 'risk: low' 'notes: cron' \
        '---' 'unit_or_job: cron-two' 'schedule_type: user_crontab' 'risk: low' 'notes: cron' \
        '---' 'unit_or_job: user.timer' 'schedule_type: user_systemd_timer' 'risk: low' 'notes: timer' \
        '---' 'unit_or_job: system.timer' 'schedule_type: system_systemd_timer' 'risk: medium' 'notes: timer'
      ;;
    "schedule validate")
      printf 'RESULT=PASS warnings=0\n'
      ;;
    "schedule plan "*)
      printf 'schedule_id: %s\nCOPY_ONLY: --confirm\nRESULT=PASS\n' "$3"
      ;;
    "schedule dry-run "*" --action enable")
      printf 'WOULD_RUN: future enable preview for %s\nCOPY_ONLY: validate first\nRESULT=PASS\n' "$3"
      ;;
    "schedule dry-run "*" --action disable")
      printf 'WOULD_RUN: future disable preview for %s\nCOPY_ONLY: validate first\nRESULT=PASS\n' "$3"
      ;;
    "schedule run-once-dry-run "*)
      printf 'WOULD_RUN: future run-once preview for %s\nRESULT=PASS\n' "$3"
      ;;
    "tmux inventory")
      printf '%s\n' \
        '---' 'session_name: alpha' 'window_index: 0' 'window_name: shell' 'pane_index: 0' 'pane_current_command: bash' 'pane_current_path: /tmp' \
        '---' 'session_name: beta' 'window_index: 1' 'window_name: agent' 'pane_index: 1' 'pane_current_command: codex' 'pane_current_path: /home/slimy'
      ;;
    "tmux validate")
      printf 'RESULT=PASS warnings=0\n'
      ;;
    "workspace plan "*)
      printf 'canonical_session_name: ops6-%s\nRESULT=PASS\n' "$3"
      ;;
    "workspace dry-run "*)
      printf 'WOULD_RUN: tmux future preview for %s\nCOPY_ONLY: bash scripts/validate-harness.sh\nRESULT=PASS\n' "$3"
      ;;
    "workspace validate")
      printf 'RESULT=PASS warnings=0\n'
      ;;
    *)
      fail "unexpected stubbed CLI command: $*"
      ;;
  esac
}

notification_json="$(build_notification_status)"
jq -e '.status == "warn" and .reportUrl == "https://harness.slimyai.xyz/reports/sessions/" and (.dedupeState | startswith("1 dedupe marker"))' <<<"$notification_json" >/dev/null || fail "notification WARN/report/dedupe parsing changed"
notification_result="FAIL"
notification_json="$(build_notification_status)"
jq -e '.status == "error"' <<<"$notification_json" >/dev/null || fail "notification FAIL parsing changed"
pass "notification RESULT/WARN/FAIL, report URL, and dedupe parsing work"

schedule_json="$(build_schedule_inventory)"
jq -e '.summary.userCrontabCount == 2 and .summary.systemTimerCount == 2 and .summary.readOnlyTargetCount == 4 and (.summary.notes[] | contains("Schedule validate: PASS")) and (.highlights | length == 4)' <<<"$schedule_json" >/dev/null || fail "schedule count/highlight parsing changed"
pass "schedule counts, read-only count, highlights, and validation result parse correctly"

schedule_dry_json="$(build_schedule_dry_run)"
jq -e 'any(.planLines[]; contains("schedule_id:")) and any(.enablePreview[]; contains("WOULD_RUN:")) and any(.enablePreview[]; contains("COPY_ONLY:")) and any(.runOncePreview[]; contains("RESULT=PASS"))' <<<"$schedule_dry_json" >/dev/null || fail "schedule dry-run summary parsing changed"
pass "schedule plan, dry-run, safeguards, and result summaries are retained"

tmux_json="$(build_tmux_inventory)"
jq -e '.summary.sessionCount == 2 and .summary.windowCount == 2 and .summary.paneCount == 2 and (.notes[] | contains("Tmux validate: PASS")) and (.highlights | length == 2)' <<<"$tmux_json" >/dev/null || fail "tmux count/highlight parsing changed"
pass "tmux session/window/pane counts, highlights, and validation result parse correctly"

workspace_json="$(build_workspace_dry_run)"
jq -e '.canonicalSessionPreview == "ops6-harness" and any(.previewLines[]; contains("WOULD_RUN:")) and any(.copyOnlyLines[]; contains("COPY_ONLY:")) and any(.notes[]; contains("Workspace validate: PASS"))' <<<"$workspace_json" >/dev/null || fail "workspace dry-run parsing changed"
pass "workspace canonical name, preview, COPY_ONLY, and validation result parse correctly"

schedule_drys_json="$(build_schedule_dry_runs)"
schedule_registry_count="$(jq '.entries | length' "$ROOT_DIR/ops/schedules/schedule-registry.json")"
jq -e --argjson count "$schedule_registry_count" '
  length == $count and
  all(.[]; has("scheduleId") and has("targetMachine") and has("risk") and has("managedMode") and
    has("liveEnableAllowed") and has("liveDisableAllowed") and has("liveRunOnceAllowed") and
    .planResult == "PASS" and .enableResult == "PASS" and .disableResult == "PASS" and .runOnceResult == "PASS")
' <<<"$schedule_drys_json" >/dev/null || fail "registry-driven schedule expansion changed"
pass "scheduleDryRuns covers the registry dynamically with structured results"

workspace_drys_json="$(build_workspace_dry_runs)"
workspace_registry_count="$(jq '.workspaces | length' "$ROOT_DIR/ops/workspaces/workspace-registry.json")"
jq -e --argjson count "$workspace_registry_count" '
  length == $count and all(.[]; has("workspaceId") and has("targetMachine") and
    has("canonicalSessionPreview") and .planResult == "PASS" and
    any(.previewLines[]; contains("WOULD_RUN:")) and any(.copyOnlyLines[]; contains("COPY_ONLY:")))
' <<<"$workspace_drys_json" >/dev/null || fail "registry-driven workspace expansion changed"
pass "workspaceDryRuns covers the registry dynamically with structured results"

echo "snapshot producer human-readable contract PASS"
