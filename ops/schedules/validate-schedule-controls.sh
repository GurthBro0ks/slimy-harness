#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT_DIR/ops/harness-ops"
REGISTRY="$ROOT_DIR/ops/schedules/schedule-registry.json"
PLAN="$ROOT_DIR/ops/schedules/schedule-plan.sh"
DRY_RUN="$ROOT_DIR/ops/schedules/schedule-dry-run.sh"
RUN_ONCE="$ROOT_DIR/ops/schedules/schedule-run-once-dry-run.sh"
VALIDATOR="$ROOT_DIR/ops/schedules/validate-schedule-controls.sh"
README_FILE="$ROOT_DIR/ops/schedules/README.md"

warn_count=0
fail_count=0

log() { echo "[schedule-controls-validate] $*"; }
warn() { echo "[schedule-controls-validate] WARN: $*"; warn_count=$((warn_count + 1)); }
fail() { echo "[schedule-controls-validate] ERROR: $*" >&2; fail_count=$((fail_count + 1)); }

usage() {
  cat <<'USG'
validate-schedule-controls.sh — validate dry-run schedule controls

Usage:
  ops/harness-ops schedule controls-validate

Behavior:
  - validates schedule registry JSON and required fields
  - checks script syntax
  - checks required tools
  - scans for unsafe executable mutation paths
  - verifies read-only preview markers and redaction behavior
USG
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown arg: $1"
      exit 2
      ;;
  esac
fi

for path in "$CLI" "$REGISTRY" "$PLAN" "$DRY_RUN" "$RUN_ONCE" "$VALIDATOR" "$README_FILE"; do
  if [[ ! -e "$path" ]]; then
    fail "missing required file: ${path#$ROOT_DIR/}"
  fi
done

for path in "$CLI" "$PLAN" "$DRY_RUN" "$RUN_ONCE" "$VALIDATOR"; do
  if [[ -f "$path" ]]; then
    if bash -n "$path"; then
      log "syntax OK: ${path#$ROOT_DIR/}"
    else
      fail "bash -n failed: ${path#$ROOT_DIR/}"
    fi
  fi
done

for cmd in jq grep sed awk; do
  if command -v "$cmd" >/dev/null 2>&1; then
    log "command present: $cmd"
  else
    fail "missing required command: $cmd"
  fi
done

if ! jq . "$REGISTRY" >/dev/null 2>&1; then
  fail "registry JSON invalid: ${REGISTRY#$ROOT_DIR/}"
else
  log "registry JSON valid"
fi

required_fields='schedule_id description target_machine owner_scope schedule_type source_path_or_unit managed_mode risk_level approval_level command_redaction_rules backup_strategy_ref rollback_strategy_ref current_inventory_ref live_enable_allowed live_disable_allowed live_run_once_allowed notes'
for field in $required_fields; do
  missing_count="$(jq --arg f "$field" '[.entries[] | has($f) | not] | map(select(.)) | length' "$REGISTRY" 2>/dev/null || printf '999')"
  if [[ "$missing_count" != "0" ]]; then
    fail "registry entries missing required field '$field'"
  fi
done

if ! jq -e '.entries | length > 0' "$REGISTRY" >/dev/null 2>&1; then
  fail "registry has no entries"
fi

if ! jq -e 'all(.entries[]; .live_enable_allowed == false and .live_disable_allowed == false and .live_run_once_allowed == false)' "$REGISTRY" >/dev/null 2>&1; then
  fail "all live flags must be false in Ops-4B"
else
  log "registry live flags are all false"
fi

if ! jq -e 'all(.entries[]; (.managed_mode == "read_only" or .managed_mode == "managed_candidate"))' "$REGISTRY" >/dev/null 2>&1; then
  fail "managed_mode contains unsupported value"
fi

if ! jq -e 'all(.entries[]; (.target_machine != "nuc2" or .managed_mode == "read_only"))' "$REGISTRY" >/dev/null 2>&1; then
  fail "nuc2 entries must be read_only"
fi

if ! jq -e 'all(.entries[]; (.owner_scope != "system" or .managed_mode == "read_only"))' "$REGISTRY" >/dev/null 2>&1; then
  fail "system-scope entries must be read_only"
fi

if ! jq -e 'all(.entries[]; (.risk_level != "high" or .managed_mode == "read_only"))' "$REGISTRY" >/dev/null 2>&1; then
  fail "high-risk entries must be read_only"
fi

if ! grep -q "WOULD_RUN:" "$DRY_RUN"; then
  fail "dry-run script missing WOULD_RUN output marker"
fi
if ! grep -q "WOULD_RUN:" "$RUN_ONCE"; then
  fail "run-once dry-run script missing WOULD_RUN output marker"
fi

if ! grep -q "COPY_ONLY:" "$PLAN"; then
  fail "plan script missing COPY_ONLY safeguards"
fi

# Disallow executable live mutation commands unless printed as WOULD_RUN text.
live_pattern='(^|[^A-Za-z0-9_])((systemctl( --user)? (enable|disable|start|stop|restart|reload|daemon-reload))|(crontab -r)|(crontab -[[:space:]])|(rm /etc/cron)|(mv /etc/cron)|(sequencer/notify-session-complete\.sh)|(sequencer/notify-proof-dir-complete\.sh))'
for file in "$CLI" "$PLAN" "$DRY_RUN" "$RUN_ONCE" "$README_FILE"; do
  while IFS= read -r line; do
    line_num="${line%%:*}"
    content="${line#*:}"
    if [[ "$content" == *"WOULD_RUN:"* ]]; then
      continue
    fi
    fail "forbidden executable mutation path in ${file#$ROOT_DIR/}:$line_num"
  done < <(grep -n -E "$live_pattern" "$file" || true)
done

# Refusal and redaction behavior should be present.
if ! grep -q "REFUSE" "$DRY_RUN"; then
  warn "dry-run script missing explicit REFUSE wording"
fi
if ! grep -q "REFUSE" "$RUN_ONCE"; then
  warn "run-once script missing explicit REFUSE wording"
fi
if ! grep -q "REDACTED" "$PLAN" || ! grep -q "REDACTED" "$DRY_RUN" || ! grep -q "REDACTED" "$RUN_ONCE"; then
  warn "one or more scripts may be missing explicit redaction marker logic"
fi

if [[ "$fail_count" -gt 0 ]]; then
  log "RESULT=FAIL fails=$fail_count warnings=$warn_count"
  exit 1
fi

if [[ "$warn_count" -gt 0 ]]; then
  log "RESULT=WARN warnings=$warn_count"
  exit 0
fi

log "RESULT=PASS warnings=0"
exit 0
