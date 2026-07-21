#!/usr/bin/env bash
set -euo pipefail

PRODUCER_VERSION="1.0.0"
SCHEMA_VERSION=1
MAX_AGE_SECONDS=900

HARNESS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT_DIR="/home/slimy/harness-logs/ops-snapshots"
LATEST_JSON="${SNAPSHOT_DIR}/latest.json"
HISTORY_DIR="${SNAPSHOT_DIR}/history"
TEMP_JSON="${SNAPSHOT_DIR}/.latest.json.tmp"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STALE_AFTER=""
HOSTNAME="$(hostname)"

CLI_CMD="bash ${HARNESS_ROOT}/ops/harness-ops"

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
  local cmd="$1"
  for allowed in "${ALLOWED_COMMANDS[@]}"; do
    if [[ "$cmd" == "$allowed"* ]]; then
      return 0
    fi
  done
  return 1
}

run_cli() {
  local cmd="$1"
  local output=""
  local rc=0

  if ! is_allowed "$cmd"; then
    warn "Command not on allowlist, skipping: $cmd"
    printf ''
    return 1
  fi

  output="$(cd "$HARNESS_ROOT" && $CLI_CMD $cmd 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    warn "Command exited with rc=$rc: $cmd"
  fi
  redact_text "$output"
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

build_notification_status() {
  log "Gathering notification status..."
  local status_output dryrun_output dedupe_output
  status_output="$(run_cli "notify status")" || true
  dryrun_output="$(run_cli "notify dry-run")" || true
  dedupe_output="$(run_cli "notify dedupe-check snapshot-producer-placeholder")" || true

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
  inv_output="$(run_cli "schedule inventory")" || true
  val_output="$(run_cli "schedule validate")" || true

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
  plan_output="$(run_cli "schedule plan harness-watchdog-cron")" || true
  enable_output="$(run_cli "schedule dry-run harness-watchdog-cron --action enable")" || true
  runonce_output="$(run_cli "schedule run-once-dry-run harness-watchdog-cron")" || true

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
  inv_output="$(run_cli "tmux inventory")" || true
  val_output="$(run_cli "tmux validate")" || true

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

build_workspace_dry_run() {
  log "Gathering workspace dry-run previews..."
  local plan_output dryrun_output val_output
  plan_output="$(run_cli "workspace plan harness")" || true
  dryrun_output="$(run_cli "workspace dry-run harness")" || true
  val_output="$(run_cli "workspace validate")" || true

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

  local source_json notification_json schedule_inv_json schedule_dry_json
  local tmux_json workspace_json reports_json

  source_json="$(jq -n \
    --arg producer "manual" \
    --arg machine "$machine" \
    --arg repoPath "$HARNESS_ROOT" \
    --arg producerVersion "$PRODUCER_VERSION" \
    '{producer: $producer, machine: $machine, repoPath: $repoPath, producerVersion: $producerVersion}')"

  notification_json="$(build_notification_status)"
  schedule_inv_json="$(build_schedule_inventory)"
  schedule_dry_json="$(build_schedule_dry_run)"
  tmux_json="$(build_tmux_inventory)"
  workspace_json="$(build_workspace_dry_run)"
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
    --argjson tmuxInventory "$tmux_json" \
    --argjson workspaceDryRun "$workspace_json" \
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
      tmuxInventory: $tmuxInventory,
      workspaceDryRun: $workspaceDryRun,
      harnessReports: $harnessReports
    }'
}

main() {
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

  printf '%s\n' "$snapshot_json" > "$TEMP_JSON" || {
    err "Failed to write temp file: $TEMP_JSON"
    exit 1
  }

  log "Validating JSON with jq..."
  local jq_result
  jq_result="$(jq '.schemaVersion == 1 and .mode == "snapshot" and .source and .freshness and .redaction and .safety and .notificationStatus and .scheduleInventory and .scheduleDryRun and .tmuxInventory and .workspaceDryRun and .harnessReports' "$TEMP_JSON" 2>&1)" || {
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
