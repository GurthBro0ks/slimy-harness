#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/schedules/schedule-registry.json"
CLI="$ROOT_DIR/ops/harness-ops"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

if ! command -v jq >/dev/null 2>&1; then
  fail "missing jq"
fi

jq . "$REGISTRY" >/dev/null
pass "registry JSON parses"

entry="$(jq -c '.entries[] | select(.schedule_id == "harness-watchdog-cron")' "$REGISTRY")"
if [[ -z "$entry" ]]; then
  fail "harness-watchdog-cron entry missing"
fi
pass "harness-watchdog-cron entry present"

source_path="$(printf '%s' "$entry" | jq -r '.source_path_or_unit')"
inventory_ref="$(printf '%s' "$entry" | jq -r '.current_inventory_ref')"

if [[ "$source_path" != *"sequencer/harness-route-auth-watchdog.sh"* ]]; then
  fail "watchdog source path does not reference sequencer/harness-route-auth-watchdog.sh"
fi
pass "watchdog source path references current sequencer script"

if [[ "$source_path" != *"--proof-dir <proof_dir>/harness-watchdog-cron"* ]]; then
  fail "watchdog source path missing explicit proof-dir placeholder"
fi
pass "watchdog source path carries explicit proof-dir placeholder"

old_watchdog_path="$(printf '%s/%s/%s' 'ned-clawd' 'scripts' 'watchdog.sh')"
if [[ "$entry" == *"$old_watchdog_path"* || ( "$entry" == *"ned-clawd"* && "$entry" == *"watchdog.sh"* ) ]]; then
  fail "stale ned-clawd watchdog path still referenced by harness-watchdog-cron"
fi
pass "stale ned-clawd watchdog path absent from harness-watchdog-cron"

if [[ "$inventory_ref" != *"*/15 * * * *"* ]]; then
  fail "watchdog dry-run cadence marker changed"
fi
pass "watchdog dry-run cadence marker preserved"

if ! printf '%s' "$entry" | jq -e '
  .live_enable_allowed == false and
  .live_disable_allowed == false and
  .live_run_once_allowed == false
' >/dev/null; then
  fail "watchdog live flags are not all false"
fi
pass "watchdog live flags remain false"

"$CLI" schedule controls-validate > "$TEMP/controls.out"
if ! grep -q 'RESULT=PASS' "$TEMP/controls.out"; then
  cat "$TEMP/controls.out"
  fail "schedule controls validation did not pass"
fi
pass "schedule controls validation passes"

"$CLI" schedule run-once-dry-run harness-watchdog-cron > "$TEMP/run-once.out"
if ! grep -q 'RESULT=PASS' "$TEMP/run-once.out"; then
  cat "$TEMP/run-once.out"
  fail "run-once dry-run did not pass"
fi
if ! grep -q 'WOULD_RUN:' "$TEMP/run-once.out"; then
  cat "$TEMP/run-once.out"
  fail "run-once dry-run missing WOULD_RUN marker"
fi
if ! grep -q 'sequencer/harness-route-auth-watchdog.sh' "$TEMP/run-once.out"; then
  cat "$TEMP/run-once.out"
  fail "run-once dry-run output missing current watchdog path"
fi
if ! grep -q -- '--proof-dir <proof_dir>/harness-watchdog-cron' "$TEMP/run-once.out"; then
  cat "$TEMP/run-once.out"
  fail "run-once dry-run output missing proof-dir placeholder"
fi

for forbidden in \
  "$(printf '%s_%s' 'DISCORD' 'WEBHOOK')" \
  "$(printf '%s_%s' 'WEBHOOK' 'URL')" \
  "$(printf '%s%s' 'notify-proof-dir-' 'complete.sh')" \
  "$(printf '%s%s' 'notify-session-' 'complete.sh')"
do
  if grep -F -- "$forbidden" "$TEMP/run-once.out" >/dev/null 2>&1; then
    cat "$TEMP/run-once.out"
    fail "run-once dry-run output contains notifier or hook marker: $forbidden"
  fi
done
pass "run-once dry-run output stays no-Discord/no-notifier"

echo "harness-watchdog-registry PASS"
