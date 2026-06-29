#!/usr/bin/env bash
# Manual Harness route/auth regression watchdog. This is intentionally
# run-on-demand only: no scheduling, service control, or notification send path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PHASE="harness-route-auth-regression-watchdog-manual"
TARGET_MACHINE="${TARGET_MACHINE:-NUC1}"
TARGET_REPO="${TARGET_REPO:-$REPO_ROOT}"
DEFAULT_DYNAMIC_REPORT_URL="https://harness.slimyai.xyz/reports/sessions/report-proof-proof_harness_reports_ticket_sso_trace_and_final_repair_20260628T171821Z.json"
DEFAULT_SESSION_INDEX="/home/slimy/slimy-kb/raw/sessions/harness-session-index.json"
DEFAULT_MIN_SESSION_COUNT=85

PROOF_DIR=""
DYNAMIC_REPORT_URL="$DEFAULT_DYNAMIC_REPORT_URL"
SESSION_INDEX_PATH="${HARNESS_ROUTE_AUTH_SESSION_INDEX:-$DEFAULT_SESSION_INDEX}"
MIN_SESSION_COUNT="${HARNESS_ROUTE_AUTH_MIN_SESSION_COUNT:-$DEFAULT_MIN_SESSION_COUNT}"

OWNER_GATE_STATUS="unknown"
REPORTS_LOGGED_OUT_BLOCKED="unknown"
DYNAMIC_REPORTS_LOGGED_OUT_BLOCKED="unknown"
SESSION_INDEX_STATUS="unknown"
ARCHIVE_ONLY_STATUS="unknown"
REPORT_LABEL_STATUS="unknown"
PRIVATE_LEAK_STATUS="unknown"
WATCHDOG_RUN_RESULT="unknown"

ROUTE_EXPOSURE_FOUND="no"
ROUTE_RUNTIME_ISSUE="no"
PRIVATE_LEAK_FOUND="no"
PRIVATE_LEAK_UNKNOWN="no"

FAILURES=()
WARNINGS=()

usage() {
  cat <<USAGE
Usage: harness-route-auth-watchdog.sh [--proof-dir DIR] [--dynamic-report-url URL] [--min-session-count N] [--session-index PATH]

Manual/run-on-demand regression watchdog for accepted Harness route/auth state.

Checks:
  - Clean-cookie logged-out Habitat and Harness Reports routes block.
  - Dynamic report detail blocks logged out.
  - Logged-out bodies do not expose report/session detail or raw secret markers.
  - Harness session index exists, is schema v1, has generated_at, and has enough
    sessions with one report link per session.
  - Archive-only session script exists, is executable, and passes syntax.
  - Report-label semantics test exists and passes.

Options:
  --proof-dir DIR           Write proof files and RESULT.md to DIR.
  --dynamic-report-url URL  Dynamic report detail URL to check.
                            Default: $DEFAULT_DYNAMIC_REPORT_URL
  --min-session-count N     Minimum accepted session_count. Default: $DEFAULT_MIN_SESSION_COUNT
  --session-index PATH      Session index JSON path.
                            Default: $DEFAULT_SESSION_INDEX
  --help, -h                Show this help.

This script never sends notifications, never reads hook configuration, never
changes cron/timers/systemd/tmux/Caddy/DNS, and never restarts services.
USAGE
}

add_failure() {
  FAILURES+=("$1")
}

add_warning() {
  WARNINGS+=("$1")
}

join_items() {
  local IFS=';'
  if [ "$#" -eq 0 ]; then
    printf 'none'
  else
    printf '%s' "$*"
  fi
}

redact_text() {
  sed -E \
    -e 's#https://[^[:space:]<>"'"'"']+/api/webhooks/[A-Za-z0-9_./-]+#[redacted-hook-url]#g' \
    -e 's#([0-9]{8,}):[A-Za-z0-9_-]{20,}#[redacted-token-shaped]#g' \
    -e 's#([?&](ticket|sso_ticket|ssoTicket)=)[^&[:space:]]+#\1[redacted]#Ig' \
    -e 's#(Authorization|authorization|cookie|Cookie|set-cookie|Set-Cookie)([[:space:]]*:?[[:space:]]*)[^[:space:];&]+#\1\2[redacted]#Ig'
}

redact_string() {
  printf '%s' "${1:-}" | redact_text
}

body_has_detail_markers() {
  local body="$1"
  [ -s "$body" ] || return 1
  grep -Eiq '("session_id"[[:space:]]*:|"feature_id"[[:space:]]*:|"proof_dir"[[:space:]]*:|"source_report"[[:space:]]*:|"harness-session-index/v1"|<span class="test-label">|Session Report|Proof Directory|Test Results|^PHASE=|^VALIDATION=|^DISCORD_SENT=|^NOTIFY_MODE=|^REPORT_URL=|^SERVICES_RESTARTED=)' "$body"
}

body_has_secret_markers() {
  local body="$1"
  [ -s "$body" ] || return 1
  grep -Eiq '(https://[^[:space:]<>"]+/api/webhooks/[A-Za-z0-9_./-]+|[0-9]{8,}:[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9._-]{12,}|BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|[?&](ticket|sso_ticket|ssoTicket)=|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]+)' "$body"
}

body_has_login_markers() {
  local body="$1"
  [ -s "$body" ] || return 1
  grep -Eiq 'Owner Login|Sign[ -]?in|Log[ -]?in|type=["'"'"']password["'"'"']|name=["'"'"']password["'"'"']|/login' "$body"
}

is_logged_out_blocked() {
  local status="$1"
  local final_url="$2"
  local body="$3"

  case "$status" in
    401|403)
      return 0
      ;;
  esac

  if printf '%s' "$final_url" | grep -Eiq '(^|/)login([/?#]|$)|/auth/signin'; then
    return 0
  fi

  if body_has_login_markers "$body"; then
    return 0
  fi

  return 1
}

status_is_runtime_issue() {
  local status="$1"
  case "$status" in
    ""|000|404)
      return 0
      ;;
  esac
  if [[ "$status" =~ ^[0-9]+$ ]] && [ "$status" -ge 500 ]; then
    return 0
  fi
  return 1
}

init_proof_dir() {
  if [ -z "$PROOF_DIR" ]; then
    PROOF_DIR="/tmp/proof_${PHASE}_$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  mkdir -p "$PROOF_DIR"
  chmod -R go-rwx "$PROOF_DIR" 2>/dev/null || true
}

record_route() {
  local label="$1"
  local url="$2"
  local temp_dir="$3"
  local body="$temp_dir/${label}.body"
  local headers="$temp_dir/${label}.headers"
  local meta="$temp_dir/${label}.meta"
  local jar="$temp_dir/${label}.cookies"
  : > "$jar"

  local curl_rc=0
  set +e
  curl --silent --show-error --location --max-redirs 8 \
    --connect-timeout 10 --max-time 30 \
    --cookie-jar "$jar" --cookie "$jar" \
    --user-agent "slimy-harness-route-auth-watchdog/1" \
    --dump-header "$headers" --output "$body" \
    --write-out '%{http_code}\t%{url_effective}\t%{num_redirects}\t%{content_type}\n' \
    "$url" > "$meta" 2>"$temp_dir/${label}.curl.err"
  curl_rc=$?
  set -e

  local status="000"
  local final_url=""
  local redirects="0"
  local content_type=""
  if [ -s "$meta" ]; then
    IFS=$'\t' read -r status final_url redirects content_type < "$meta" || true
  fi

  local body_bytes=0
  if [ -f "$body" ]; then
    body_bytes="$(wc -c < "$body" | tr -d ' ')"
  fi

  local blocked="unknown"
  local runtime_issue="no"
  local detail_marker="no"
  local secret_marker="no"
  local login_marker="no"

  if [ "$curl_rc" -ne 0 ] || status_is_runtime_issue "$status"; then
    runtime_issue="yes"
    ROUTE_RUNTIME_ISSUE="yes"
    add_warning "route_${label}_runtime_issue_status_${status}_curl_${curl_rc}"
  else
    if is_logged_out_blocked "$status" "$final_url" "$body"; then
      blocked="yes"
    else
      blocked="no"
      ROUTE_EXPOSURE_FOUND="yes"
      add_failure "route_${label}_not_blocked_logged_out_status_${status}"
    fi
  fi

  if body_has_detail_markers "$body"; then
    detail_marker="yes"
    PRIVATE_LEAK_FOUND="yes"
    ROUTE_EXPOSURE_FOUND="yes"
    add_failure "route_${label}_detail_marker_visible_logged_out"
  fi

  if body_has_secret_markers "$body"; then
    secret_marker="yes"
    PRIVATE_LEAK_FOUND="yes"
    ROUTE_EXPOSURE_FOUND="yes"
    add_failure "route_${label}_secret_marker_visible_logged_out"
  fi

  if body_has_login_markers "$body"; then
    login_marker="yes"
  fi

  if [ "$runtime_issue" = "yes" ]; then
    PRIVATE_LEAK_UNKNOWN="yes"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$label" \
    "$(redact_string "$url")" \
    "$status" \
    "$(redact_string "$final_url")" \
    "$redirects" \
    "$content_type" \
    "$curl_rc" \
    "$blocked" \
    "$login_marker" \
    "$detail_marker" \
    "$secret_marker" \
    "$body_bytes" >> "$PROOF_DIR/route-checks.tsv"
}

route_blocked_value() {
  local label="$1"
  awk -F '\t' -v label="$label" '$1 == label { print $8; found=1 } END { if (!found) print "unknown" }' "$PROOF_DIR/route-checks.tsv"
}

run_route_checks() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  cat > "$PROOF_DIR/route-checks.tsv" <<'EOF'
label	requested_url	final_status	final_url	redirects	content_type	curl_rc	blocked_logged_out	login_marker	detail_marker	secret_marker	body_bytes
EOF

  record_route "habitat_root" "https://habitat.slimyai.xyz/" "$temp_dir"
  record_route "habitat_harness" "https://habitat.slimyai.xyz/harness" "$temp_dir"
  record_route "reports_index" "https://harness.slimyai.xyz/reports" "$temp_dir"
  record_route "reports_sessions" "https://harness.slimyai.xyz/reports/sessions" "$temp_dir"
  record_route "dynamic_report_detail" "$DYNAMIC_REPORT_URL" "$temp_dir"

  local habitat_root habitat_harness reports_index reports_sessions dynamic_detail
  habitat_root="$(route_blocked_value "habitat_root")"
  habitat_harness="$(route_blocked_value "habitat_harness")"
  reports_index="$(route_blocked_value "reports_index")"
  reports_sessions="$(route_blocked_value "reports_sessions")"
  dynamic_detail="$(route_blocked_value "dynamic_report_detail")"

  if [ "$habitat_root" = "yes" ] && [ "$habitat_harness" = "yes" ]; then
    OWNER_GATE_STATUS="accepted"
  elif [ "$habitat_root" = "unknown" ] || [ "$habitat_harness" = "unknown" ]; then
    OWNER_GATE_STATUS="warn"
  else
    OWNER_GATE_STATUS="fail"
  fi

  if [ "$reports_index" = "yes" ] && [ "$reports_sessions" = "yes" ]; then
    REPORTS_LOGGED_OUT_BLOCKED="yes"
  elif [ "$reports_index" = "unknown" ] || [ "$reports_sessions" = "unknown" ]; then
    REPORTS_LOGGED_OUT_BLOCKED="warn"
  else
    REPORTS_LOGGED_OUT_BLOCKED="no"
  fi

  if [ "$dynamic_detail" = "yes" ]; then
    DYNAMIC_REPORTS_LOGGED_OUT_BLOCKED="yes"
  elif [ "$dynamic_detail" = "unknown" ]; then
    DYNAMIC_REPORTS_LOGGED_OUT_BLOCKED="warn"
  else
    DYNAMIC_REPORTS_LOGGED_OUT_BLOCKED="no"
  fi

  if [ "$PRIVATE_LEAK_FOUND" = "yes" ]; then
    PRIVATE_LEAK_STATUS="fail"
  elif [ "$PRIVATE_LEAK_UNKNOWN" = "yes" ]; then
    PRIVATE_LEAK_STATUS="warn"
  else
    PRIVATE_LEAK_STATUS="clean"
  fi
}

check_session_index() {
  local output="$PROOF_DIR/session-index-check.txt"
  set +e
  python3 - "$SESSION_INDEX_PATH" "$MIN_SESSION_COUNT" > "$output" 2>&1 <<'PY'
import datetime as dt
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
minimum = int(sys.argv[2])
errors = []

if not path.is_file():
    print(f"path={path}")
    print("exists=no")
    raise SystemExit(1)

print(f"path={path}")
print("exists=yes")

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"json_load=fail:{type(exc).__name__}")
    raise SystemExit(1)

schema = data.get("schema_version")
generated_at = data.get("generated_at")
sessions = data.get("sessions")
session_count = data.get("session_count")

print(f"schema_version={schema}")
print(f"generated_at_present={'yes' if generated_at else 'no'}")
print(f"session_count={session_count}")
print(f"minimum_session_count={minimum}")

if schema != "harness-session-index/v1":
    errors.append("schema_version")

try:
    dt.datetime.fromisoformat(str(generated_at).replace("Z", "+00:00"))
except Exception:
    errors.append("generated_at")

if not isinstance(sessions, list):
    errors.append("sessions_array")
    sessions = []

if not isinstance(session_count, int):
    errors.append("session_count_type")
    session_count = -1

derived_report_link_count = sum(
    1
    for session in sessions
    if isinstance(session, dict)
    and isinstance(session.get("report_url"), str)
    and session["report_url"].strip()
)

print(f"derived_report_link_count={derived_report_link_count}")
print(f"sessions_length={len(sessions)}")

if session_count != len(sessions):
    errors.append("session_count_length")
if session_count < minimum:
    errors.append("session_count_minimum")
if derived_report_link_count != session_count:
    errors.append("report_link_count")

if errors:
    print("status=fail")
    print("errors=" + ";".join(errors))
    raise SystemExit(1)

print("status=accepted")
PY
  local rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    SESSION_INDEX_STATUS="accepted"
  else
    SESSION_INDEX_STATUS="fail"
    add_failure "session_index_check_failed"
  fi
}

check_archive_only() {
  local output="$PROOF_DIR/archive-only-check.txt"
  local script="$REPO_ROOT/sequencer/archive-proof-dir-session.sh"
  {
    if [ -f "$script" ]; then
      echo "archive_only_script_exists=yes"
    else
      echo "archive_only_script_exists=no"
    fi
    if [ -x "$script" ]; then
      echo "archive_only_script_executable=yes"
    else
      echo "archive_only_script_executable=no"
    fi
    if bash -n "$script"; then
      echo "archive_only_script_syntax=pass"
    else
      echo "archive_only_script_syntax=fail"
    fi
  } > "$output" 2>&1

  if grep -q '^archive_only_script_exists=yes$' "$output" \
    && grep -q '^archive_only_script_executable=yes$' "$output" \
    && grep -q '^archive_only_script_syntax=pass$' "$output"; then
    ARCHIVE_ONLY_STATUS="accepted"
  else
    ARCHIVE_ONLY_STATUS="fail"
    add_failure "archive_only_check_failed"
  fi
}

check_report_label() {
  local output="$PROOF_DIR/report-label-check.txt"
  local test_script="$REPO_ROOT/sequencer/tests/test_report_label_semantics.sh"

  if [ ! -f "$test_script" ]; then
    echo "report_label_test_exists=no" > "$output"
    REPORT_LABEL_STATUS="fail"
    add_failure "report_label_test_missing"
    return
  fi

  if [ ! -x "$test_script" ]; then
    echo "report_label_test_executable=no" > "$output"
    REPORT_LABEL_STATUS="fail"
    add_failure "report_label_test_not_executable"
    return
  fi

  set +e
  bash "$test_script" > "$output" 2>&1
  local rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    REPORT_LABEL_STATUS="accepted"
  else
    REPORT_LABEL_STATUS="fail"
    add_failure "report_label_test_failed"
  fi
}

write_result() {
  local result="$1"
  WATCHDOG_RUN_RESULT="$result"
  cat > "$PROOF_DIR/RESULT.md" <<EOF
PHASE=$PHASE
RESULT=$result
TARGET_MACHINE=$TARGET_MACHINE
TARGET_REPO=$TARGET_REPO
PROOF_DIR=$PROOF_DIR
OWNER_GATE_STATUS=$OWNER_GATE_STATUS
REPORTS_LOGGED_OUT_BLOCKED=$REPORTS_LOGGED_OUT_BLOCKED
DYNAMIC_REPORTS_LOGGED_OUT_BLOCKED=$DYNAMIC_REPORTS_LOGGED_OUT_BLOCKED
SESSION_INDEX_STATUS=$SESSION_INDEX_STATUS
ARCHIVE_ONLY_STATUS=$ARCHIVE_ONLY_STATUS
REPORT_LABEL_STATUS=$REPORT_LABEL_STATUS
PRIVATE_LEAK_STATUS=$PRIVATE_LEAK_STATUS
DISCORD_SENT=no
NOTIFY_MODE=manual_watchdog_no_send
SERVICES_RESTARTED=no
CRON_CHANGED=no
TIMER_CHANGED=no
TMUX_CHANGED=no
CADDY_CHANGED=no
DNS_CHANGED=no
SECRETS_PRINTED=no
WATCHDOG_SCRIPT=sequencer/harness-route-auth-watchdog.sh
WATCHDOG_RUN_RESULT=$WATCHDOG_RUN_RESULT
WARNINGS=$(join_items "${WARNINGS[@]}")
FAILURES=$(join_items "${FAILURES[@]}")
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --proof-dir)
        if [ "$#" -lt 2 ]; then
          echo "ERROR: --proof-dir requires a directory" >&2
          exit 64
        fi
        PROOF_DIR="$2"
        shift 2
        ;;
      --dynamic-report-url)
        if [ "$#" -lt 2 ]; then
          echo "ERROR: --dynamic-report-url requires a URL" >&2
          exit 64
        fi
        DYNAMIC_REPORT_URL="$2"
        shift 2
        ;;
      --min-session-count)
        if [ "$#" -lt 2 ]; then
          echo "ERROR: --min-session-count requires a number" >&2
          exit 64
        fi
        MIN_SESSION_COUNT="$2"
        shift 2
        ;;
      --session-index)
        if [ "$#" -lt 2 ]; then
          echo "ERROR: --session-index requires a path" >&2
          exit 64
        fi
        SESSION_INDEX_PATH="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: unknown argument: $1" >&2
        usage >&2
        exit 64
        ;;
    esac
  done

  if ! [[ "$MIN_SESSION_COUNT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --min-session-count must be a non-negative integer" >&2
    exit 64
  fi
}

main() {
  parse_args "$@"
  init_proof_dir

  {
    echo "phase=$PHASE"
    echo "target_machine=$TARGET_MACHINE"
    echo "target_repo=$TARGET_REPO"
    echo "proof_dir=$PROOF_DIR"
    echo "dynamic_report_url=$(redact_string "$DYNAMIC_REPORT_URL")"
    echo "session_index_path=$SESSION_INDEX_PATH"
    echo "min_session_count=$MIN_SESSION_COUNT"
    echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$PROOF_DIR/watchdog-meta.txt"

  run_route_checks
  if [ "$ROUTE_EXPOSURE_FOUND" = "yes" ]; then
    SESSION_INDEX_STATUS="not_checked_route_exposure"
    ARCHIVE_ONLY_STATUS="not_checked_route_exposure"
    REPORT_LABEL_STATUS="not_checked_route_exposure"
    write_result "FAIL"
    cat "$PROOF_DIR/RESULT.md"
    exit 1
  fi

  check_session_index
  check_archive_only
  check_report_label

  local result="PASS"
  if [ "${#FAILURES[@]}" -gt 0 ]; then
    result="FAIL"
  elif [ "${#WARNINGS[@]}" -gt 0 ]; then
    result="WARN"
  fi

  write_result "$result"
  cat "$PROOF_DIR/RESULT.md"

  case "$result" in
    PASS) exit 0 ;;
    WARN) exit 2 ;;
    *) exit 1 ;;
  esac
}

if [ "${HARNESS_ROUTE_AUTH_WATCHDOG_LIB_ONLY:-0}" != "1" ]; then
  main "$@"
fi
