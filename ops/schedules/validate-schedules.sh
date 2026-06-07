#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT_DIR/ops/harness-ops"
DISCOVER="$ROOT_DIR/ops/schedules/discover-schedules.sh"
VALIDATOR="$ROOT_DIR/ops/schedules/validate-schedules.sh"
README_FILE="$ROOT_DIR/ops/schedules/README.md"

log() { echo "[schedule-validate] $*"; }
warn() { echo "[schedule-validate] WARN: $*"; }
err() { echo "[schedule-validate] ERROR: $*" >&2; }

warn_count=0
fail_count=0

record_warn() { warn "$*"; warn_count=$((warn_count + 1)); }
record_fail() { err "$*"; fail_count=$((fail_count + 1)); }

forbidden_pattern() {
  local sys_cmd="systemctl"
  local sys_ops='enable|disable|start|stop|restart|reload|daemon-reload'
  local cron_remove="crontab -""r"
  local cron_stdin="crontab -""[[:space:]]"
  local cron_path="/etc/cron"
  local chmod_path='ch'"mod .*/etc/""cron"
  local hook_host='dis'"cord"
  local send_pattern_a="curl.*${hook_host}"
  local send_pattern_b="${hook_host}.*curl"
  printf '%s' "${sys_cmd} (${sys_ops})|${cron_remove}|${cron_stdin}|rm ${cron_path}|mv ${cron_path}|${chmod_path}|${send_pattern_a}|${send_pattern_b}"
}

cron_mutation_pattern() {
  local cron_remove="crontab -""r"
  local cron_stdin="crontab -""[[:space:]]"
  printf '%s' "${cron_remove}|${cron_stdin}"
}

service_mutation_pattern() {
  local sys_cmd="systemctl"
  local sys_ops='start|stop|restart|reload|enable|disable|daemon-reload'
  printf '%s' "${sys_cmd} (${sys_ops})"
}

usage() {
  cat <<'USG'
validate-schedules.sh — validate read-only schedule inventory tooling

Usage:
  ops/harness-ops schedule validate

Behavior:
  - checks required files exist
  - runs bash -n on Ops CLI and schedule scripts
  - checks command availability and reports WARN when optional tools are absent
  - scans for forbidden mutation commands in the schedule inventory layer
  - prints PASS/WARN/FAIL
USG
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      err "unknown arg: $1"
      exit 2
      ;;
  esac
fi

for path in "$CLI" "$DISCOVER" "$VALIDATOR" "$README_FILE"; do
  if [[ ! -e "$path" ]]; then
    record_fail "missing required file: $path"
  fi
done

for path in "$CLI" "$DISCOVER" "$VALIDATOR"; do
  if [[ -f "$path" ]]; then
    if bash -n "$path"; then
      log "syntax OK: ${path#$ROOT_DIR/}"
    else
      record_fail "bash -n failed: ${path#$ROOT_DIR/}"
    fi
  fi
done

for cmd in crontab systemctl find grep awk sed stat ls cat; do
  if command -v "$cmd" >/dev/null 2>&1; then
    log "command present: $cmd"
  else
    record_warn "command missing: $cmd"
  fi
done

if command -v ssh >/dev/null 2>&1; then
  log "command present: ssh"
else
  record_warn "command missing: ssh (optional for NUC2 read-only inventory)"
fi

MUTATION_PATTERN="$(forbidden_pattern)"

if grep -n -E "$MUTATION_PATTERN" "$CLI" "$DISCOVER" "$README_FILE" >/dev/null 2>&1; then
  grep -n -E "$MUTATION_PATTERN" "$CLI" "$DISCOVER" "$README_FILE" || true
  record_fail "forbidden mutation or Discord-send command found in schedule inventory layer"
else
  log "forbidden mutation scan: clean"
fi

if grep -n -E 'notify-blockers\.sh' "$CLI" "$DISCOVER" "$README_FILE" >/dev/null 2>&1; then
  record_warn "schedule layer references notify-blockers.sh by name; verify read-only intent"
else
  log "no notify-blockers mutation path present"
fi

SERVICE_MUTATION_PATTERN="$(service_mutation_pattern)"
if grep -n -E "$SERVICE_MUTATION_PATTERN" "$CLI" "$DISCOVER" "$README_FILE" >/dev/null 2>&1; then
  record_fail "timer/service mutation path present"
else
  log "no timer/service mutation path present"
fi

CRON_MUTATION_PATTERN="$(cron_mutation_pattern)"
if grep -n -E "$CRON_MUTATION_PATTERN" "$CLI" "$DISCOVER" "$README_FILE" >/dev/null 2>&1; then
  record_fail "crontab mutation path present"
else
  log "no crontab mutation path present"
fi

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
