#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ADAPTER="$REPO_ROOT/sequencer/$(printf '%s%s' 'notify-proof-dir-' 'complete.sh')"
NOTIFIER="$REPO_ROOT/sequencer/$(printf '%s%s' 'notify-session-' 'complete.sh')"
SYNC_HELPER="$REPO_ROOT/sequencer/sync-session-reports-to-nuc2.sh"
TEMP="$(mktemp -d -t notifier-sync-modes.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT

PASS=0
FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then pass "$label"; else fail "$label (expected=$expected actual=$actual)"; fi
}
assert_contains() {
  local path="$1" pattern="$2" label="$3"
  if grep -Eq -- "$pattern" "$path"; then pass "$label"; else fail "$label (missing $pattern)"; fi
}
assert_not_contains() {
  local path="$1" pattern="$2" label="$3"
  if grep -Eq -- "$pattern" "$path"; then fail "$label (found $pattern)"; else pass "$label"; fi
}
count_log() {
  local pattern="$1"
  grep -Ec -- "$pattern" "$CALL_LOG" 2>/dev/null || true
}
marker_count() {
  local pattern="$1"
  find "$STATE" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l | tr -d ' '
}

make_stubs() {
  mkdir -p "$STUBS"
  cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl' >> "$CALL_LOG"
out=""
while [[ $# -gt 0 ]]; do
  printf ' <%s>' "$1" >> "$CALL_LOG"
  if [[ "$1" == "-o" && $# -ge 2 ]]; then
    out="$2"
  fi
  shift
done
printf '\n' >> "$CALL_LOG"
[[ -z "$out" ]] || printf '{"id":"synthetic-message-id"}\n' > "$out"
printf '%s' "${CURL_STUB_HTTP:-200}"
STUB
  cat > "$STUBS/ssh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh' >> "$CALL_LOG"
printf ' <%s>' "$@" >> "$CALL_LOG"
printf '\n' >> "$CALL_LOG"
[[ "${SSH_STUB_FAIL:-0}" != "1" ]]
STUB
  cat > "$STUBS/rsync" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'rsync' >> "$CALL_LOG"
printf ' <%s>' "$@" >> "$CALL_LOG"
printf '\n' >> "$CALL_LOG"
[[ "${RSYNC_STUB_FAIL:-0}" != "1" ]]
STUB
  cat > "$STUBS/scp" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'scp' >> "$CALL_LOG"
printf ' <%s>' "$@" >> "$CALL_LOG"
printf '\n' >> "$CALL_LOG"
exit 99
STUB
  cat > "$STUBS/notifier-wrapper" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "notifier-helper" >> "$CALL_LOG"
exec bash "$ACTUAL_NOTIFIER" "$@"
STUB
  cat > "$STUBS/sync-wrapper" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "sync-helper" >> "$CALL_LOG"
exec bash "$ACTUAL_SYNC" "$@"
STUB
  chmod +x "$STUBS"/*
}

new_case() {
  local name="$1"
  CASE="$TEMP/$name"
  PROOF="$CASE/proof_$name"
  SESSIONS="$CASE/sessions"
  STATE="$CASE/state"
  LOGS="$CASE/logs"
  STUBS="$CASE/stubs"
  CALL_LOG="$CASE/calls.log"
  ENV_FILE="$CASE/synthetic-notifier.env"
  mkdir -p "$PROOF" "$SESSIONS" "$STATE" "$LOGS"
  : > "$CALL_LOG"
  cat > "$PROOF/RESULT.md" <<EOF
PHASE=test-$name
RESULT=PASS
VALIDATION=tests pass
SUMMARY=Synthetic notifier boundary test for $name.
EOF
  cat > "$PROOF/harness-metadata.json" <<EOF
{"feature_id":"test-$name","task_title":"Synthetic $name","status":"completed","agent":"codex","source_nuc":"nuc1","repo_name":"slimy-harness","repo_path":"$REPO_ROOT","summary":"Synthetic boundary test."}
EOF
  printf '%s\n' \
    'printf '\''env-loader\n'\'' >> "$CALL_LOG"' \
    "$(printf '%s_%s=%s' 'DISCORD_HARNESS_WEBHOOK' 'URL' 'https://synthetic.invalid/not-a-real-hook')" \
    'HARNESS_REPORT_BASE_URL=https://harness.slimyai.xyz' > "$ENV_FILE"
  make_stubs
  export CASE PROOF SESSIONS STATE LOGS STUBS CALL_LOG ENV_FILE
  export ACTUAL_NOTIFIER="$NOTIFIER" ACTUAL_SYNC="$SYNC_HELPER"
  export HARNESS_ROOT="$REPO_ROOT"
  export HARNESS_KB_SESSIONS="$SESSIONS"
  export HARNESS_SESSION_INDEX_OUTPUT="$SESSIONS/harness-session-index.json"
  export HARNESS_NOTIFY_STATE_DIR="$STATE"
  export HARNESS_SYNC_STATE_DIR="$STATE"
  export HARNESS_NOTIFY_LOG_DIR="$LOGS"
  export HARNESS_ENV_FILE="$ENV_FILE"
  export HARNESS_NOTIFY_SESSION_SCRIPT="$STUBS/notifier-wrapper"
  export HARNESS_SYNC_SESSION_SCRIPT="$STUBS/sync-wrapper"
  export HARNESS_NOTIFIER_TEST_MODE=1
  export HARNESS_NOTIFIER_STUB_ROOT="$STUBS"
  export HARNESS_SYNC_LOCAL_ROOT="$SESSIONS"
  export HARNESS_DISABLE_PROOF_INDEX_REFRESH=1
  export PATH="$STUBS:$ORIGINAL_PATH"
  unset CURL_STUB_HTTP SSH_STUB_FAIL RSYNC_STUB_FAIL
}

adapter() {
  bash "$ADAPTER" --proof-dir "$PROOF" --repo-path "$REPO_ROOT" --repo-name slimy-harness "$@"
}

ORIGINAL_PATH="$PATH"

# 1. Safe default: no mode refuses before report/archive/marker/helper action.
new_case default
set +e
adapter > "$CASE/output" 2>&1
rc=$?
set -e
assert_eq 64 "$rc" "no mode exits with usage refusal"
assert_contains "$CASE/output" '^STATE=NO_ACTION$' "no mode reports NO_ACTION"
assert_eq 0 "$(count_log '^(curl|ssh|rsync|notifier-helper|sync-helper)')" "no mode invokes no external/helper process"
assert_eq 0 "$(marker_count '*sent')" "no mode creates no marker"
assert_eq 0 "$(find "$SESSIONS" -type f | wc -l | tr -d ' ')" "no mode creates no report artifact"

new_case unauthorized_discord
set +e
adapter --mode discord-only > "$CASE/output" 2>&1
rc=$?
set -e
assert_eq 69 "$rc" "real discord-only requires explicit Discord authorization"
assert_contains "$CASE/output" '^STATE=REFUSED_UNAUTHORIZED_MODE$' "unauthorized Discord mode has stable state"
assert_eq 0 "$(count_log '^(curl|ssh|rsync|notifier-helper|sync-helper)')" "unauthorized Discord mode invokes nothing"

new_case unauthorized_sync
set +e
adapter --mode sync-only --sync-file "$SESSIONS/missing.json" > "$CASE/output" 2>&1
rc=$?
set -e
assert_eq 69 "$rc" "real sync-only requires explicit sync authorization before allowlist processing"
assert_contains "$CASE/output" '^STATE=REFUSED_UNAUTHORIZED_MODE$' "unauthorized sync mode has stable state"
assert_eq 0 "$(count_log '^(curl|ssh|rsync|notifier-helper|sync-helper)')" "unauthorized sync mode invokes nothing"

# 2. discord-only: one curl, readable report link, repeat dedupes, zero sync.
new_case discord
adapter --mode discord-only --discord-authorized > "$CASE/first.out" 2>&1
adapter --mode discord-only --discord-authorized > "$CASE/second.out" 2>&1
assert_eq 1 "$(count_log '^curl')" "discord-only sends transport exactly once across repeat"
assert_eq 2 "$(count_log '^notifier-helper$')" "discord-only reaches notifier helper on both dedupe-aware calls"
assert_eq 0 "$(count_log '^sync-helper$')" "discord-only invokes no sync helper"
assert_eq 0 "$(count_log '^ssh')" "discord-only invokes no ssh"
assert_eq 0 "$(count_log '^rsync')" "discord-only invokes no rsync"
assert_eq 0 "$(count_log '^scp')" "discord-only invokes no scp/relay"
assert_contains "$CASE/first.out" '^DISCORD_RESULT=DISCORD_SENT$' "discord-only records sent result"
assert_contains "$CASE/second.out" '^DISCORD_RESULT=DISCORD_DEDUPED$' "discord-only repeat dedupes"
assert_contains "$CASE/first.out" 'https://harness\.slimyai\.xyz/reports/sessions/report-proof-proof_discord\.json' "discord-only emits readable protected report link"
assert_eq 1 "$(marker_count '*.sent')" "discord-only creates one Discord marker"
assert_eq 0 "$(marker_count '*.sync-sent')" "discord-only creates no sync marker"

# 3. sync-only: no env/webhook/curl, exact files only, separate marker.
new_case sync
printf '{"unrelated":true}\n' > "$SESSIONS/unrelated-third.json"
REPORT="$SESSIONS/report-proof-proof_sync.json"
INDEX="$SESSIONS/harness-session-index.json"
adapter --mode sync-only --sync-authorized --sync-file "$REPORT" --sync-file "$INDEX" > "$CASE/output" 2>&1
assert_eq 0 "$(count_log '^env-loader$')" "sync-only never loads webhook environment"
assert_eq 0 "$(count_log '^notifier-helper$')" "sync-only never invokes Discord notifier"
assert_eq 0 "$(count_log '^curl')" "sync-only never invokes curl"
assert_eq 1 "$(count_log '^ssh')" "sync-only invokes one fixed-host ssh mkdir"
assert_eq 1 "$(count_log '^rsync')" "sync-only invokes one exact-file rsync"
assert_contains "$CALL_LOG" 'report-proof-proof_sync\.json' "sync-only includes exact report"
assert_contains "$CALL_LOG" 'harness-session-index\.json' "sync-only includes exact index"
assert_not_contains "$CALL_LOG" 'unrelated-third\.json' "sync-only excludes unrelated third JSON"
assert_eq 0 "$(marker_count '*.sent')" "sync-only creates no Discord marker"
assert_eq 1 "$(marker_count '*.sync-sent')" "sync-only creates separate sync marker"
assert_contains "$CASE/output" '^SYNC_RESULT=SYNC_COMPLETE$' "sync-only records completion"

# 4. both: explicit, separate results, deterministic separate dedupe.
new_case both
REPORT="$SESSIONS/report-proof-proof_both.json"
INDEX="$SESSIONS/harness-session-index.json"
adapter --mode both --discord-authorized --sync-authorized --sync-file "$REPORT" --sync-file "$INDEX" > "$CASE/first.out" 2>&1
adapter --mode both --discord-authorized --sync-authorized --sync-file "$REPORT" --sync-file "$INDEX" > "$CASE/second.out" 2>&1
assert_contains "$CASE/first.out" '^DISCORD_RESULT=DISCORD_SENT$' "both records Discord sent independently"
assert_contains "$CASE/first.out" '^SYNC_RESULT=SYNC_COMPLETE$' "both records sync complete independently"
assert_contains "$CASE/second.out" '^DISCORD_RESULT=DISCORD_DEDUPED$' "repeated both Discord dedupes"
assert_contains "$CASE/second.out" '^SYNC_RESULT=SYNC_DEDUPED$' "repeated both sync dedupes"
assert_eq 1 "$(count_log '^curl')" "repeated both does not resend Discord"
assert_eq 1 "$(count_log '^ssh')" "repeated both does not reaccess NUC2"
assert_eq 1 "$(count_log '^rsync')" "repeated both does not rerun rsync"
assert_eq 1 "$(marker_count '*.sent')" "both has one Discord marker"
assert_eq 1 "$(marker_count '*.sync-sent')" "both has one distinct sync marker"

# 5. both partial failures: no fallback and stable mixed states.
new_case partial_discord
REPORT="$SESSIONS/report-proof-proof_partial_discord.json"
INDEX="$SESSIONS/harness-session-index.json"
export CURL_STUB_HTTP=500
set +e
adapter --mode both --discord-authorized --sync-authorized --sync-file "$REPORT" --sync-file "$INDEX" > "$CASE/output" 2>&1
rc=$?
set -e
assert_eq 72 "$rc" "Discord failure with sync success returns partial exit"
assert_contains "$CASE/output" '^STATE=SYNC_OK_DISCORD_FAILED$' "Discord failure records SYNC_OK_DISCORD_FAILED"
assert_eq 1 "$(count_log '^curl')" "Discord failure has one transport attempt"
assert_eq 1 "$(count_log '^rsync')" "Discord failure does not suppress separately authorized sync"

new_case partial_sync
REPORT="$SESSIONS/report-proof-proof_partial_sync.json"
INDEX="$SESSIONS/harness-session-index.json"
export SSH_STUB_FAIL=1
set +e
adapter --mode both --discord-authorized --sync-authorized --sync-file "$REPORT" --sync-file "$INDEX" > "$CASE/output" 2>&1
rc=$?
set -e
assert_eq 72 "$rc" "sync failure with Discord success returns partial exit"
assert_contains "$CASE/output" '^STATE=DISCORD_OK_SYNC_FAILED$' "sync failure records DISCORD_OK_SYNC_FAILED"
assert_eq 1 "$(count_log '^curl')" "sync failure does not suppress separately authorized Discord"
assert_eq 1 "$(count_log '^ssh')" "sync failure attempts ssh once"
assert_eq 0 "$(count_log '^rsync')" "ssh failure never falls through to rsync"

new_case partial_rsync
REPORT="$SESSIONS/report-proof-proof_partial_rsync.json"
INDEX="$SESSIONS/harness-session-index.json"
export RSYNC_STUB_FAIL=1
set +e
adapter --mode sync-only --sync-authorized --sync-file "$REPORT" --sync-file "$INDEX" > "$CASE/output" 2>&1
rc=$?
set -e
assert_eq 71 "$rc" "rsync failure returns sync failure exit"
assert_contains "$CASE/output" '^SYNC_RESULT=SYNC_FAILED_RSYNC$' "rsync failure is explicit"
assert_eq 1 "$(count_log '^ssh')" "rsync failure follows successful ssh preflight"
assert_eq 1 "$(count_log '^rsync')" "rsync failure has one rsync attempt"
assert_eq 0 "$(count_log '^curl')" "sync failure has no Discord fallback"

# 6. Exact allowlist rejection matrix, then valid bounded transfer shape.
new_case allowlist
GOOD="$SESSIONS/good.json"
INDEX="$SESSIONS/harness-session-index.json"
UNRELATED="$SESSIONS/unrelated.json"
OUTSIDE="$CASE/outside.json"
printf '{"good":true}\n' > "$GOOD"
printf '{"index":true}\n' > "$INDEX"
printf '{"unrelated":true}\n' > "$UNRELATED"
printf '{"outside":true}\n' > "$OUTSIDE"
printf 'not-json\n' > "$SESSIONS/invalid.json"
ln -s "$GOOD" "$SESSIONS/link.json"
mkdir "$SESSIONS/directory.json"
for n in 1 2 3 4 5 6 7 8 9; do printf '{"n":%s}\n' "$n" > "$SESSIONS/bounded-$n.json"; done

sync_invalid() {
  local label="$1" expected="$2"
  shift 2
  set +e
  bash "$SYNC_HELPER" --sync-authorized "$@" > "$CASE/$label.out" 2>&1
  local rc=$?
  set -e
  assert_eq 65 "$rc" "$label is refused"
  assert_contains "$CASE/$label.out" "$expected" "$label has stable refusal reason"
}
sync_invalid outside outside_approved_root --file "$OUTSIDE"
sync_invalid symlink symlink_rejected --file "$SESSIONS/link.json"
sync_invalid directory non_regular_file_rejected --file "$SESSIONS/directory.json"
sync_invalid wildcard wildcard_or_glob_rejected --file "$SESSIONS/*.json"
sync_invalid duplicate duplicate_file --file "$GOOD" --file "$GOOD"
sync_invalid missing missing_file --file "$SESSIONS/missing.json"
sync_invalid invalid_json invalid_json_file --file "$SESSIONS/invalid.json"
sync_invalid bounded allowlist_exceeds_8_files \
  --file "$SESSIONS/bounded-1.json" --file "$SESSIONS/bounded-2.json" --file "$SESSIONS/bounded-3.json" \
  --file "$SESSIONS/bounded-4.json" --file "$SESSIONS/bounded-5.json" --file "$SESSIONS/bounded-6.json" \
  --file "$SESSIONS/bounded-7.json" --file "$SESSIONS/bounded-8.json" --file "$SESSIONS/bounded-9.json"
assert_eq 0 "$(count_log '^(ssh|rsync)')" "invalid allowlists perform no external command"

bash "$SYNC_HELPER" --sync-authorized --file "$GOOD" --file "$INDEX" > "$CASE/valid.out" 2>&1
assert_contains "$CALL_LOG" 'good\.json>' "valid allowlist transfers first exact file"
assert_contains "$CALL_LOG" 'harness-session-index\.json>' "valid allowlist transfers second exact file"
assert_not_contains "$CALL_LOG" 'unrelated\.json' "valid allowlist excludes unrelated JSON"
assert_not_contains "$CALL_LOG" '--delete' "rsync command has no delete capability"
assert_not_contains "$CALL_LOG" '<-r>|<--recursive>|<-a>' "rsync command has no recursive/archive capability"
assert_contains "$CALL_LOG" '<nuc2:/home/slimy/slimy-kb/raw/sessions/>' "rsync destination is fixed"

# 7. Dry-run/preflight is redacted and has no external action or marker.
new_case preflight
PREFLIGHT_A="$SESSIONS/preflight-a.json"
PREFLIGHT_B="$SESSIONS/preflight-b.json"
printf '{"a":1}\n' > "$PREFLIGHT_A"
printf '{"b":2}\n' > "$PREFLIGHT_B"
adapter --dry-run --mode both --sync-file "$PREFLIGHT_A" --sync-file "$PREFLIGHT_B" > "$CASE/output" 2>&1
assert_contains "$CASE/output" '^STATE=PREFLIGHT_OK$' "dry-run reports PREFLIGHT_OK"
assert_contains "$CASE/output" '^NOTIFY_MODE=both$' "preflight shows exact mode"
assert_contains "$CASE/output" '^DISCORD_AUTHORIZED=no$' "preflight shows Discord authorization"
assert_contains "$CASE/output" '^SYNC_AUTHORIZED=no$' "preflight shows sync authorization"
assert_contains "$CASE/output" '^EXTERNAL_SIDE_EFFECT_COUNT=2$' "preflight counts two independently selected actions"
assert_contains "$CASE/output" 'SYNC_FILE_1=preflight-a\.json sha256=' "preflight shows basename/hash allowlist"
assert_contains "$CASE/output" '^SYNC_EXTERNAL_SIDE_EFFECT_COUNT=1$' "sync preflight counts one bounded sync action"
assert_contains "$CASE/output" '^SYNC_DESTINATION=nuc2:/home/slimy/slimy-kb/raw/sessions/$' "preflight shows fixed destination"
assert_not_contains "$CASE/output" 'synthetic\.invalid/not-a-real-hook' "preflight never prints synthetic webhook value"
assert_eq 0 "$(count_log '^(curl|ssh|rsync|notifier-helper)')" "dry-run invokes no external/Discord process"
assert_eq 0 "$(marker_count '*sent')" "dry-run creates no marker"
assert_eq 0 "$(count_log '^env-loader$')" "dry-run does not load webhook environment"

# 8. Static process-boundary assertions.
if grep -Eq '^[[:space:]]*(ssh|scp|rsync)[[:space:]]' "$ADAPTER"; then
  fail "proof-dir adapter contains a direct network/sync command"
else
  pass "proof-dir adapter delegates no direct ssh/scp/rsync command"
fi
HOOK_ENV_NAME="$(printf '%s_%s' 'DISCORD_HARNESS_WEBHOOK' 'URL')"
if grep -q "$HOOK_ENV_NAME\|curl" "$SYNC_HELPER"; then
  fail "sync helper references Discord secret/transport"
else
  pass "sync helper has no Discord secret/transport reference"
fi
if grep -Eq 'find .*\.json|--delete|--recursive|rsync -a' "$SYNC_HELPER"; then
  fail "sync helper contains directory discovery/delete/recursive capability"
else
  pass "sync helper has no directory discovery/delete/recursive capability"
fi
assert_contains "$ADAPTER" 'if \[\[ "\$SYNC_SELECTED" -eq 1 \]\]' "sync dispatch is mode-gated"
assert_contains "$ADAPTER" 'if \[\[ "\$DISCORD_SELECTED" -eq 1 \]\]' "Discord dispatch is mode-gated"

if [[ -n "${HARNESS_TEST_STUB_LOG_OUTPUT:-}" ]]; then
  : > "$HARNESS_TEST_STUB_LOG_OUTPUT"
  while IFS= read -r call_log; do
    printf 'CASE=%s\n' "$(basename "$(dirname "$call_log")")" >> "$HARNESS_TEST_STUB_LOG_OUTPUT"
    sed 's#https://synthetic\.invalid/[^ >]*#[REDACTED-SYNTHETIC-URL]#g' "$call_log" >> "$HARNESS_TEST_STUB_LOG_OUTPUT"
  done < <(find "$TEMP" -mindepth 2 -maxdepth 2 -type f -name calls.log | sort)
fi

echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
