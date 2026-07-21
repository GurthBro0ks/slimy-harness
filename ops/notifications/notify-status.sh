#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/notifications/registry.json"
HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-/home/slimy/.slimy-harness.env}"
STATE_DIR="/home/slimy/harness-logs/notify-state"

log()  { echo "[notify-status] $*"; }
warn() { echo "[notify-status] WARN: $*"; }
err()  { echo "[notify-status] ERROR: $*" >&2; }

warn_count=0
fail_count=0

record_warn() { warn "$*"; warn_count=$((warn_count + 1)); }
record_fail() { err "$*"; fail_count=$((fail_count + 1)); }

if [[ $# -gt 0 ]]; then
  case "$1" in
    --help|-h) cat <<'USG'
notify-status.sh — read-only notification health summary

Usage:
  ops/harness-ops notify status

Behavior:
  - runs registry validation
  - summarizes configured channels
  - shows env key presence as present/missing/redacted only
  - shows report URL base and session report URL pattern
  - shows marker directory presence
  - shows NUC1/NUC2 ownership assumptions
  - shows legacy cleanup flag for blocker fallback
  - prints PASS/WARN/FAIL
  - no secrets printed
  - no Discord messages sent
USG
    exit 0 ;;
    *) echo "[notify-status] ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
fi

if ! command -v jq >/dev/null 2>&1; then
  record_fail "jq is required"
fi

if [[ ! -f "$REGISTRY" ]]; then
  record_fail "missing registry.json"
  exit 1
fi

log "=== Registry Validation ==="
if ! jq . "$REGISTRY" >/dev/null 2>&1; then
  record_fail "registry.json is not valid JSON"
  exit 1
fi
log "registry.json: valid JSON"

log ""
log "=== Report URLs ==="
report_base="$(jq -r '.report_url_base' "$REGISTRY")"
session_pattern="$(jq -r '.session_report_url_pattern' "$REGISTRY")"
mention_id="$(jq -r '.mention_target_id' "$REGISTRY")"
log "  report_url_base: $report_base"
log "  session_report_url_pattern: $session_pattern"
log "  mention_target_id: $mention_id"

if [[ "$report_base" != "https://harness.slimyai.xyz/reports" ]]; then
  record_fail "report_url_base mismatch"
fi
if [[ "$session_pattern" != *"/reports/sessions/"* ]]; then
  record_fail "session_report_url_pattern must contain /reports/sessions/"
fi

log ""
log "=== Configured Channels ==="
channel_count="$(jq '.channels | length' "$REGISTRY")"
log "  channels: $channel_count"
for i in $(seq 0 $((channel_count - 1))); do
  name="$(jq -r ".channels[$i].name" "$REGISTRY")"
  ctype="$(jq -r ".channels[$i].type" "$REGISTRY")"
  script="$(jq -r ".channels[$i].script_path" "$REGISTRY")"
  log "  [$i] $name ($ctype)"
  log "       script: $script"
  if [[ -f "$ROOT_DIR/$script" ]]; then
    log "       script present: yes"
  else
    record_warn "script missing: $ROOT_DIR/$script"
  fi
  legacy="$(jq -r ".channels[$i].legacy_cleanup_needed // false" "$REGISTRY")"
  if [[ "$legacy" == "true" ]]; then
    log "       legacy_cleanup_needed: true"
  fi
done

log ""
log "=== Env Key Presence ==="
all_required_nuc1="$(jq -r '.env_keys.required_on_nuc1[]' "$REGISTRY")"
all_optional_nuc1="$(jq -r '.env_keys.optional_on_nuc1[]' "$REGISTRY")"
all_expected_nuc2="$(jq -r '.env_keys.expected_on_nuc2[]' "$REGISTRY")"
all_must_not_nuc2="$(jq -r '.env_keys.must_not_live_on_nuc2[]' "$REGISTRY")"

check_env_key() {
  local key="$1"
  if grep -qE "^${key}=" "$HARNESS_ENV_FILE" 2>/dev/null; then
    log "  $key: present (redacted)"
  else
    log "  $key: missing"
  fi
}

log "  NUC1 required:"
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  check_env_key "$key"
done <<< "$all_required_nuc1"

log "  NUC1 optional:"
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  check_env_key "$key"
done <<< "$all_optional_nuc1"

log "  NUC2 expected:"
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  if ssh -o BatchMode=yes -o ConnectTimeout=5 nuc2 "grep -qE '^${key}=' /home/slimy/.slimy-harness.env" 2>/dev/null; then
    log "    $key: present (remote, redacted)"
  else
    record_warn "NUC2 $key: missing or unreachable"
  fi
done <<< "$all_expected_nuc2"

log "  NUC2 must NOT store:"
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  if ssh -o BatchMode=yes -o ConnectTimeout=5 nuc2 "grep -qE '^${key}=' /home/slimy/.slimy-harness.env" 2>/dev/null; then
    record_fail "NUC2 must not store $key"
  else
    log "    $key: absent (correct)"
  fi
done <<< "$all_must_not_nuc2"

log ""
log "=== Marker Directory ==="
if [[ -d "$STATE_DIR" ]]; then
  marker_count="$(find "$STATE_DIR" -name '*.sent' -o -name '*.relay-sent' -o -name '*.relay-failed' 2>/dev/null | wc -l)"
  log "  state_dir: $STATE_DIR (present, $marker_count markers)"
else
  record_warn "state_dir missing: $STATE_DIR"
fi

log ""
log "=== Machine Ownership ==="
jq -r '.machine_owner | to_entries[] | "  \(.key): \(.value | to_entries | map("\(.key)=\(.value)") | join(", "))"' "$REGISTRY" 2>/dev/null || \
  jq -r '.machine_ownership | to_entries[] | "  \(.key): \(.value | to_entries | map("\(.key)=\(.value)") | join(", "))"' "$REGISTRY"

log ""
log "=== Supporting Components ==="
comp_count="$(jq '.supporting_components | length' "$REGISTRY")"
for i in $(seq 0 $((comp_count - 1))); do
  name="$(jq -r ".supporting_components[$i].name" "$REGISTRY")"
  path="$(jq -r ".supporting_components[$i].path" "$REGISTRY")"
  role="$(jq -r ".supporting_components[$i].role" "$REGISTRY")"
  if [[ -f "$ROOT_DIR/$path" ]]; then
    log "  $name ($role): present"
  else
    record_warn "supporting component missing: $path"
  fi
done

log ""
if [[ "$fail_count" -gt 0 ]]; then
  log "RESULT=FAIL fails=$fail_count warnings=$warn_count"
  exit 1
elif [[ "$warn_count" -gt 0 ]]; then
  log "RESULT=WARN warnings=$warn_count"
  exit 0
else
  log "RESULT=PASS warnings=0"
  exit 0
fi
