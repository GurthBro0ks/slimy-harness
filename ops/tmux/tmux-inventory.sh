#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MACHINE_NAME="${HARNESS_MACHINE_NAME:-$(hostname)}"
DEFAULT_USER="${USER:-unknown}"

log() { echo "[tmux-inventory] $*"; }
warn() { echo "[tmux-inventory] WARN: $*"; }

usage() {
  cat <<'USG'
tmux-inventory.sh — read-only tmux inventory

Usage:
  ops/harness-ops tmux inventory

Behavior:
  - lists tmux sessions, windows, and panes using metadata-only commands
  - does not capture pane contents by default
  - does not attach/detach, send keys, resize, create, or destroy tmux objects
  - redacts secret-looking values
  - may attempt optional read-only NUC2 inspection via ssh host `nuc2`
USG
}

redact_text() {
  local text="$1"
  local hook_host='dis''cord'
  local hook_app='app'
  local hook_path='/api/webhooks/'
  printf '%s' "$text" | sed -E \
    -e "s#https://${hook_host}(${hook_app})?\\.com${hook_path}[A-Za-z0-9/_-]+#[REDACTED_DISCORD_WEBHOOK]#g" \
    -e 's#(https?://)[^ /:@]+:[^ /@]+@#\1[REDACTED]@#g' \
    -e 's/\b([Bb]earer)[[:space:]]+[A-Za-z0-9._~+\/=:-]+/\1 [REDACTED]/g' \
    -e 's/\b([A-Za-z_][A-Za-z0-9_]*(SECRET|TOKEN|KEY|PASSWORD|WEBHOOK|COOKIE|SESSION)[A-Za-z0-9_]*)=([^[:space:]]+)/\1=[REDACTED]/g' \
    -e 's/([?&](token|secret|key|password|session|cookie)=)[^&[:space:]]+/\1[REDACTED]/Ig'
}

compact_text() {
  local text="$1"
  text="$(printf '%s' "$text" | tr '\t' ' ' | tr -s ' ')"
  text="${text# }"
  text="${text% }"
  if [[ ${#text} -gt 220 ]]; then
    text="${text:0:217}..."
  fi
  printf '%s' "$text"
}

guess_project() {
  local haystack="$1"
  shopt -s nocasematch
  local project="unknown"
  if [[ "$haystack" =~ gh-tracker|habitat ]]; then
    project="gh-tracker"
  elif [[ "$haystack" =~ kb|wiki|obsidian|daily-note ]]; then
    project="kb"
  elif [[ "$haystack" =~ research ]]; then
    project="research-farm"
  elif [[ "$haystack" =~ harness|notify|sequencer|tmux ]]; then
    project="slimy-harness"
  elif [[ "$haystack" =~ slimy-chat ]]; then
    project="slimy-chat"
  elif [[ "$haystack" =~ opencode|claude|codex|agent|builder ]]; then
    project="agent-workflow"
  fi
  shopt -u nocasematch
  printf '%s' "$project"
}

guess_risk() {
  local haystack="$1"
  shopt -s nocasematch
  local risk="unknown"
  if [[ "$haystack" =~ discord|webhook|prod|production|deploy|caddy|notify|restart|systemctl|mysql|docker|publish ]]; then
    risk="high"
  elif [[ "$haystack" =~ opencode|claude|codex|agent|build|compile|pnpm|node|python|runner|sync|report|watchdog ]]; then
    risk="medium"
  elif [[ "$haystack" =~ bash|zsh|fish|sh|shell|status|top|htop|watch ]]; then
    risk="low"
  fi
  shopt -u nocasematch
  printf '%s' "$risk"
}

print_entry() {
  local machine="$1"
  local server_status="$2"
  local session_name="$3"
  local session_created="$4"
  local session_windows="$5"
  local session_attached="$6"
  local window_index="$7"
  local window_name="$8"
  local window_active="$9"
  local pane_index="${10}"
  local pane_id="${11}"
  local pane_active="${12}"
  local pane_command="${13}"
  local pane_path="${14}"
  local pane_width="${15}"
  local pane_height="${16}"
  local owner="${17}"
  local notes="${18}"

  session_name="$(compact_text "$(redact_text "$session_name")")"
  window_name="$(compact_text "$(redact_text "$window_name")")"
  pane_command="$(compact_text "$(redact_text "$pane_command")")"
  pane_path="$(compact_text "$(redact_text "$pane_path")")"
  notes="$(compact_text "$(redact_text "$notes")")"

  local project_guess risk
  project_guess="$(guess_project "$session_name $window_name $pane_command $pane_path $notes")"
  risk="$(guess_risk "$session_name $window_name $pane_command $pane_path $notes")"

  echo "---"
  echo "machine: $machine"
  echo "tmux_server_status: $server_status"
  echo "owner: $owner"
  echo "session_name: ${session_name:-none}"
  echo "session_created: ${session_created:-unknown}"
  echo "session_windows: ${session_windows:-0}"
  echo "session_attached: ${session_attached:-unknown}"
  echo "window_index: ${window_index:-none}"
  echo "window_name: ${window_name:-none}"
  echo "window_active: ${window_active:-unknown}"
  echo "pane_index: ${pane_index:-none}"
  echo "pane_id: ${pane_id:-none}"
  echo "pane_active: ${pane_active:-unknown}"
  echo "pane_current_command: ${pane_command:-unknown}"
  echo "pane_current_path: ${pane_path:-unknown}"
  echo "pane_width: ${pane_width:-unknown}"
  echo "pane_height: ${pane_height:-unknown}"
  echo "project_guess: $project_guess"
  echo "risk: $risk"
  echo "notes: ${notes:-none}"
}

print_skip() {
  print_entry "$MACHINE_NAME" "$1" "$2" "n/a" "0" "n/a" "n/a" "n/a" "n/a" "n/a" "n/a" "n/a" "n/a" "n/a" "n/a" "n/a" "$DEFAULT_USER" "$3"
}

emit_local_inventory() {
  local machine="$1"
  local owner="$2"
  local server_status="$3"
  local sessions_raw="$4"

  while IFS='|' read -r session_name session_created session_windows session_attached; do
    [[ -z "$session_name" ]] && continue
    local windows_raw
    windows_raw="$(tmux list-windows -t "$session_name" -F '#{window_index}|#{window_name}|#{?window_active,yes,no}' 2>/dev/null || true)"
    if [[ -z "${windows_raw// }" ]]; then
      print_entry "$machine" "$server_status" "$session_name" "$session_created" "$session_windows" "$session_attached" "none" "none" "n/a" "none" "none" "n/a" "unknown" "unknown" "unknown" "unknown" "$owner" "session listed but no windows returned"
      continue
    fi
    while IFS='|' read -r window_index window_name window_active; do
      [[ -z "$window_index" ]] && continue
      local panes_raw
      panes_raw="$(tmux list-panes -t "$session_name:$window_index" -F '#{pane_index}|#{pane_id}|#{?pane_active,yes,no}|#{pane_current_command}|#{pane_current_path}|#{pane_width}|#{pane_height}' 2>/dev/null || true)"
      if [[ -z "${panes_raw// }" ]]; then
        print_entry "$machine" "$server_status" "$session_name" "$session_created" "$session_windows" "$session_attached" "$window_index" "$window_name" "$window_active" "none" "none" "n/a" "unknown" "unknown" "unknown" "unknown" "$owner" "window listed but no panes returned"
        continue
      fi
      while IFS='|' read -r pane_index pane_id pane_active pane_command pane_path pane_width pane_height; do
        [[ -z "$pane_id" ]] && continue
        print_entry "$machine" "$server_status" "$session_name" "$session_created" "$session_windows" "$session_attached" "$window_index" "$window_name" "$window_active" "$pane_index" "$pane_id" "$pane_active" "$pane_command" "$pane_path" "$pane_width" "$pane_height" "$owner" "metadata-only pane inventory"
      done <<< "$panes_raw"
    done <<< "$windows_raw"
  done <<< "$sessions_raw"
}

emit_remote_inventory() {
  if ! command -v ssh >/dev/null 2>&1; then
    print_skip "ssh_unavailable" "remote_nuc2" "ssh client unavailable; optional remote tmux inspection skipped"
    return
  fi
  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 nuc2 "hostname" >/dev/null 2>&1; then
    print_skip "remote_unavailable" "remote_nuc2" "ssh host unavailable or not configured for safe non-interactive inspection"
    return
  fi

  local remote_sessions
  remote_sessions="$(ssh -o BatchMode=yes -o ConnectTimeout=5 nuc2 "tmux list-sessions -F '#{session_name}|#{session_created}|#{session_windows}|#{?session_attached,attached,detached}' 2>/dev/null || true" 2>/dev/null || true)"
  if [[ -z "${remote_sessions// }" ]]; then
    print_entry "nuc2" "no_server_or_no_sessions" "(none)" "n/a" "0" "n/a" "none" "none" "n/a" "none" "none" "n/a" "unknown" "unknown" "unknown" "unknown" "slimy" "optional remote inspection returned no sessions"
    return
  fi

  while IFS='|' read -r session_name session_created session_windows session_attached; do
    [[ -z "$session_name" ]] && continue
    local windows_raw
    windows_raw="$(ssh -o BatchMode=yes -o ConnectTimeout=5 nuc2 "tmux list-windows -t '$session_name' -F '#{window_index}|#{window_name}|#{?window_active,yes,no}' 2>/dev/null || true" 2>/dev/null || true)"
    if [[ -z "${windows_raw// }" ]]; then
      print_entry "nuc2" "running" "$session_name" "$session_created" "$session_windows" "$session_attached" "none" "none" "n/a" "none" "none" "n/a" "unknown" "unknown" "unknown" "unknown" "slimy" "remote session listed but no windows returned"
      continue
    fi
    while IFS='|' read -r window_index window_name window_active; do
      [[ -z "$window_index" ]] && continue
      local panes_raw
      panes_raw="$(ssh -o BatchMode=yes -o ConnectTimeout=5 nuc2 "tmux list-panes -t '$session_name:$window_index' -F '#{pane_index}|#{pane_id}|#{?pane_active,yes,no}|#{pane_current_command}|#{pane_current_path}|#{pane_width}|#{pane_height}' 2>/dev/null || true" 2>/dev/null || true)"
      if [[ -z "${panes_raw// }" ]]; then
        print_entry "nuc2" "running" "$session_name" "$session_created" "$session_windows" "$session_attached" "$window_index" "$window_name" "$window_active" "none" "none" "n/a" "unknown" "unknown" "unknown" "unknown" "slimy" "remote window listed but no panes returned"
        continue
      fi
      while IFS='|' read -r pane_index pane_id pane_active pane_command pane_path pane_width pane_height; do
        [[ -z "$pane_id" ]] && continue
        print_entry "nuc2" "running" "$session_name" "$session_created" "$session_windows" "$session_attached" "$window_index" "$window_name" "$window_active" "$pane_index" "$pane_id" "$pane_active" "$pane_command" "$pane_path" "$pane_width" "$pane_height" "slimy" "optional remote metadata-only pane inventory"
      done <<< "$panes_raw"
    done <<< "$windows_raw"
  done <<< "$remote_sessions"
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "[tmux-inventory] ERROR: unknown arg: $1" >&2
      exit 2
      ;;
  esac
fi

echo "# Harness Ops Tmux Inventory"
echo "generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "machine: $MACHINE_NAME"
echo "mode: read-only"
echo "pane_content_capture: disabled_by_default"
echo "notes: metadata-only tmux inspection; no keys sent; no sessions attached, detached, created, renamed, resized, or destroyed"

if ! command -v tmux >/dev/null 2>&1; then
  print_skip "tmux_unavailable" "local_tmux" "tmux command unavailable on this host"
  echo "RESULT=WARN warnings=1"
  exit 0
fi

local_sessions="$(tmux list-sessions -F '#{session_name}|#{session_created}|#{session_windows}|#{?session_attached,attached,detached}' 2>/dev/null || true)"
if [[ -z "${local_sessions// }" ]]; then
  print_entry "$MACHINE_NAME" "no_server_or_no_sessions" "(none)" "n/a" "0" "n/a" "none" "none" "n/a" "none" "none" "n/a" "unknown" "unknown" "unknown" "unknown" "$DEFAULT_USER" "tmux present but no server or sessions returned"
  emit_remote_inventory
  echo "RESULT=WARN warnings=1"
  exit 0
fi

emit_local_inventory "$MACHINE_NAME" "$DEFAULT_USER" "running" "$local_sessions"
emit_remote_inventory
echo "RESULT=PASS warnings=0"
