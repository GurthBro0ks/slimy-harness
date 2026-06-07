#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/schedules/schedule-registry.json"

usage() {
  cat <<'USG'
schedule-dry-run.sh — read-only schedule mutation preview

Usage:
  ops/harness-ops schedule dry-run <schedule_id> --action enable|disable

Behavior:
  - validates schedule_id against registry
  - prints future commands as WOULD_RUN only
  - does not execute cron/systemctl/service commands
USG
}

require_tools() {
  for cmd in jq sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "[schedule-dry-run] ERROR: missing required command: $cmd" >&2
      exit 1
    fi
  done
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

entry_json() {
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
  echo "[schedule-dry-run] ERROR: missing registry: $REGISTRY" >&2
  exit 1
fi

SCHEDULE_ID="${1:-}"
shift || true

ACTION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      ACTION="${2:-}"
      shift 2
      ;;
    *)
      echo "[schedule-dry-run] ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$SCHEDULE_ID" ]]; then
  echo "[schedule-dry-run] ERROR: missing schedule_id" >&2
  usage
  exit 2
fi

if [[ "$ACTION" != "enable" && "$ACTION" != "disable" ]]; then
  echo "[schedule-dry-run] ERROR: --action must be enable or disable" >&2
  exit 2
fi

ENTRY_JSON="$(entry_json "$SCHEDULE_ID")"
if [[ -z "${ENTRY_JSON:-}" ]]; then
  echo "[schedule-dry-run] ERROR: unknown schedule_id: $SCHEDULE_ID" >&2
  exit 2
fi

FIELD() {
  local key="$1"
  printf '%s' "$ENTRY_JSON" | jq -r ".${key}"
}

MACHINE="$(FIELD target_machine)"
OWNER_SCOPE="$(FIELD owner_scope)"
SCHEDULE_TYPE="$(FIELD schedule_type)"
MANAGED_MODE="$(FIELD managed_mode)"
RISK_LEVEL="$(FIELD risk_level)"

echo "schedule_id: $(FIELD schedule_id)"
echo "action: $ACTION"
echo "target_machine: $MACHINE"
echo "owner_scope: $OWNER_SCOPE"
echo "schedule_type: $SCHEDULE_TYPE"
echo "managed_mode: $MANAGED_MODE"
echo "risk_level: $RISK_LEVEL"

if [[ "$MANAGED_MODE" == "read_only" ]]; then
  echo "[schedule-dry-run] REFUSE: schedule is read_only in this pass." >&2
  echo "RESULT=REFUSED"
  exit 1
fi

if [[ "$MACHINE" != "nuc1" || "$OWNER_SCOPE" != "user" ]]; then
  echo "[schedule-dry-run] REFUSE: remote/root/system targets are out of scope for Ops-4B." >&2
  echo "RESULT=REFUSED"
  exit 1
fi

if [[ "$SCHEDULE_TYPE" != "user_crontab" && "$SCHEDULE_TYPE" != "user_systemd_timer" ]]; then
  echo "[schedule-dry-run] REFUSE: unsupported schedule_type for dry-run controls: $SCHEDULE_TYPE" >&2
  echo "RESULT=REFUSED"
  exit 1
fi

if [[ "$RISK_LEVEL" == "high" ]]; then
  echo "[schedule-dry-run] REFUSE: high-risk entries remain read-only in Ops-4B." >&2
  echo "RESULT=REFUSED"
  exit 1
fi

echo "future_required_flags:"
echo "COPY_ONLY: --confirm"
echo "COPY_ONLY: --proof-dir <path>"
echo "COPY_ONLY: --ticket <change-id>"
echo "COPY_ONLY: run ops/harness-ops schedule controls-validate first"

if [[ "$SCHEDULE_TYPE" == "user_systemd_timer" ]]; then
  UNIT="$(FIELD source_path_or_unit)"
  SERVICE_UNIT="${UNIT%.timer}.service"
  echo "future_mutation_preview:"
  if [[ "$ACTION" == "enable" ]]; then
    echo "WOULD_RUN: systemctl --user enable $UNIT"
    echo "WOULD_RUN: systemctl --user start $UNIT"
    echo "COPY_ONLY: verify next trigger with systemctl --user list-timers --all --no-pager"
  else
    echo "WOULD_RUN: systemctl --user stop $UNIT"
    echo "WOULD_RUN: systemctl --user disable $UNIT"
    echo "COPY_ONLY: verify disabled state with systemctl --user list-unit-files --type=timer"
  fi
  echo "COPY_ONLY: inspect service pair $SERVICE_UNIT before live approvals"
elif [[ "$SCHEDULE_TYPE" == "user_crontab" ]]; then
  SAFE_ID="$(printf '%s' "$SCHEDULE_ID" | tr -c 'a-zA-Z0-9._-' '_')"
  echo "future_mutation_preview:"
  echo "WOULD_RUN: crontab -l > \"<proof_dir>/crontab.before.$SAFE_ID\""
  echo "WOULD_RUN: python3 <registry-aware-template-tool> --schedule-id $SCHEDULE_ID --action $ACTION > \"<proof_dir>/crontab.after.$SAFE_ID\""
  echo "WOULD_RUN: crontab \"<proof_dir>/crontab.after.$SAFE_ID\""
  echo "COPY_ONLY: verify resulting schedule with crontab -l"
fi

echo "notes: $(redact_text "$(FIELD notes)")"
echo "RESULT=PASS"
