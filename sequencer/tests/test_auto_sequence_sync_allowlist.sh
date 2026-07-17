#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTO_SEQUENCE="$REPO_ROOT/sequencer/auto-sequence.sh"
AUTO_CLOSE="$REPO_ROOT/sequencer/auto-close.sh"
NOTIFIER_BASENAME="$(sed -n 's|^NOTIFIER=.*sequencer/\([^\"]*\)\".*|\1|p' "$AUTO_CLOSE")"
if [[ -z "$NOTIFIER_BASENAME" ]]; then
  printf 'FAIL: could not discover notifier basename from auto-close caller\n' >&2
  exit 1
fi
NOTIFIER="$REPO_ROOT/sequencer/$NOTIFIER_BASENAME"
ACCEPTED_BASE="b10cb8fd1e8ad1a3afbb7046e411923862715830"
TEMP="$(mktemp -d -t auto-sequence-sync-allowlist.XXXXXX)"
ORIGINAL_PATH="$PATH"
trap 'rm -rf "$TEMP"' EXIT

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (expected=$expected actual=$actual)"
  fi
}

assert_contains() {
  local path="$1" pattern="$2" label="$3"
  if grep -Eq -- "$pattern" "$path"; then
    pass "$label"
  else
    fail "$label (missing pattern: $pattern)"
  fi
}

assert_not_contains() {
  local path="$1" pattern="$2" label="$3"
  if grep -Eq -- "$pattern" "$path"; then
    fail "$label (unexpected pattern: $pattern)"
  else
    pass "$label"
  fi
}

make_case() {
  local name="$1" sync_rc="$2"
  CASE_DIR="$TEMP/$name"
  SMOKE_ROOT="$CASE_DIR/smoke"
  STUB_ROOT="$CASE_DIR/stubs"
  CALL_LOG="$CASE_DIR/calls.log"
  OUTPUT="$CASE_DIR/output.log"
  TEST_AUTO_SEQUENCE="$CASE_DIR/auto-sequence.sh"
  mkdir -p "$SMOKE_ROOT/kb-sessions" "$SMOKE_ROOT/logs" "$STUB_ROOT" "$CASE_DIR/notify-state" "$CASE_DIR/notify-logs"
  : > "$CALL_LOG"

  cat > "$SMOKE_ROOT/session-report.json" <<EOF
{"timestamp":"$name","feature_id":"cm1-$name","project":"slimy-harness","status":"completed","summary":"Synthetic CM-1 caller test","tests":{"passed":true}}
EOF
  printf '{"features":[]}\n' > "$SMOKE_ROOT/feature_list.json"
  printf '{"entries":[]}\n' > "$SMOKE_ROOT/failed-approaches.json"
  printf '{"reports":[]}\n' > "$SMOKE_ROOT/kb-sessions/harness-session-index.json"
  printf '{"unrelated":true}\n' > "$SMOKE_ROOT/kb-sessions/unrelated-third.json"

  cat > "$STUB_ROOT/sync-session-reports-to-nuc2.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'sync' >> "$CALL_LOG"
printf ' <%s>' "$@" >> "$CALL_LOG"
printf '\n' >> "$CALL_LOG"
exit "$SYNC_STUB_RC"
STUB

cat > "$STUB_ROOT/$NOTIFIER_BASENAME" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'notifier-invocation <%s>\n' "$*" >> "$CALL_LOG"
marker="$CASE_DIR/notify-state/synthetic.sent"
if [[ -f "$marker" ]]; then
  printf 'already_notified\n'
  exit 0
fi
curl -sS -o "$CASE_DIR/transport-response.json" "https://synthetic.invalid/notification"
printf 'synthetic notification recorded\n' > "$marker"
STUB

  cat > "$STUB_ROOT/auto-close.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'auto-close\n' >> "$CALL_LOG"
bash "$(dirname "$0")/$NOTIFIER_BASENAME" "$SESSION_REPORT"
STUB

  cat > "$STUB_ROOT/blocker-report.sh" <<'STUB'
#!/usr/bin/env bash
printf 'blocker-report\n' >> "$CALL_LOG"
STUB

  cat > "$STUB_ROOT/notify-blockers.sh" <<'STUB'
#!/usr/bin/env bash
printf 'notify-blockers\n' >> "$CALL_LOG"
STUB

  cat > "$STUB_ROOT/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'discord-post\n' >> "$CALL_LOG"
output_path=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" && $# -ge 2 ]]; then
    output_path="$2"
    shift 2
    continue
  fi
  shift
done
if [[ -n "$output_path" ]]; then
  printf '{"id":"synthetic-cm1-message"}\n' > "$output_path"
fi
printf '200'
STUB
  chmod +x "$STUB_ROOT"/*

  sed "s|SEQUNCER_DIR=\"/home/slimy/slimy-harness/sequencer\"|SEQUNCER_DIR=\"$STUB_ROOT\"|g" \
    "$AUTO_SEQUENCE" > "$TEST_AUTO_SEQUENCE"
  chmod +x "$TEST_AUTO_SEQUENCE"

  export CASE_DIR SMOKE_ROOT STUB_ROOT CALL_LOG OUTPUT NOTIFIER_BASENAME
  export SYNC_STUB_RC="$sync_rc"
  export HARNESS_SMOKE_ROOT="$SMOKE_ROOT"
  export HARNESS_SKIP_ENV_FILE=1
  export HARNESS_NOTIFIER_TEST_MODE=1
  export HARNESS_NOTIFIER_STUB_ROOT="$STUB_ROOT"
  export HARNESS_NOTIFY_STATE_DIR="$CASE_DIR/notify-state"
  export HARNESS_NOTIFY_LOG_DIR="$CASE_DIR/notify-logs"
  export HARNESS_ENV_FILE="$CASE_DIR/nonexistent.env"
  export HARNESS_NOTIFY_ATTACH_HTML=0
  export HARNESS_NOTIFY_ATTACH_JSON=0
  export HARNESS_NOTIFY_ON_SUCCESS=0
  export HARNESS_REPORT_BASE_URL="https://synthetic.invalid"
  export PATH="$STUB_ROOT:$ORIGINAL_PATH"

  bash "$TEST_AUTO_SEQUENCE" > "$OUTPUT" 2>&1
}

# The only runtime caller migration is the exact sync call in auto-sequence.
assert_contains "$AUTO_SEQUENCE" '--sync-authorized' "auto-sequence explicitly authorizes sync-only action"
assert_contains "$AUTO_SEQUENCE" '--file \"\$ARCHIVED_SESSION_REPORT\"' "allowlist includes the archived session report"
assert_contains "$AUTO_SEQUENCE" '--file \"\$KB_SESSIONS_DIR/harness-session-index\.json\"' "allowlist includes the session index"
assert_eq 0 "$(git -C "$REPO_ROOT" diff --quiet "$ACCEPTED_BASE" -- "$AUTO_CLOSE" "$NOTIFIER"; printf '%s' "$?")" "Discord notifier call sites remain byte-unchanged from accepted base"

# Success path: the stub receives exactly the bounded two-file allowlist.
make_case success 0
assert_eq 1 "$(grep -c '^sync ' "$CALL_LOG")" "sync helper is invoked once"
assert_contains "$CALL_LOG" '^sync <--sync-authorized> <--file> <.*/report-success\.json> <--file> <.*/harness-session-index\.json>$' "sync helper receives exact explicit two-file argument list"
assert_not_contains "$CALL_LOG" 'unrelated-third\.json' "unrelated report is excluded from sync allowlist"
assert_eq 2 "$(grep -c '^notifier-invocation ' "$CALL_LOG")" "indirect and direct Discord notifier call sites are both reachable"
assert_eq 1 "$(grep -c '^discord-post$' "$CALL_LOG")" "Discord dedupe permits exactly one stubbed POST"
assert_eq 1 "$(find "$CASE_DIR/notify-state" -maxdepth 1 -type f -name '*.sent' | wc -l | tr -d ' ')" "Discord dedupe writes exactly one marker"
assert_contains "$OUTPUT" 'already_notified' "second sequential notifier invocation is deduped"

# Failure path: sync failure stays non-fatal and closeout/Discord continue.
make_case sync_failure 71
assert_contains "$OUTPUT" 'Session report sync to NUC2 failed \(non-fatal\)' "sync helper failure is logged as non-fatal"
assert_contains "$CALL_LOG" '^auto-close$' "auto-close continues after sync failure"
assert_contains "$CALL_LOG" '^blocker-report$' "dispatch continues through blocker report after sync failure"
assert_eq 2 "$(grep -c '^notifier-invocation ' "$CALL_LOG")" "both Discord notifier call sites remain reachable after sync failure"
assert_eq 1 "$(grep -c '^discord-post$' "$CALL_LOG")" "sync failure does not cause duplicate stubbed Discord POSTs"

printf '\nRESULT: %s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
