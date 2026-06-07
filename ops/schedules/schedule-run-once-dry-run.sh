#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/schedules/schedule-registry.json"

usage() {
  cat <<'USG'
schedule-run-once-dry-run.sh — read-only one-shot execution preview

Usage:
  ops/harness-ops schedule run-once-dry-run <schedule_id>

Behavior:
  - validates schedule_id against registry
  - prints future one-shot trigger commands as WOULD_RUN only
  - executes nothing
USG
}

require_tools() {
  for cmd in jq sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "[schedule-run-once-dry-run] ERROR: missing required command: $cmd" >&2
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
  echo "[schedule-run-once-dry-run] ERROR: missing registry: $REGISTRY" >&2
  exit 1
fi

SCHEDULE_ID="${1:-}"
if [[ -z "$SCHEDULE_ID" ]]; then
  echo "[schedule-run-once-dry-run] ERROR: missing schedule_id" >&2
  usage
  exit 2
fi

ENTRY_JSON="$(entry_json "$SCHEDULE_ID")"
if [[ -z "${ENTRY_JSON:-}" ]]; then
  echo "[schedule-run-once-dry-run] ERROR: unknown schedule_id: $SCHEDULE_ID" >&2
  exit 2
fi

FIELD() {
  local key="$1"
  printf '%s' "$ENTRY_JSON" | jq -r ".${key}"
}

MACHINE="$(FIELD target_machine)"
OWNER_SCOPE="$(FIELD owner_scope)"
SCHEDULE_TYPE="$(FIELD schedule_type)"
RISK_LEVEL="$(FIELD risk_level)"

echo "schedule_id: $(FIELD schedule_id)"
echo "target_machine: $MACHINE"
echo "owner_scope: $OWNER_SCOPE"
echo "schedule_type: $SCHEDULE_TYPE"
echo "risk_level: $RISK_LEVEL"

if [[ "$MACHINE" != "nuc1" || "$OWNER_SCOPE" != "user" ]]; then
  echo "[schedule-run-once-dry-run] REFUSE: remote/root/system targets are read-only in Ops-4B." >&2
  echo "RESULT=REFUSED"
  exit 1
fi

if [[ "$RISK_LEVEL" == "high" ]]; then
  echo "[schedule-run-once-dry-run] REFUSE: high-risk schedule run-once preview blocked in Ops-4B." >&2
  echo "RESULT=REFUSED"
  exit 1
fi

echo "future_required_flags:"
echo "COPY_ONLY: --confirm"
echo "COPY_ONLY: --proof-dir <path>"
echo "COPY_ONLY: --ticket <change-id>"

if [[ "$SCHEDULE_TYPE" == "user_systemd_timer" ]]; then
  UNIT="$(FIELD source_path_or_unit)"
  SERVICE_UNIT="${UNIT%.timer}.service"
  echo "future_run_once_preview:"
  echo "WOULD_RUN: systemctl --user start $SERVICE_UNIT"
  echo "COPY_ONLY: inspect logs via journalctl --user -u $SERVICE_UNIT --since '15 minutes ago'"
elif [[ "$SCHEDULE_TYPE" == "user_crontab" ]]; then
  SOURCE="$(FIELD source_path_or_unit)"
  echo "future_run_once_preview:"
  echo "WOULD_RUN: <invoke-registered-cron-wrapper> --schedule-id $SCHEDULE_ID --source \"$(redact_text "$SOURCE")\""
  echo "COPY_ONLY: capture output under proof-dir and redact secrets"
else
  echo "[schedule-run-once-dry-run] REFUSE: unsupported schedule_type for run-once preview: $SCHEDULE_TYPE" >&2
  echo "RESULT=REFUSED"
  exit 1
fi

echo "notes: $(redact_text "$(FIELD notes)")"
echo "RESULT=PASS"
