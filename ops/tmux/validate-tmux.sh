#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT_DIR/ops/harness-ops"
DISCOVER="$ROOT_DIR/ops/tmux/tmux-inventory.sh"
VALIDATOR="$ROOT_DIR/ops/tmux/validate-tmux.sh"
README_FILE="$ROOT_DIR/ops/tmux/README.md"

log() { echo "[tmux-validate] $*"; }
warn() { echo "[tmux-validate] WARN: $*"; }
err() { echo "[tmux-validate] ERROR: $*" >&2; }

warn_count=0
fail_count=0

record_warn() { warn "$*"; warn_count=$((warn_count + 1)); }
record_fail() { err "$*"; fail_count=$((fail_count + 1)); }

mutation_pattern() {
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

capture_pattern() {
  local tm='tmux'
  local capture_pane='cap''ture-pane'
  printf '%s' "${tm} ${capture_pane}"
}

usage() {
  cat <<'USG'
validate-tmux.sh — validate read-only tmux inventory tooling

Usage:
  ops/harness-ops tmux validate

Behavior:
  - checks required files exist
  - runs bash -n on Ops CLI and tmux scripts
  - checks tmux availability and reports WARN when absent
  - scans for forbidden tmux mutation commands in the tmux inventory layer
  - confirms pane-content capture is not done by default
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

for cmd in tmux grep sed awk stat ssh; do
  if command -v "$cmd" >/dev/null 2>&1; then
    log "command present: $cmd"
  else
    if [[ "$cmd" == "ssh" || "$cmd" == "tmux" ]]; then
      record_warn "command missing: $cmd"
    else
      record_fail "command missing: $cmd"
    fi
  fi
done

MUTATION_PATTERN="$(mutation_pattern)"
if grep -n -E "$MUTATION_PATTERN" "$CLI" "$DISCOVER" "$README_FILE" >/dev/null 2>&1; then
  grep -n -E "$MUTATION_PATTERN" "$CLI" "$DISCOVER" "$README_FILE" || true
  record_fail "forbidden tmux mutation command found in tmux inventory layer"
else
  log "tmux mutation scan: clean"
fi

CAPTURE_PATTERN="$(capture_pattern)"
if grep -n -E "$CAPTURE_PATTERN" "$CLI" "$DISCOVER" "$README_FILE" >/dev/null 2>&1; then
  grep -n -E "$CAPTURE_PATTERN" "$CLI" "$DISCOVER" "$README_FILE" || true
  record_fail "pane-content capture command found in default tmux inventory path"
else
  log "no pane-content capture in default path"
fi

if grep -n -E 'notify-blockers\.sh' "$CLI" "$DISCOVER" "$README_FILE" >/dev/null 2>&1; then
  record_warn "tmux layer references notify-blockers.sh by name; verify read-only intent"
else
  log "no notify-blockers mutation path present"
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
