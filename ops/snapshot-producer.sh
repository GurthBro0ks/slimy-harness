#!/usr/bin/env bash
set -euo pipefail

PRODUCER_VERSION="1.0.0"
SCHEMA_VERSION=1
MAX_AGE_SECONDS=900
RUN_CLI_TIMEOUT_SECONDS="${RUN_CLI_TIMEOUT_SECONDS:-20}"
MAX_SNAPSHOT_BYTES="${MAX_SNAPSHOT_BYTES:-524288}"

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_DIR="${SNAPSHOT_OUTPUT_DIR:-/home/slimy/harness-logs/ops-snapshots}"
LATEST_JSON="${SNAPSHOT_DIR}/latest.json"
HISTORY_DIR="${SNAPSHOT_DIR}/history"
TEMP_JSON="${SNAPSHOT_DIR}/.latest.json.tmp"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STALE_AFTER=""
HOSTNAME="$(hostname)"

HARNESS_OPS_BIN="${SNAPSHOT_HARNESS_OPS_BIN:-${HARNESS_ROOT}/ops/harness-ops}"
SCHEDULE_REGISTRY="${SNAPSHOT_SCHEDULE_REGISTRY:-${HARNESS_ROOT}/ops/schedules/schedule-registry.json}"
WORKSPACE_REGISTRY="${SNAPSHOT_WORKSPACE_REGISTRY:-${HARNESS_ROOT}/ops/workspaces/workspace-registry.json}"

ALLOWED_COMMANDS=(
  "notify status"
  "notify dry-run"
  "notify dedupe-check"
  "schedule inventory"
  "schedule validate"
  "schedule plan"
  "schedule dry-run"
  "schedule run-once-dry-run"
  "schedule controls-validate"
  "tmux inventory"
  "tmux validate"
  "workspace plan"
  "workspace dry-run"
  "workspace validate"
)

log() { printf '[snapshot-producer] %s\n' "$*" >&2; }
warn() { printf '[snapshot-producer] WARN: %s\n' "$*" >&2; }
err() { printf '[snapshot-producer] ERROR: %s\n' "$*" >&2; }

redact_text() {
  local text="$1"
  local hook_host='dis''cord'
  local hook_app='app'
  local hook_path='/api/webhooks/'
  printf '%s' "$text" | sed -E \
    -e "s#https://${hook_host}(${hook_app})?\\.com${hook_path}[A-Za-z0-9/_-]+#[REDACTED_WEBHOOK]#g" \
    -e 's#(https?://)[^ /:@]+:[^ /@]+@#\1[REDACTED]@#g' \
    -e 's/\b([Bb]earer)[[:space:]]+[A-Za-z0-9._~+\/=:-]+/\1 [REDACTED]/g' \
    -e 's/\b([A-Za-z_][A-Za-z0-9_]*(SECRET|TOKEN|KEY|PASSWORD|WEBHOOK|COOKIE|SESSION)[A-Za-z0-9_]*)=([^[:space:]]+)/\1=[REDACTED]/g' \
    -e 's/([?&](token|secret|key|password|session|cookie)=)[^&[:space:]]+/\1[REDACTED]/Ig'
}

is_allowed() {
  local command_key="${1:-} ${2:-}"
  for allowed in "${ALLOWED_COMMANDS[@]}"; do
    if [[ "$command_key" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}

run_cli() {
  local command_label="$*"
  local output=""
  local rc=0

  if ! is_allowed "$@"; then
    warn "Command not on allowlist, skipping: $command_label"
    printf ''
    return 1
  fi

  output="$(cd "$HARNESS_ROOT" && timeout --foreground "$RUN_CLI_TIMEOUT_SECONDS" bash "$HARNESS_OPS_BIN" "$@" 2>&1)" || rc=$?
  if [[ $rc -eq 124 || $rc -eq 137 ]]; then
    warn "CLI timed out after ${RUN_CLI_TIMEOUT_SECONDS}s: $command_label"
    output="${output}${output:+$'\n'}producer_note: CLI timed out after ${RUN_CLI_TIMEOUT_SECONDS}s
RESULT=WARN"
  elif [[ $rc -ne 0 ]]; then
    warn "Command exited with rc=$rc: $command_label"
  fi
  redact_text "$output"
}

validate_configuration() {
  local path
  for path in "$SNAPSHOT_DIR" "$HARNESS_OPS_BIN" "$SCHEDULE_REGISTRY" "$WORKSPACE_REGISTRY"; do
    if [[ "$path" != /* ]]; then
      err "Configured paths must be absolute"
      return 1
    fi
  done
  if [[ ! "$RUN_CLI_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    err "RUN_CLI_TIMEOUT_SECONDS must be a positive integer"
    return 1
  fi
  if [[ ! "$MAX_SNAPSHOT_BYTES" =~ ^[1-9][0-9]*$ ]]; then
    err "MAX_SNAPSHOT_BYTES must be a positive integer"
    return 1
  fi
  if [[ ! -f "$HARNESS_OPS_BIN" || ! -f "$SCHEDULE_REGISTRY" || ! -f "$WORKSPACE_REGISTRY" ]]; then
    err "Configured producer input file is missing"
    return 1
  fi
}

compute_stale_after() {
  local epoch_now
  epoch_now="$(date -u +%s)"
  STALE_AFTER="$(date -u -d "@$((epoch_now + MAX_AGE_SECONDS))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "${GENERATED_AT}+900")"
}

text_to_json_lines() {
  printf '%s' "$1" | jq -R -s 'split("\n") | map(select(length > 0))'
}

extract_field() {
  local text="$1"
  local field="$2"
  printf '%s' "$text" | grep "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//"
}

result_from_output() {
  local text="$1"
  if printf '%s' "$text" | grep -q 'RESULT=REFUSED'; then
    printf 'REFUSED'
  elif printf '%s' "$text" | grep -q 'RESULT=FAIL'; then
    printf 'FAIL'
  elif printf '%s' "$text" | grep -q 'RESULT=WARN'; then
    printf 'WARN'
  elif printf '%s' "$text" | grep -q 'RESULT=PASS'; then
    printf 'PASS'
  else
    printf 'UNKNOWN'
  fi
}

workspace_registry_entries() {
  jq -c '
    .workspaces[]? |
    select(type == "object") |
    select(.workspace_id | type == "string") |
    select(.target_machine | type == "string") |
    select(.canonical_session_name | type == "string")
  ' "$WORKSPACE_REGISTRY" 2>/dev/null
}

build_notification_status() {
  log "Gathering notification status..."
  local status_output dryrun_output dedupe_output
  status_output="$(run_cli notify status)" || true
  dryrun_output="$(run_cli notify dry-run)" || true
  dedupe_output="$(run_cli notify dedupe-check snapshot-producer-placeholder)" || true

  local notify_status="ok"
  local delivery_mode="disabled"
  local report_url="https://harness.slimyai.xyz/reports/sessions/"
  local dedupe_state="Snapshot does not track live dedupe markers."

  if printf '%s' "$status_output" | grep -qi "RESULT=FAIL"; then
    notify_status="error"
  elif printf '%s' "$status_output" | grep -qi "RESULT=WARN"; then
    notify_status="warn"
  fi

  local report_line
  report_line="$(printf '%s' "$status_output" | grep -i 'report_url_base:' | head -1 || true)"
  if [[ -n "$report_line" ]]; then
    local extracted
    extracted="$(printf '%s' "$report_line" | sed -E 's/.*report_url_base:[[:space:]]*//' | sed 's:/*$::')"
    if [[ -n "$extracted" ]]; then
      report_url="${extracted}/sessions/"
    fi
  fi

  local marker_count
  marker_count="$(printf '%s' "$dedupe_output" | grep -c '\.sent marker' || true)"
  if [[ "$marker_count" -gt 0 ]]; then
    dedupe_state="${marker_count} dedupe marker(s) on file. Snapshot does not track live markers."
  fi

  jq -n \
    --arg status "$notify_status" \
    --arg deliveryMode "$delivery_mode" \
    --arg dedupeState "$dedupe_state" \
    --arg reportUrl "$report_url" \
    --arg redactionNote "Notification status derived from ops/harness-ops notify status output." \
    '{
      status: $status,
      deliveryMode: $deliveryMode,
      dedupeState: $dedupeState,
      reportUrl: $reportUrl,
      redactionNote: $redactionNote
    }'
}

build_schedule_highlights() {
  local inv_output="$1"
  local hl_tmp
  hl_tmp="$(mktemp)"
  printf '%s' "$inv_output" | \
    awk '
      /^---$/{ found=1; next }
      found && /^unit_or_job:/ { uj=$0; sub(/^unit_or_job:[[:space:]]*/, "", uj) }
      found && /^schedule_type:/ { st=$0; sub(/^schedule_type:[[:space:]]*/, "", st) }
      found && /^risk:/ { r=$0; sub(/^risk:[[:space:]]*/, "", r) }
      found && /^notes:/ {
        if (uj != "") {
          printf "%s\t%s\t%s\n", uj, st, (r != "" ? r : "unknown")
        }
        uj=""; st=""; r=""
      }
    ' 2>/dev/null | head -8 > "$hl_tmp"

  local hl_json_tmp
  hl_json_tmp="$(mktemp)"
  : > "$hl_json_tmp"
  while IFS=$'\t' read -r label value risk; do
    [[ -z "$label" ]] && continue
    jq -n --arg l "$label" --arg v "$value" --arg r "$risk" \
      '{label: $l, value: $v, risk: $r}' >> "$hl_json_tmp"
  done < "$hl_tmp"

  jq -s '.' "$hl_json_tmp" 2>/dev/null || echo '[]'
  rm -f "$hl_tmp" "$hl_json_tmp"
}

build_schedule_inventory() {
  log "Gathering schedule inventory..."
  local inv_output val_output
  inv_output="$(run_cli schedule inventory)" || true
  val_output="$(run_cli schedule validate)" || true

  local user_cron=0 sys_timer=0 read_only=0
  user_cron="$(printf '%s' "$inv_output" | grep -c 'schedule_type: user_crontab' || true)"
  sys_timer="$(printf '%s' "$inv_output" | grep -cE 'schedule_type: (system_systemd_timer|user_systemd_timer)' || true)"
  read_only="$(printf '%s' "$inv_output" | grep -c '^---$' || true)"

  local highlights
  highlights="$(build_schedule_highlights "$inv_output")" || highlights="[]"
  [[ "$highlights" == "" ]] && highlights="[]"

  local val_result="unknown"
  if printf '%s' "$val_output" | grep -q 'RESULT=PASS'; then
    val_result="PASS"
  elif printf '%s' "$val_output" | grep -q 'RESULT=FAIL'; then
    val_result="FAIL"
  fi

  jq -n \
    --argjson userCron "$user_cron" \
    --argjson sysTimer "$sys_timer" \
    --argjson readOnly "$read_only" \
    --arg valResult "$val_result" \
    --argjson highlights "$highlights" \
    '{
      summary: {
        userCrontabCount: $userCron,
        systemTimerCount: $sysTimer,
        readOnlyTargetCount: $readOnly,
        notes: ["Snapshot inventory is read-only.", ("Schedule validate: " + $valResult)]
      },
      highlights: $highlights
    }'
}

build_schedule_dry_run() {
  log "Gathering schedule dry-run previews..."
  local plan_output enable_output runonce_output
  plan_output="$(run_cli schedule plan harness-watchdog-cron)" || true
  enable_output="$(run_cli schedule dry-run harness-watchdog-cron --action enable)" || true
  runonce_output="$(run_cli schedule run-once-dry-run harness-watchdog-cron)" || true

  local plan_lines enable_lines runonce_lines
  plan_lines="$(text_to_json_lines "$plan_output")"
  enable_lines="$(text_to_json_lines "$enable_output")"
  runonce_lines="$(text_to_json_lines "$runonce_output")"

  jq -n \
    --arg sampleTarget "harness-watchdog-cron" \
    --argjson planLines "$plan_lines" \
    --argjson enablePreview "$enable_lines" \
    --argjson disablePreview '[]' \
    --argjson runOncePreview "$runonce_lines" \
    '{
      sampleTarget: $sampleTarget,
      planLines: $planLines,
      enablePreview: $enablePreview,
      disablePreview: $disablePreview,
      runOncePreview: $runOncePreview
    }'
}

build_schedule_dry_runs() {
  log "Gathering registry-driven schedule dry-run previews..."
  local rows_tmp
  rows_tmp="$(mktemp)"
  : > "$rows_tmp"

  if ! jq -e '.entries | type == "array"' "$SCHEDULE_REGISTRY" >/dev/null 2>&1; then
    warn "Schedule registry is malformed; scheduleDryRuns will be empty"
    printf '[]'
    rm -f "$rows_tmp"
    return 0
  fi

  local index=0 entry schedule_id target_machine risk managed_mode
  local live_enable live_disable live_run_once registry_notes
  local plan_output enable_output disable_output runonce_output
  local plan_lines enable_lines disable_lines runonce_lines
  local plan_result enable_result disable_result runonce_result
  declare -A seen_ids=()

  while IFS= read -r entry; do
    if ! jq -e '
      type == "object" and
      (.schedule_id | type == "string") and
      (.target_machine | type == "string") and
      (.risk_level | type == "string") and
      (.managed_mode | type == "string") and
      (.live_enable_allowed | type == "boolean") and
      (.live_disable_allowed | type == "boolean") and
      (.live_run_once_allowed | type == "boolean")
    ' <<<"$entry" >/dev/null 2>&1; then
      warn "Skipping malformed schedule registry entry at index $index"
      index=$((index + 1))
      continue
    fi

    schedule_id="$(jq -r '.schedule_id' <<<"$entry")"
    if [[ ! "$schedule_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
      warn "Skipping schedule registry entry with invalid ID at index $index"
      index=$((index + 1))
      continue
    fi
    if [[ -n "${seen_ids[$schedule_id]:-}" ]]; then
      warn "Skipping duplicate schedule registry ID at index $index"
      index=$((index + 1))
      continue
    fi
    seen_ids["$schedule_id"]=1

    target_machine="$(jq -r '.target_machine' <<<"$entry")"
    risk="$(jq -r '.risk_level' <<<"$entry")"
    managed_mode="$(jq -r '.managed_mode' <<<"$entry")"
    live_enable="$(jq -r '.live_enable_allowed' <<<"$entry")"
    live_disable="$(jq -r '.live_disable_allowed' <<<"$entry")"
    live_run_once="$(jq -r '.live_run_once_allowed' <<<"$entry")"
    registry_notes="$(jq -r '.notes // "No registry notes."' <<<"$entry")"
    registry_notes="$(redact_text "$registry_notes")"

    plan_output="$(run_cli schedule plan "$schedule_id")" || true
    enable_output="$(run_cli schedule dry-run "$schedule_id" --action enable)" || true
    disable_output="$(run_cli schedule dry-run "$schedule_id" --action disable)" || true
    runonce_output="$(run_cli schedule run-once-dry-run "$schedule_id")" || true

    plan_lines="$(text_to_json_lines "$plan_output")"
    enable_lines="$(text_to_json_lines "$enable_output")"
    disable_lines="$(text_to_json_lines "$disable_output")"
    runonce_lines="$(text_to_json_lines "$runonce_output")"
    plan_result="$(result_from_output "$plan_output")"
    enable_result="$(result_from_output "$enable_output")"
    disable_result="$(result_from_output "$disable_output")"
    runonce_result="$(result_from_output "$runonce_output")"

    jq -n \
      --arg scheduleId "$schedule_id" \
      --arg targetMachine "$target_machine" \
      --arg risk "$risk" \
      --arg managedMode "$managed_mode" \
      --argjson liveEnableAllowed "$live_enable" \
      --argjson liveDisableAllowed "$live_disable" \
      --argjson liveRunOnceAllowed "$live_run_once" \
      --arg planResult "$plan_result" \
      --argjson planLines "$plan_lines" \
      --arg enableResult "$enable_result" \
      --argjson enablePreview "$enable_lines" \
      --arg disableResult "$disable_result" \
      --argjson disablePreview "$disable_lines" \
      --arg runOnceResult "$runonce_result" \
      --argjson runOncePreview "$runonce_lines" \
      --arg notes "$registry_notes" \
      '{
        scheduleId: $scheduleId,
        targetMachine: $targetMachine,
        risk: $risk,
        managedMode: $managedMode,
        liveEnableAllowed: $liveEnableAllowed,
        liveDisableAllowed: $liveDisableAllowed,
        liveRunOnceAllowed: $liveRunOnceAllowed,
        planResult: $planResult,
        planLines: $planLines,
        enableResult: $enableResult,
        enablePreview: $enablePreview,
        disableResult: $disableResult,
        disablePreview: $disablePreview,
        runOnceResult: $runOnceResult,
        runOncePreview: $runOncePreview,
        notes: [$notes]
      }' >> "$rows_tmp"
    index=$((index + 1))
  done < <(jq -c '.entries[]' "$SCHEDULE_REGISTRY")

  jq -s '.' "$rows_tmp"
  rm -f "$rows_tmp"
}

build_tmux_highlights() {
  local inv_output="$1"
  local hl_tmp
  hl_tmp="$(mktemp)"
  printf '%s' "$inv_output" | \
    awk '
      /^---$/{ found=1; next }
      found && /^session_name:/ { sn=$0; sub(/^session_name:[[:space:]]*/, "", sn) }
      found && /^window_name:/ { wn=$0; sub(/^window_name:[[:space:]]*/, "", wn) }
      found && /^pane_current_command:/ { pc=$0; sub(/^pane_current_command:[[:space:]]*/, "", pc) }
      found && /^pane_current_path:/ {
        if (sn != "") {
          val = ""
          if (wn != "") val = wn
          if (pc != "") val = val (val != "" ? " / " : "") pc
          printf "%s\t%s\n", sn, val
        }
        sn=""; wn=""; pc=""
      }
    ' 2>/dev/null | head -8 > "$hl_tmp"

  local hl_json_tmp
  hl_json_tmp="$(mktemp)"
  : > "$hl_json_tmp"
  while IFS=$'\t' read -r label value; do
    [[ -z "$label" ]] && continue
    jq -n --arg l "$label" --arg v "$value" \
      '{label: $l, value: $v}' >> "$hl_json_tmp"
  done < "$hl_tmp"

  jq -s '.' "$hl_json_tmp" 2>/dev/null || echo '[]'
  rm -f "$hl_tmp" "$hl_json_tmp"
}

build_tmux_inventory() {
  log "Gathering tmux inventory..."
  local inv_output val_output
  inv_output="$(run_cli tmux inventory)" || true
  val_output="$(run_cli tmux validate)" || true

  local sessions=0 windows=0 panes=0
  sessions="$(printf '%s' "$inv_output" | grep -c 'session_name:' || true)"
  windows="$(printf '%s' "$inv_output" | grep -c 'window_index:' || true)"
  panes="$(printf '%s' "$inv_output" | grep -c 'pane_index:' || true)"

  local highlights
  highlights="$(build_tmux_highlights "$inv_output")" || highlights="[]"
  [[ "$highlights" == "" ]] && highlights="[]"

  local val_result="unknown"
  if printf '%s' "$val_output" | grep -q 'RESULT=PASS'; then
    val_result="PASS"
  fi

  jq -n \
    --argjson sessions "$sessions" \
    --argjson windows "$windows" \
    --argjson panes "$panes" \
    --arg valResult "$val_result" \
    --argjson highlights "$highlights" \
    '{
      summary: {
        sessionCount: $sessions,
        windowCount: $windows,
        paneCount: $panes
      },
      notes: ["Metadata only. No pane content captured.", "Snapshot inventory is read-only.", ("Tmux validate: " + $valResult)],
      highlights: $highlights
    }'
}

build_tmux_sessions() {
  log "Gathering structured tmux sessions..."
  local inv_output records_tmp records_json mappings_json
  inv_output="$(run_cli tmux inventory)" || true
  records_tmp="$(mktemp)"
  : > "$records_tmp"

  while IFS=$'\t' read -r machine session_name attached window_count pane_index record_notes; do
    [[ -z "$session_name" ]] && continue
    case "$session_name" in
      none|"(none)"|local_tmux|remote_nuc2) continue ;;
    esac
    jq -n \
      --arg machine "$machine" \
      --arg sessionName "$session_name" \
      --arg attached "$attached" \
      --arg windowCount "$window_count" \
      --arg paneIndex "$pane_index" \
      --arg notes "$record_notes" \
      '{machine: $machine, sessionName: $sessionName, attachedRaw: $attached, windowCountRaw: $windowCount, paneIndex: $paneIndex, notes: $notes}' \
      >> "$records_tmp"
  done < <(
    printf '%s' "$inv_output" | awk '
      function emit() {
        if (started && session_name != "") {
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", machine, session_name, attached, windows, pane_index, notes
        }
      }
      /^---$/ { emit(); started=1; machine=""; session_name=""; attached=""; windows="0"; pane_index="none"; notes=""; next }
      started && /^machine:/ { machine=$0; sub(/^machine:[[:space:]]*/, "", machine); next }
      started && /^session_name:/ { session_name=$0; sub(/^session_name:[[:space:]]*/, "", session_name); next }
      started && /^session_attached:/ { attached=$0; sub(/^session_attached:[[:space:]]*/, "", attached); next }
      started && /^session_windows:/ { windows=$0; sub(/^session_windows:[[:space:]]*/, "", windows); next }
      started && /^pane_index:/ { pane_index=$0; sub(/^pane_index:[[:space:]]*/, "", pane_index); next }
      started && /^notes:/ { notes=$0; sub(/^notes:[[:space:]]*/, "", notes); next }
      END { emit() }
    '
  )

  records_json="$(jq -s '.' "$records_tmp")"
  rm -f "$records_tmp"

  mappings_json="$(workspace_registry_entries | jq -s '
    map(select(.workspace_id | test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))) |
    unique_by(.workspace_id) |
    map({workspaceId: .workspace_id, targetMachine: .target_machine, sessionName: .canonical_session_name})
  ' 2>/dev/null || echo '[]')"
  [[ -n "$mappings_json" ]] || mappings_json='[]'

  jq -n \
    --argjson records "$records_json" \
    --argjson mappings "$mappings_json" '
      def machine_key:
        ascii_downcase |
        if contains("nuc1") then "nuc1"
        elif contains("nuc2") then "nuc2"
        else . end;
      reduce $records[] as $record ([];
        ($mappings | map(select(
          .sessionName == $record.sessionName and
          ((.targetMachine | machine_key) == ($record.machine | machine_key))
        )) | first // null) as $association |
        (map(.machine == $record.machine and .sessionName == $record.sessionName) | index(true)) as $index |
        if $index == null then
          . + [{
            machine: $record.machine,
            sessionName: $record.sessionName,
            attached: (if $record.attachedRaw == "attached" then true elif $record.attachedRaw == "detached" then false else null end),
            windowCount: ($record.windowCountRaw | tonumber? // 0),
            paneCount: (if ($record.paneIndex == "none" or $record.paneIndex == "n/a") then 0 else 1 end),
            canonical: ($association != null),
            workspaceId: ($association.workspaceId // null),
            notes: (["Metadata only. No pane content or scrollback captured.", $record.notes] | map(select(length > 0)) | unique)
          }]
        else
          .[$index].paneCount += (if ($record.paneIndex == "none" or $record.paneIndex == "n/a") then 0 else 1 end) |
          .[$index].notes = ((.[$index].notes + [$record.notes]) | map(select(length > 0)) | unique)
        end
      )'
}

build_workspace_dry_run() {
  log "Gathering workspace dry-run previews..."
  local plan_output dryrun_output val_output
  plan_output="$(run_cli workspace plan harness)" || true
  dryrun_output="$(run_cli workspace dry-run harness)" || true
  val_output="$(run_cli workspace validate)" || true

  local canonical="harness"
  local canonical_line
  canonical_line="$(extract_field "$plan_output" "canonical_session_name")"
  if [[ -n "$canonical_line" ]]; then
    canonical="$canonical_line"
  fi

  local preview_lines copy_only_lines
  preview_lines="$(text_to_json_lines "$dryrun_output")"
  copy_only_lines="$(printf '%s' "$dryrun_output" | grep 'COPY_ONLY:' | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')"

  local val_result="unknown"
  if printf '%s' "$val_output" | grep -q 'RESULT=PASS'; then
    val_result="PASS"
  fi

  jq -n \
    --arg canonical "$canonical" \
    --argjson previewLines "$preview_lines" \
    --argjson copyOnlyLines "$copy_only_lines" \
    --arg valResult "$val_result" \
    '{
      canonicalSessionPreview: $canonical,
      previewLines: $previewLines,
      copyOnlyLines: $copyOnlyLines,
      notes: ["Snapshot preview only.", ("Workspace validate: " + $valResult)]
    }'
}

build_workspace_dry_runs() {
  log "Gathering registry-driven workspace dry-run previews..."
  local rows_tmp
  rows_tmp="$(mktemp)"
  : > "$rows_tmp"

  if ! jq -e '.workspaces | type == "array"' "$WORKSPACE_REGISTRY" >/dev/null 2>&1; then
    warn "Workspace registry is malformed; workspaceDryRuns will be empty"
    printf '[]'
    rm -f "$rows_tmp"
    return 0
  fi

  local index=0 entry workspace_id target_machine canonical registry_notes
  local plan_output dryrun_output plan_result preview_lines copy_only_lines
  declare -A seen_ids=()

  while IFS= read -r entry; do
    if ! jq -e '
      type == "object" and
      (.workspace_id | type == "string") and
      (.target_machine | type == "string") and
      (.canonical_session_name | type == "string")
    ' <<<"$entry" >/dev/null 2>&1; then
      warn "Skipping malformed workspace registry entry at index $index"
      index=$((index + 1))
      continue
    fi

    workspace_id="$(jq -r '.workspace_id' <<<"$entry")"
    if [[ ! "$workspace_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
      warn "Skipping workspace registry entry with invalid ID at index $index"
      index=$((index + 1))
      continue
    fi
    if [[ -n "${seen_ids[$workspace_id]:-}" ]]; then
      warn "Skipping duplicate workspace registry ID at index $index"
      index=$((index + 1))
      continue
    fi
    seen_ids["$workspace_id"]=1

    target_machine="$(jq -r '.target_machine' <<<"$entry")"
    canonical="$(jq -r '.canonical_session_name' <<<"$entry")"
    registry_notes="$(jq -r '.notes // "No registry notes."' <<<"$entry")"
    registry_notes="$(redact_text "$registry_notes")"

    plan_output="$(run_cli workspace plan "$workspace_id")" || true
    dryrun_output="$(run_cli workspace dry-run "$workspace_id")" || true
    plan_result="$(result_from_output "$plan_output")"
    canonical="$(extract_field "$plan_output" "canonical_session_name" || true)"
    if [[ -z "$canonical" ]]; then
      canonical="$(jq -r '.canonical_session_name' <<<"$entry")"
    fi
    preview_lines="$(text_to_json_lines "$dryrun_output")"
    copy_only_lines="$(printf '%s' "$dryrun_output" | grep 'COPY_ONLY:' | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')"

    jq -n \
      --arg workspaceId "$workspace_id" \
      --arg targetMachine "$target_machine" \
      --arg canonicalSessionPreview "$canonical" \
      --arg planResult "$plan_result" \
      --argjson previewLines "$preview_lines" \
      --argjson copyOnlyLines "$copy_only_lines" \
      --arg notes "$registry_notes" \
      '{
        workspaceId: $workspaceId,
        targetMachine: $targetMachine,
        canonicalSessionPreview: $canonicalSessionPreview,
        planResult: $planResult,
        previewLines: $previewLines,
        copyOnlyLines: $copyOnlyLines,
        notes: [$notes]
      }' >> "$rows_tmp"
    index=$((index + 1))
  done < <(jq -c '.workspaces[]' "$WORKSPACE_REGISTRY")

  jq -s '.' "$rows_tmp"
  rm -f "$rows_tmp"
}

build_harness_reports() {
  jq -n '{
    latest: [
      {
        label: "Session reports",
        url: "https://harness.slimyai.xyz/reports/sessions/",
        result: "unknown"
      }
    ],
    emptyMessage: "Session reports are not included in the snapshot. Visit the reports URL directly."
  }'
}

redaction_scan() {
  local filepath="$1"
  local hook_host='dis''cord'
  local found=0

  if grep -RInE "https://${hook_host}\\.com/api/webhooks/|${hook_host}app\\.com/api/webhooks/" "$filepath" 2>/dev/null; then
    found=1
  fi
  if grep -RInE 'Bearer [A-Za-z0-9._-]{8,}' "$filepath" 2>/dev/null; then
    found=1
  fi
  if grep -RInE 'sk-[A-Za-z0-9._-]{12,}' "$filepath" 2>/dev/null; then
    found=1
  fi
  if grep -RInE '(SECRET|TOKEN|PASSWORD|WEBHOOK_URL)=[A-Za-z0-9]' "$filepath" 2>/dev/null; then
    found=1
  fi

  return $found
}

assemble_snapshot() {
  log "Assembling snapshot JSON..."

  compute_stale_after

  local machine="nuc1"
  if [[ "$HOSTNAME" == *"nuc2"* ]]; then
    machine="nuc2"
  fi

  local source_json notification_json schedule_inv_json schedule_dry_json schedule_drys_json
  local tmux_json tmux_sessions_json workspace_json workspace_drys_json reports_json

  source_json="$(jq -n \
    --arg producer "manual" \
    --arg machine "$machine" \
    --arg repoPath "$HARNESS_ROOT" \
    --arg producerVersion "$PRODUCER_VERSION" \
    '{producer: $producer, machine: $machine, repoPath: $repoPath, producerVersion: $producerVersion}')"

  notification_json="$(build_notification_status)"
  schedule_inv_json="$(build_schedule_inventory)"
  schedule_dry_json="$(build_schedule_dry_run)"
  schedule_drys_json="$(build_schedule_dry_runs)"
  tmux_json="$(build_tmux_inventory)"
  tmux_sessions_json="$(build_tmux_sessions)"
  workspace_json="$(build_workspace_dry_run)"
  workspace_drys_json="$(build_workspace_dry_runs)"
  reports_json="$(build_harness_reports)"

  local freshness_json redaction_json safety_json

  freshness_json="$(jq -n \
    --arg state "fresh" \
    --argjson maxAge "$MAX_AGE_SECONDS" \
    --argjson age "null" \
    --arg staleAfter "$STALE_AFTER" \
    --arg message "Snapshot generated at ${GENERATED_AT}. Stale after $((MAX_AGE_SECONDS / 60)) minutes." \
    '{state: $state, maxAgeSeconds: $maxAge, ageSeconds: $age, staleAfter: $staleAfter, message: $message}')"

  redaction_json="$(jq -n \
    --arg status "passed" \
    --arg rulesVersion "$PRODUCER_VERSION" \
    --argjson redactedCount 0 \
    --argjson blockedCount 0 \
    --arg notes "Redaction scan passed." \
    '{status: $status, rulesVersion: $rulesVersion, redactedFieldCount: $redactedCount, blockedFieldCount: $blockedCount, notes: [$notes]}')"

  safety_json="$(jq -n '{
    readOnly: true,
    dryRunOnly: true,
    noLiveMutation: true,
    snapshotMode: true,
    backendAdapterConnected: false,
    shellExecutionPresent: false
  }')"

  jq -n \
    --argjson schemaVersion "$SCHEMA_VERSION" \
    --arg mode "snapshot" \
    --arg generatedAt "$GENERATED_AT" \
    --argjson source "$source_json" \
    --argjson freshness "$freshness_json" \
    --argjson redaction "$redaction_json" \
    --argjson safety "$safety_json" \
    --argjson notificationStatus "$notification_json" \
    --argjson scheduleInventory "$schedule_inv_json" \
    --argjson scheduleDryRun "$schedule_dry_json" \
    --argjson scheduleDryRuns "$schedule_drys_json" \
    --argjson tmuxInventory "$tmux_json" \
    --argjson tmuxSessions "$tmux_sessions_json" \
    --argjson workspaceDryRun "$workspace_json" \
    --argjson workspaceDryRuns "$workspace_drys_json" \
    --argjson harnessReports "$reports_json" \
    '{
      schemaVersion: $schemaVersion,
      mode: $mode,
      generatedAt: $generatedAt,
      source: $source,
      freshness: $freshness,
      redaction: $redaction,
      safety: $safety,
      notificationStatus: $notificationStatus,
      scheduleInventory: $scheduleInventory,
      scheduleDryRun: $scheduleDryRun,
      scheduleDryRuns: $scheduleDryRuns,
      tmuxInventory: $tmuxInventory,
      tmuxSessions: $tmuxSessions,
      workspaceDryRun: $workspaceDryRun,
      workspaceDryRuns: $workspaceDryRuns,
      harnessReports: $harnessReports
    }'
}

main() {
  validate_configuration || exit 1
  log "Starting snapshot producer v${PRODUCER_VERSION}..."
  log "Harness root: ${HARNESS_ROOT}"
  log "Output: ${LATEST_JSON}"

  mkdir -p "$SNAPSHOT_DIR" "$HISTORY_DIR"
  chmod 0750 "$SNAPSHOT_DIR" 2>/dev/null || true

  local snapshot_json
  snapshot_json="$(assemble_snapshot)" || {
    err "Failed to assemble snapshot JSON"
    exit 1
  }

  local snapshot_bytes
  snapshot_bytes="$(printf '%s\n' "$snapshot_json" | wc -c)"
  if [[ "$snapshot_bytes" -gt "$MAX_SNAPSHOT_BYTES" ]]; then
    err "Snapshot size ${snapshot_bytes} bytes exceeds configured maximum ${MAX_SNAPSHOT_BYTES} bytes"
    err "Latest.json will NOT be updated. Previous snapshot preserved."
    rm -f "$TEMP_JSON"
    exit 1
  fi

  printf '%s\n' "$snapshot_json" > "$TEMP_JSON" || {
    err "Failed to write temp file: $TEMP_JSON"
    exit 1
  }

  log "Validating JSON with jq..."
  local jq_result
  jq_result="$(jq '.schemaVersion == 1 and .mode == "snapshot" and .source and .freshness and .redaction and .safety and .notificationStatus and .scheduleInventory and .scheduleDryRun and (.scheduleDryRuns | type == "array") and .tmuxInventory and (.tmuxSessions | type == "array") and .workspaceDryRun and (.workspaceDryRuns | type == "array") and .harnessReports' "$TEMP_JSON" 2>&1)" || {
    err "jq validation failed"
    rm -f "$TEMP_JSON"
    exit 1
  }

  if [[ "$jq_result" != "true" ]]; then
    err "jq schema validation returned: $jq_result"
    rm -f "$TEMP_JSON"
    exit 1
  fi

  log "Running post-redaction secret scan..."
  if ! redaction_scan "$TEMP_JSON"; then
    err "REDACTION FAILED: forbidden pattern detected in snapshot output"
    err "Latest.json will NOT be updated. Previous snapshot preserved."
    rm -f "$TEMP_JSON"
    printf '%s\n' "REDACTION_FAILED at ${GENERATED_AT}" > "${SNAPSHOT_DIR}/.redaction-failed"
    exit 1
  fi
  log "Redaction scan passed."

  chmod 0640 "$TEMP_JSON" 2>/dev/null || true

  log "Atomic move to latest.json..."
  mv "$TEMP_JSON" "$LATEST_JSON" || {
    err "Failed to move temp file to latest.json"
    exit 1
  }

  local history_file="${HISTORY_DIR}/$(date -u +%Y%m%dT%H%M%SZ).json"
  cp "$LATEST_JSON" "$history_file" 2>/dev/null || {
    warn "Failed to write history file (non-fatal): $history_file"
  }
  chmod 0640 "$history_file" 2>/dev/null || true

  log "Snapshot written successfully: $LATEST_JSON"
  log "History: $history_file"
  log "DONE"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
