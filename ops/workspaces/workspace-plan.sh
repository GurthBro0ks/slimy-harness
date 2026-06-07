#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/workspaces/workspace-registry.json"

usage() {
  cat <<'USG'
workspace-plan.sh — read-only workspace planner

Usage:
  ops/harness-ops workspace plan <workspace>

Behavior:
  - validates the requested workspace against the allowlist
  - prints canonical future session name, target machine, target paths,
    proposed windows, shell start directories, and copy-only commands
  - prints refusal reasons for unknown workspaces
  - does not call tmux mutation commands and does not create anything
USG
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[workspace-plan] ERROR: required command missing: $1" >&2
    exit 1
  }
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

json_get() {
  local ws="$1"
  local filter="$2"
  jq -r --arg ws "$ws" ".workspaces[] | select(.workspace_id == \$ws) | ${filter}" "$REGISTRY"
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
require_cmd jq

if [[ ! -f "$REGISTRY" ]]; then
  echo "[workspace-plan] ERROR: registry missing: $REGISTRY" >&2
  exit 1
fi

if ! jq . "$REGISTRY" >/dev/null 2>&1; then
  echo "[workspace-plan] ERROR: registry is not valid JSON" >&2
  exit 1
fi

if ! jq -e --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws)' "$REGISTRY" >/dev/null 2>&1; then
  echo "[workspace-plan] RESULT=FAIL"
  echo "[workspace-plan] refusal_reason: unknown_workspace"
  echo "[workspace-plan] requested_workspace: $WORKSPACE_ID"
  echo "[workspace-plan] allowed_workspaces: $(jq -r '.workspaces[].workspace_id' "$REGISTRY" | paste -sd ',')"
  exit 2
fi

CANONICAL_SESSION="$(json_get "$WORKSPACE_ID" '.canonical_session_name')"
TARGET_MACHINE="$(json_get "$WORKSPACE_ID" '.target_machine')"
DEFAULT_BEHAVIOR="$(json_get "$WORKSPACE_ID" '.default_behavior')"
RISK="$(json_get "$WORKSPACE_ID" '.risk')"
NOTES="$(json_get "$WORKSPACE_ID" '.notes')"

echo "workspace_id: $WORKSPACE_ID"
echo "canonical_session_name: $CANONICAL_SESSION"
echo "target_machine: $TARGET_MACHINE"
echo "default_behavior: $DEFAULT_BEHAVIOR"
echo "live_create_allowed: false"
echo "live_reuse_allowed: false"
echo "risk: $RISK"
echo "notes: $(redact_text "$NOTES")"
echo "target_paths:"
jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | .target_paths[] | "  - " + .' "$REGISTRY"
echo "windows:"
jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | .windows[] | "  - name=" + .window_name + " dir=" + .shell_start_directory' "$REGISTRY"
echo "copy_only_commands:"
jq -r --arg ws "$WORKSPACE_ID" '.workspaces[] | select(.workspace_id == $ws) | .copy_only_commands[] | "  - " + .' "$REGISTRY" | while IFS= read -r line; do
  echo "$(redact_text "$line")"
done
echo "RESULT=PASS"
