#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WATCHDOG="$REPO_ROOT/sequencer/harness-route-auth-watchdog.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

bash -n "$WATCHDOG"
pass "watchdog syntax"

HARNESS_ROUTE_AUTH_WATCHDOG_LIB_ONLY=1 source "$WATCHDOG"

write_body() {
  local name="$1"
  local content="$2"
  printf '%s\n' "$content" > "$TEMP/$name"
  printf '%s\n' "$TEMP/$name"
}

detail_body="$(write_body detail '{"session_id":"s1","feature_id":"f1","proof_dir":"/tmp/proof"}')"
if body_has_detail_markers "$detail_body"; then
  pass "detail marker detected"
else
  fail "detail marker missed"
fi

login_return_body="$(write_body login_return '<input name="returnTo" value="/reports/sessions/report-proof-example.json"><input type="password">')"
if body_has_detail_markers "$login_return_body"; then
  fail "login returnTo path treated as report detail"
else
  pass "login returnTo path is not a detail marker"
fi

hook_like="$(printf 'https://hooks.example/%s/%s' 'api/webhooks' '1234567890/abcdefghijklmnopqrstuvwxyz')"
secret_body="$(write_body secret "$hook_like")"
if body_has_secret_markers "$secret_body"; then
  pass "secret-shaped marker detected"
else
  fail "secret-shaped marker missed"
fi

plain_body="$(write_body plain '<html><title>Owner Login</title><input type="password"></html>')"
if is_logged_out_blocked "200" "https://habitat.slimyai.xyz/login" "$plain_body"; then
  pass "login page treated as blocked"
else
  fail "login page was not treated as blocked"
fi

if is_logged_out_blocked "401" "https://habitat.slimyai.xyz/" "$plain_body"; then
  pass "401 treated as blocked"
else
  fail "401 was not treated as blocked"
fi

unblocked_body="$(write_body unblocked '<html><h1>Harness Report</h1><p>private route content</p></html>')"
if is_logged_out_blocked "200" "https://harness.slimyai.xyz/reports" "$unblocked_body"; then
  fail "plain 200 private page treated as blocked"
else
  pass "plain 200 private page treated as unblocked"
fi

if status_is_runtime_issue "404" && status_is_runtime_issue "500" && status_is_runtime_issue "000"; then
  pass "runtime issue statuses detected"
else
  fail "runtime issue status helper missed expected status"
fi

for forbidden in \
  "$(printf '%s_%s' 'DISCORD' 'WEBHOOK')" \
  "$(printf '%s_%s' 'WEBHOOK' 'URL')" \
  "$(printf '%s%s' 'notify-proof-dir-' 'complete.sh')" \
  "$(printf '%s%s' 'notify-session-' 'complete.sh')"
do
  if grep -RIF -- "$forbidden" "$WATCHDOG" "$REPO_ROOT/sequencer/tests" >/dev/null 2>&1; then
    fail "forbidden notifier or hook-env reference found: $forbidden"
  fi
done
pass "no hook env or notifier references in watchdog validation path"

"$WATCHDOG" --help >/dev/null
pass "help output"

echo "harness-route-auth-watchdog PASS"
