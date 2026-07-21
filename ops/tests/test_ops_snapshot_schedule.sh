#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/schedules/schedule-registry.json"
SERVICE="$ROOT_DIR/ops/systemd/user/ops-snapshot-producer.service"
TIMER="${OPS_SNAPSHOT_TIMER_PATH:-$ROOT_DIR/ops/systemd/user/ops-snapshot-producer.timer}"
CLI="$ROOT_DIR/ops/harness-ops"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

timer_value() {
  local directive="$1"
  local -a values=()

  mapfile -t values < <(
    sed -n -E \
      "s/^[[:space:]]*${directive}[[:space:]]*=[[:space:]]*([^#;[:space:]]+)[[:space:]]*([#;].*)?$/\\1/p" \
      "$TIMER"
  )
  [[ "${#values[@]}" == "1" ]] || fail "expected exactly one $directive directive"
  printf '%s\n' "${values[0]}"
}

duration_to_seconds() {
  local duration="$1"
  local amount unit multiplier

  [[ "$duration" =~ ^([0-9]+)([[:alpha:]]*)$ ]] || return 1
  amount="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[2]}"
  case "$unit" in
    ''|s|sec|secs|second|seconds) multiplier=1 ;;
    min|mins|minute|minutes) multiplier=60 ;;
    h|hr|hrs|hour|hours) multiplier=3600 ;;
    d|day|days) multiplier=86400 ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$((10#$amount * multiplier))"
}

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

if grep -Fx 'ProtectKernelModules=true' "$SERVICE" >/dev/null; then
  fail "user service must not implicitly request a CAP_SYS_MODULE bounding-set drop"
fi
for directive in \
  'UMask=0027' \
  'NoNewPrivileges=true' \
  'ProtectSystem=full' \
  'ProtectKernelTunables=true' \
  'ProtectControlGroups=true' \
  'RestrictSUIDSGID=true'; do
  grep -Fx "$directive" "$SERVICE" >/dev/null || \
    fail "compatible service hardening changed: $directive"
done
pass "user-manager-compatible hardening avoids capability drops and preserves compatible restrictions"

if grep -Eq '^[[:space:]]*(OnBootSec|OnStartupSec|OnCalendar)[[:space:]]*=' "$TIMER"; then
  fail "timer contains a boot/startup-relative or calendar catch-up trigger"
fi
if grep -Eq '^[[:space:]]*Persistent[[:space:]]*=[[:space:]]*(1|yes|true|on)[[:space:]]*$' "$TIMER"; then
  fail "timer must not request persistent catch-up activation"
fi

first_delay="$(timer_value OnActiveSec)"
first_delay_seconds="$(duration_to_seconds "$first_delay")" || fail "timer first delay has an unsupported duration: $first_delay"
(( first_delay_seconds > 0 )) || fail "timer first delay must be positive"

recurring_interval="$(timer_value OnUnitActiveSec)"
recurring_interval_seconds="$(duration_to_seconds "$recurring_interval")" || \
  fail "timer recurring interval has an unsupported duration: $recurring_interval"
(( recurring_interval_seconds > 0 )) || fail "timer recurring interval must be positive"
(( recurring_interval_seconds < 900 )) || fail "timer recurring interval must remain below the 900-second freshness window"

grep -Fx 'Unit=ops-snapshot-producer.service' "$TIMER" >/dev/null || fail "timer/service pair does not match"
pass "timer defers first firing from activation and recurs within the freshness window"
pass "enabling and starting the timer cannot imply an immediate producer start"

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
