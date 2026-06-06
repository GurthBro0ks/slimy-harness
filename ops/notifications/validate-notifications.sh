#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/notifications/registry.json"
README_FILE="$ROOT_DIR/ops/notifications/README.md"
HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-/home/slimy/.slimy-harness.env}"
STATE_DIR="/home/slimy/harness-logs/notify-state"
PROOF_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proof-dir)
      PROOF_DIR="${2:-}"
      shift 2
      ;;
    --help|-h)
      cat <<'USG'
validate-notifications.sh -- read-only notification registry validator

Usage:
  bash ops/notifications/validate-notifications.sh [--proof-dir PATH]

Behavior:
  - prints env key presence only, never values
  - validates registry.json via jq
  - checks expected harness scripts exist
  - checks marker directory presence and warns if missing
  - checks report URL base and session report URL pattern
  - checks NUC2 relay assumptions via redacted remote key-name presence only
  - scans registry/README/output for webhook-like URLs

Exit nonzero only for invalid registry, hard safety failures, or secret-like strings.
USG
      exit 0
      ;;
    *)
      echo "[validate-notifications] ERROR: unknown arg: $1" >&2
      exit 64
      ;;
  esac
done

log()  { echo "[validate-notifications] $*"; }
warn() { echo "[validate-notifications] WARN: $*"; }
err()  { echo "[validate-notifications] ERROR: $*" >&2; }

hard_fail=0
warn_count=0

record_warn() {
  warn "$*"
  warn_count=$((warn_count + 1))
}

record_fail() {
  err "$*"
  hard_fail=1
}

if ! command -v jq >/dev/null 2>&1; then
  record_fail "jq is required for registry validation"
fi

if [[ ! -f "$REGISTRY" ]]; then
  record_fail "missing registry.json: $REGISTRY"
fi

if [[ ! -f "$README_FILE" ]]; then
  record_fail "missing README.md: $README_FILE"
fi

if [[ "$hard_fail" -ne 0 ]]; then
  exit 1
fi

log "jq validating registry.json"
if ! jq . "$REGISTRY" >/dev/null 2>&1; then
  record_fail "registry.json is not valid JSON"
fi

report_base="$(jq -r '.report_url_base' "$REGISTRY")"
session_pattern="$(jq -r '.session_report_url_pattern' "$REGISTRY")"
mention_target_id="$(jq -r '.mention_target_id' "$REGISTRY")"

log "registry report_url_base=$report_base"
log "registry session_report_url_pattern=$session_pattern"
log "registry mention_target_id=$mention_target_id"

if [[ "$report_base" != "https://harness.slimyai.xyz/reports" ]]; then
  record_fail "report_url_base mismatch: expected https://harness.slimyai.xyz/reports"
fi

if [[ "$session_pattern" != *"/reports/sessions/"* ]]; then
  record_fail "session_report_url_pattern must contain /reports/sessions/"
fi

log "checking expected scripts from registry"
while IFS= read -r path; do
  if [[ -n "$path" ]]; then
    if [[ -f "$ROOT_DIR/$path" ]]; then
      log "present: $path"
    else
      record_fail "missing expected script/file: $path"
    fi
  fi
done < <(jq -r '.channels[].script_path, .supporting_components[].path' "$REGISTRY" | sort -u)

log "checking dedupe/marker state directory"
if [[ -d "$STATE_DIR" ]]; then
  log "present: $STATE_DIR"
else
  record_warn "marker state dir missing: $STATE_DIR"
fi

local_env_keys=(
  DISCORD_HARNESS_WEBHOOK_URL
  DISCORD_HARNESS_MENTION
  HARNESS_REPORT_BASE_URL
  HARNESS_NOTIFY_ON_SUCCESS
  HARNESS_NOTIFY_PING_ON_SUCCESS
  HARNESS_NOTIFY_ATTACH_HTML
  HARNESS_NOTIFY_ATTACH_JSON
  HARNESS_NOTIFY_RELAY_HOST
  HARNESS_NOTIFY_STATE_DIR
)

log "local env key presence (values redacted / not printed)"
for key in "${local_env_keys[@]}"; do
  if grep -qE "^${key}=" "$HARNESS_ENV_FILE" 2>/dev/null; then
    log "  $key present"
  else
    log "  $key absent"
  fi
done

log "checking NUC2 relay assumption via key-name presence only"
remote_relay_key="HARNESS_NOTIFY_RELAY_HOST"
remote_webhook_key="DISCORD_HARNESS_WEBHOOK_URL"
if ssh nuc2 'test -f /home/slimy/.slimy-harness.env' 2>/dev/null; then
  if ssh nuc2 "grep -qE '^${remote_relay_key}=' /home/slimy/.slimy-harness.env" 2>/dev/null; then
    log "  NUC2 ${remote_relay_key} present"
  else
    record_warn "NUC2 ${remote_relay_key} missing"
  fi

  if ssh nuc2 "grep -qE '^${remote_webhook_key}=' /home/slimy/.slimy-harness.env" 2>/dev/null; then
    record_fail "NUC2 must not store ${remote_webhook_key}"
  else
    log "  NUC2 ${remote_webhook_key} absent"
  fi
else
  record_warn "NUC2 env file not reachable; relay assumption not fully verified"
fi

scan_paths=("$REGISTRY" "$README_FILE" "$0")
if [[ -n "$PROOF_DIR" && -d "$PROOF_DIR" ]]; then
  scan_paths+=("$PROOF_DIR")
fi

log "scanning files for webhook-like URLs / secret-like strings"
discord_host_part="discord.com"
discordapp_host_part="discordapp.com"
api_path_part="api/webhooks"
webhook_key_part_a="WEBHOOK"
webhook_key_part_b="_URL="
scheme_part="https://"
discord_word_part="discord"
discord_path_part="${discord_host_part}/${api_path_part}"
discordapp_path_part="${discordapp_host_part}/${api_path_part}"
webhook_assign_part="${webhook_key_part_a}${webhook_key_part_b}"
https_discord_part="${scheme_part}${discord_word_part}"
patterns=(
  "$discord_path_part"
  "$discordapp_path_part"
  "$webhook_assign_part"
  "$https_discord_part"
)
for pattern in "${patterns[@]}"; do
  if grep -RIn "$pattern" "${scan_paths[@]}" >/tmp/validate-notifications-grep.$$.log 2>/dev/null; then
    # Allow WEBHOOK_URL mentions in code/comments only if not assigned a value and not a Discord URL.
    if [[ "$pattern" == "$webhook_assign_part" ]]; then
      record_warn "webhook-assignment token found in scanned files; review manually if needed"
      cat /tmp/validate-notifications-grep.$$.log | sed 's/^/[validate-notifications] WARN-MATCH: /'
    else
      record_fail "secret-like pattern found: $pattern"
      cat /tmp/validate-notifications-grep.$$.log | sed 's/^/[validate-notifications] MATCH: /'
    fi
  fi
  rm -f /tmp/validate-notifications-grep.$$.log
done

if [[ "$hard_fail" -ne 0 ]]; then
  record_fail "validation failed with hard safety errors"
  exit 1
fi

if [[ "$warn_count" -gt 0 ]]; then
  log "RESULT=WARN warnings=$warn_count"
else
  log "RESULT=PASS warnings=0"
fi

exit 0
