#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT_DIR/ops/harness-ops"
REGISTRY="$ROOT_DIR/ops/workspaces/workspace-registry.json"
PLAN_SCRIPT="$ROOT_DIR/ops/workspaces/workspace-plan.sh"
DRY_RUN_SCRIPT="$ROOT_DIR/ops/workspaces/workspace-dry-run.sh"
VALIDATOR="$ROOT_DIR/ops/workspaces/validate-workspaces.sh"
README_FILE="$ROOT_DIR/ops/workspaces/README.md"

log() { echo "[workspace-validate] $*"; }
warn() { echo "[workspace-validate] WARN: $*"; }
err() { echo "[workspace-validate] ERROR: $*" >&2; }

warn_count=0
fail_count=0

record_warn() { warn "$*"; warn_count=$((warn_count + 1)); }
record_fail() { err "$*"; fail_count=$((fail_count + 1)); }

tmux_mutation_pattern() {
  local tm='tmux'
  local new_cmd='ne''w'
  local new_session='new''-session'
  local kill_session='kill''-session'
  local kill_window='kill''-window'
  local kill_pane='kill''-pane'
  local rename_session='rename''-session'
  local rename_window='rename''-window'
  local send_keys='send''-keys'
  local split_window='split''-window'
  local resize_pane='resize''-pane'
  local attach_cmd='atta''ch'
  local detach_cmd='deta''ch'
  local source_file='source''-file'
  local set_option='set''-option'
  local set_window_option='set''-window-option'
  local move_window='move''-window'
  local swap_window='swap''-window'
  local capture_pane='cap''ture-pane'
  printf '%s' "${tm} ${new_cmd}|${tm} ${new_session}|${tm} ${kill_session}|${tm} ${kill_window}|${tm} ${kill_pane}|${tm} ${rename_session}|${tm} ${rename_window}|${tm} ${send_keys}|${tm} ${split_window}|${tm} ${resize_pane}|${tm} ${attach_cmd}|${tm} ${detach_cmd}|${tm} ${source_file}|${tm} ${set_option}|${tm} ${set_window_option}|${tm} ${move_window}|${tm} ${swap_window}|${tm} ${capture_pane}"
}

service_cron_pattern() {
  local sys_cmd='systemctl'
  local sys_ops='start|stop|restart|reload|enable|disable|daemon-reload'
  local cron_remove='crontab -'""'r'
  local cron_write='crontab -'""'[[:space:]]'
  local hook_host='dis'""'cord'
  local curl_hook_a="curl.*${hook_host}"
  local curl_hook_b="${hook_host}.*curl"
  printf '%s' "${sys_cmd} (${sys_ops})|${cron_remove}|${cron_write}|${curl_hook_a}|${curl_hook_b}"
}

no_create_reuse_pattern() {
  local create_cmd='workspace cr'"eate"
  local reuse_cmd='workspace re'"use"
  printf '%s' "${create_cmd}|${reuse_cmd}"
}

usage() {
  cat <<'USG'
validate-workspaces.sh — validate dry-run workspace planner tooling

Usage:
  ops/harness-ops workspace validate

Behavior:
  - validates workspace registry JSON
  - validates workspace scripts syntax
  - confirms target paths exist or reports WARN
  - confirms no live tmux mutation execution path exists
  - confirms no create/reuse command is implemented
  - confirms no pane content capture path exists
  - confirms no service/cron/timer/notifier mutation paths exist
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

for path in "$CLI" "$REGISTRY" "$PLAN_SCRIPT" "$DRY_RUN_SCRIPT" "$VALIDATOR" "$README_FILE"; do
  if [[ ! -e "$path" ]]; then
    record_fail "missing required file: $path"
  fi
done

for path in "$CLI" "$PLAN_SCRIPT" "$DRY_RUN_SCRIPT" "$VALIDATOR"; do
  if [[ -f "$path" ]]; then
    if bash -n "$path"; then
      log "syntax OK: ${path#$ROOT_DIR/}"
    else
      record_fail "bash -n failed: ${path#$ROOT_DIR/}"
    fi
  fi
done

if [[ -f "$REGISTRY" ]]; then
  if jq . "$REGISTRY" >/dev/null 2>&1; then
    log "registry JSON valid"
  else
    record_fail "workspace registry is not valid JSON"
  fi
fi

for cmd in jq tmux grep sed awk stat ls; do
  if command -v "$cmd" >/dev/null 2>&1; then
    log "command present: $cmd"
  else
    record_fail "command missing: $cmd"
  fi
done

if ! grep -q 'workspace validate' "$CLI" 2>/dev/null; then
  record_fail "ops/harness-ops missing workspace validate command"
fi

CREATE_REUSE_PATTERN="$(no_create_reuse_pattern)"
if grep -n -E "$CREATE_REUSE_PATTERN" "$CLI" "$PLAN_SCRIPT" "$DRY_RUN_SCRIPT" >/dev/null 2>&1; then
  record_fail "live create/reuse command path implemented in this pass"
else
  log "no live create/reuse command path present"
fi

TMUX_MUTATION_PATTERN="$(tmux_mutation_pattern)"
if grep -n -E "$TMUX_MUTATION_PATTERN" "$CLI" "$PLAN_SCRIPT" "$DRY_RUN_SCRIPT" "$README_FILE" >/dev/null 2>&1; then
  record_fail "executable tmux mutation path present in workspace planner files"
else
  log "tmux mutation execution scan: clean"
fi

if grep -n -E 'capture-pane' "$CLI" "$PLAN_SCRIPT" "$DRY_RUN_SCRIPT" "$README_FILE" >/dev/null 2>&1; then
  record_fail "pane content capture path present"
else
  log "no pane content capture path present"
fi

SERVICE_CRON_PATTERN="$(service_cron_pattern)"
if grep -n -E "$SERVICE_CRON_PATTERN" "$CLI" "$PLAN_SCRIPT" "$DRY_RUN_SCRIPT" "$README_FILE" >/dev/null 2>&1; then
  record_fail "service/cron/notifier mutation path present"
else
  log "service/cron/notifier mutation scan: clean"
fi

if [[ -f "$REGISTRY" ]]; then
  jq -r '.workspaces[] | .workspace_id + "|" + .target_machine + "|" + (.target_paths[0] // "")' "$REGISTRY" | while IFS='|' read -r workspace_id target_machine first_path; do
    [[ -z "$workspace_id" ]] && continue
    if [[ "$target_machine" == "nuc2" ]]; then
      log "target path check skipped for remote-only workspace: $workspace_id"
      continue
    fi
    if [[ -z "$first_path" || ! -e "$first_path" ]]; then
      record_warn "target path missing for $workspace_id: ${first_path:-none}"
    else
      log "target path present for $workspace_id: $first_path"
    fi
  done
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
