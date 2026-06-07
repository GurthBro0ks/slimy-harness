#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/schedules/schedule-registry.json"

usage() {
  cat <<'USG'
schedule-plan.sh — read-only schedule control planner

Usage:
  ops/harness-ops schedule plan <schedule_id>

Behavior:
  - validates schedule_id against schedule-registry.json
  - prints schedule metadata and future safeguards
  - does not mutate cron, timers, services, or tmux
USG
}

redact_text() {
  local text="$1"
  local hook_host='dis''cord'
  local hook_app='app'
  local hook_path='/api/webhooks/'
  printf '%s' "$text" | sed -E \
    -e "s#https://${hook_host}(${hook_app})?\.com${hook_path}[A-Za-z0-9/_-]+#[REDACTED_DISCORD_WEBHOOK]#g" \
    -e 's#(https?://)[^ /:@]+:[^ /@]+@#\1[REDACTED]@#g' \
    -e 's/\b([Bb]earer)[[:space:]]+[A-Za-z0-9._~+\/=:-]+/\1 [REDACTED]/g' \
    -e 's/\b([A-Za-z_][A-Za-z0-9_]*(SECRET|TOKEN|KEY|PASSWORD|WEBHOOK|COOKIE|SESSION)[A-Za-z0-9_]*)=([^[:space:]]+)/\1=[REDACTED]/g'
}

require_tools() {
  for cmd in jq sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "[schedule-plan] ERROR: missing required command: $cmd" >&2
      exit 1
    fi
  done
}

fetch_entry_json() {
  local schedule_id="$1"
  jq -c --arg id "$schedule_id" '.entries[] | select(.schedule_id == $id)' "$REGISTRY"
}

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
esac

require_tools

if [[ ! -f "$REGISTRY" ]]; then
  echo "[schedule-plan] ERROR: missing registry: $REGISTRY" >&2
  exit 1
fi

SCHEDULE_ID="${1:-}"
if [[ -z "$SCHEDULE_ID" ]]; then
  echo "[schedule-plan] ERROR: missing schedule_id" >&2
  usage
  exit 2
fi

ENTRY_JSON="$(fetch_entry_json "$SCHEDULE_ID")"
if [[ -z "${ENTRY_JSON:-}" ]]; then
  echo "[schedule-plan] ERROR: unknown schedule_id: $SCHEDULE_ID" >&2
  echo "[schedule-plan] HINT: use a schedule_id listed in ops/schedules/schedule-registry.json" >&2
  exit 2
fi

FIELD() {
  local key="$1"
  printf '%s' "$ENTRY_JSON" | jq -r ".${key}"
}

RED_FIELD() {
  local key="$1"
  redact_text "$(FIELD "$key")"
}

MACHINE="$(FIELD target_machine)"
MANAGED_MODE="$(FIELD managed_mode)"
RISK_LEVEL="$(FIELD risk_level)"
APPROVAL_LEVEL="$(FIELD approval_level)"
SCHEDULE_TYPE="$(FIELD schedule_type)"

echo "schedule_id: $(FIELD schedule_id)"
echo "description: $(RED_FIELD description)"
echo "target_machine: $MACHINE"
echo "owner_scope: $(FIELD owner_scope)"
echo "source_type: $SCHEDULE_TYPE"
echo "source_path_or_unit: $(RED_FIELD source_path_or_unit)"
echo "managed_mode: $MANAGED_MODE"
echo "risk_level: $RISK_LEVEL"
echo "approval_level: $APPROVAL_LEVEL"
echo "live_enable_allowed: $(FIELD live_enable_allowed)"
echo "live_disable_allowed: $(FIELD live_disable_allowed)"
echo "live_run_once_allowed: $(FIELD live_run_once_allowed)"

if [[ "$MANAGED_MODE" == "managed_candidate" && "$MACHINE" == "nuc1" ]]; then
  echo "live_mutation_currently_allowed: no (Ops-4B dry-run-only pass)"
else
  echo "live_mutation_currently_allowed: no"
fi

echo "required_future_safeguards:"
echo "COPY_ONLY: --confirm"
echo "COPY_ONLY: --proof-dir <path>"
echo "COPY_ONLY: --ticket <change-id>"
if [[ "$RISK_LEVEL" == "high" ]]; then
  echo "COPY_ONLY: --explicit-approval <id>"
fi
echo "COPY_ONLY: snapshot current schedule state before any future mutation"
echo "COPY_ONLY: run plan + dry-run + controls-validate before any future mutation"
echo "COPY_ONLY: refuse unknown schedules and raw line edits"
echo "notes: $(RED_FIELD notes)"
echo "RESULT=PASS"
