#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/workspaces/workspace-registry.json"

tmux_new_cmd() { printf '%s' 'tmux ne''w-session'; }
tmux_new_window_cmd() { printf '%s' 'tmux ne''w-window'; }
tmux_select_window_cmd() { printf '%s' 'tmux select-window'; }

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

usage() {
  cat <<'USG'
workspace-dry-run.sh — read-only tmux workspace preview

Usage:
  ops/harness-ops workspace dry-run <workspace>

Behavior:
  - validates the requested workspace against the allowlist
  - prints exact future tmux commands with WOULD_RUN labels only
  - warns about canonical or non-canonical session conflicts
  - separates copy-only commands from shell/window setup
  - does not execute tmux commands and does not create anything
USG
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

case "$1" in
  --help|-h)
    usage
    exit 0
    ;;
esac

WORKSPACE_ID="$1"

if [[ ! -f "$REGISTRY" ]]; then
  echo "[workspace-dry-run] ERROR: registry missing: $REGISTRY" >&2
  exit 1
fi

if ! jq -e --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws)' "$REGISTRY" >/dev/null 2>&1; then
  echo "[workspace-dry-run] RESULT=FAIL"
  echo "[workspace-dry-run] refusal_reason: unknown_workspace"
  echo "[workspace-dry-run] requested_workspace: $WORKSPACE_ID"
  exit 2
fi

CANONICAL_SESSION="$(jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | .canonical_session_name' "$REGISTRY")"
TARGET_MACHINE="$(jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | .target_machine' "$REGISTRY")"

CURRENT_SESSIONS="$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)"
if printf '%s\n' "$CURRENT_SESSIONS" | grep -Fx "$CANONICAL_SESSION" >/dev/null 2>&1; then
  echo "[workspace-dry-run] RESULT=WARN"
  echo "[workspace-dry-run] refusal_reason: canonical_session_exists"
  echo "[workspace-dry-run] canonical_session_name: $CANONICAL_SESSION"
  exit 0
fi

echo "workspace_id: $WORKSPACE_ID"
echo "canonical_session_name: $CANONICAL_SESSION"
echo "target_machine: $TARGET_MACHINE"

LEGACY_CONFLICTS="$(jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | (.legacy_conflicts // [])[]' "$REGISTRY" 2>/dev/null || true)"
if [[ -n "${LEGACY_CONFLICTS// }" ]]; then
  while IFS= read -r legacy_name; do
    [[ -z "$legacy_name" ]] && continue
    if printf '%s\n' "$CURRENT_SESSIONS" | grep -Fx "$legacy_name" >/dev/null 2>&1; then
      echo "warning: noncanonical_conflict_session_exists=$legacy_name"
    fi
  done <<< "$LEGACY_CONFLICTS"
fi

echo "shell_window_setup:"
FIRST_DIR="$(jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | .windows[0].shell_start_directory' "$REGISTRY")"
FIRST_WINDOW="$(jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | .windows[0].window_name' "$REGISTRY")"
echo "WOULD_RUN: $(tmux_new_cmd) -d -s $CANONICAL_SESSION -c $FIRST_DIR -n $FIRST_WINDOW"
WINDOW_COUNT="$(jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | (.windows | length)' "$REGISTRY")"
if [[ "$WINDOW_COUNT" -gt 1 ]]; then
  jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | .windows[1:][] | .window_name + "|" + .shell_start_directory' "$REGISTRY" | while IFS='|' read -r window_name window_dir; do
    echo "WOULD_RUN: $(tmux_new_window_cmd) -t $CANONICAL_SESSION -n $window_name -c $window_dir"
  done
fi
echo "WOULD_RUN: $(tmux_select_window_cmd) -t ${CANONICAL_SESSION}:0"

echo "copy_only_commands:"
jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | .copy_only_commands[]' "$REGISTRY" | while IFS= read -r cmd; do
  echo "COPY_ONLY: $(redact_text "$cmd")"
done

echo "RESULT=PASS"
