#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/schedules/schedule-registry.json"
SERVICE="$ROOT_DIR/ops/systemd/user/ops-snapshot-producer.service"
TIMER="$ROOT_DIR/ops/systemd/user/ops-snapshot-producer.timer"
CLI="$ROOT_DIR/ops/harness-ops"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

entry_count="$(jq '[.entries[] | select(.schedule_id == "ops-snapshot-producer-timer")] | length' "$REGISTRY")"
[[ "$entry_count" == "1" ]] || fail "expected exactly one ops snapshot timer registry entry"
pass "exactly one ops snapshot timer target is registered"

jq -e '.entries[] | select(.schedule_id == "ops-snapshot-producer-timer") |
  .target_machine == "nuc1" and
  .owner_scope == "user" and
  .schedule_type == "user_systemd_timer" and
  .source_path_or_unit == "ops-snapshot-producer.timer" and
  .managed_mode == "managed_candidate" and
  .risk_level == "low" and
  .live_enable_allowed == false and
  .live_disable_allowed == false and
  .live_run_once_allowed == false and
  (.notes | contains("producer is read-only")) and
  (.notes | contains("separate activation phase"))' "$REGISTRY" >/dev/null || \
  fail "ops snapshot timer registry safety contract changed"
pass "registry pins NUC1 user timer, low risk, read-only producer, and all live flags false"

grep -Fx 'Type=oneshot' "$SERVICE" >/dev/null || fail "service is not oneshot"
grep -Fx 'WorkingDirectory=/home/slimy/slimy-harness' "$SERVICE" >/dev/null || fail "WorkingDirectory is not absolute and exact"
grep -Fx 'ExecStart=/home/slimy/slimy-harness/ops/snapshot-producer.sh' "$SERVICE" >/dev/null || fail "ExecStart is not absolute and exact"
if grep -Eq '^(Environment|EnvironmentFile|User|Restart)=' "$SERVICE"; then
  fail "service contains environment, identity, or restart directives outside the contract"
fi
pass "service is an absolute-path oneshot with no embedded environment or restart policy"

grep -Fx 'OnUnitActiveSec=10min' "$TIMER" >/dev/null || fail "timer cadence is not 10 minutes"
grep -Fx 'Unit=ops-snapshot-producer.service' "$TIMER" >/dev/null || fail "timer/service pair does not match"
pass "timer uses the explicit matching service on a 10-minute cadence"

"$CLI" schedule plan ops-snapshot-producer-timer > "$TEMP/plan.out"
"$CLI" schedule dry-run ops-snapshot-producer-timer --action enable > "$TEMP/enable.out"
"$CLI" schedule dry-run ops-snapshot-producer-timer --action disable > "$TEMP/disable.out"
"$CLI" schedule run-once-dry-run ops-snapshot-producer-timer > "$TEMP/run-once.out"
for output in "$TEMP/plan.out" "$TEMP/enable.out" "$TEMP/disable.out" "$TEMP/run-once.out"; do
  grep -Fx 'RESULT=PASS' "$output" >/dev/null || fail "schedule preview did not pass: $output"
done
grep -F 'WOULD_RUN: systemctl --user enable ops-snapshot-producer.timer' "$TEMP/enable.out" >/dev/null || fail "enable preview missing timer"
grep -F 'WOULD_RUN: systemctl --user start ops-snapshot-producer.service' "$TEMP/run-once.out" >/dev/null || fail "run-once preview missing service"
pass "dry-run controls describe the staged timer without executing mutations"

echo "ops snapshot schedule contract PASS"
