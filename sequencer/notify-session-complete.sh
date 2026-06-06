#!/usr/bin/env bash
# notify-session-complete.sh — send a Discord completion notification when a
# harness/agent session finishes.
#
# This is the dedicated COMPLETION webhook. It is intentionally separate from
# sequencer/notify-blockers.sh (which posts blocker / queue state) and is
# integrated at the closeout / finalizer point so it fires for every agent
# (OpenCode, Claude, Codex, future) that writes a session report.
#
# Usage:
#   notify-session-complete.sh [--dry-run] [--require-webhook] <session-report.json>
#   notify-session-complete.sh --help
#
# Behaviour:
#   - Loads /home/slimy/.slimy-harness.env if present (autodetected).
#   - Never prints the Discord webhook URL. All log lines and stdout are
#     redacted via REDACT_TOKEN.
#   - If DISCORD_HARNESS_WEBHOOK_URL is missing:
#       * --dry-run:        continues, prints what WOULD be sent.
#       * --require-webhook: exits non-zero with a clear message.
#       * otherwise:        exits 0 with a WARN log line.
#   - Builds a public report URL of the form
#         ${HARNESS_REPORT_BASE_URL}/reports/sessions/<filename>
#   - Mentions are sent on WARN/FAIL/BLOCKED, and on SUCCESS only when
#     HARNESS_NOTIFY_ON_SUCCESS=1 and DISCORD_HARNESS_MENTION is set.
#   - Attaches an HTML snapshot of the report when
#     HARNESS_NOTIFY_ATTACH_HTML=1 (renderer: render-session-report-html.py).
#   - Always attaches the raw session-report.json (Discord max 25 MiB; we
#     refuse anything larger).
#   - Writes a redacted log line to
#         /home/slimy/harness-logs/notifications.log
#   - Handles Discord 429 once by honouring retry_after, then exits.
#   - Never turns a passing task into FAIL. Notification failures are logged
#     and exit non-zero ONLY under --require-webhook.
#
# Strict safety:
#   - The webhook URL is never echoed. The REDACT_TOKEN substitution is
#     applied to every variable that could carry it.
#   - The script never executes the report; it only reads it as JSON.
set -euo pipefail

SCRIPT_NAME="notify-session-complete"
LOG_DIR="/home/slimy/harness-logs"
LOG_FILE="${LOG_DIR}/notifications.log"
HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-/home/slimy/.slimy-harness.env}"
SEQUNCER_DIR_DEFAULT="/home/slimy/slimy-harness/sequencer"
RENDERER="${RENDERER:-${SEQUNCER_DIR_DEFAULT}/render-session-report-html.py}"
HARNESS_ROOT_DEFAULT="/home/slimy/slimy-harness"
HARNESS_ROOT="${HARNESS_ROOT:-$HARNESS_ROOT_DEFAULT}"
REDACT_TOKEN="[REDACTED-WEBHOOK]"

DRY_RUN=0
REQUIRE_WEBHOOK=0
REPORT_PATH=""

usage() {
  cat <<USG
$SCRIPT_NAME — Discord completion webhook for harness agent runs

Usage:
  $SCRIPT_NAME [--dry-run] [--require-webhook] <session-report.json>
  $SCRIPT_NAME --help

Options:
  --dry-run           Show what would be sent; do not call Discord.
  --require-webhook   Exit non-zero if the webhook URL is missing.
  --help              Show this help.

Environment (loaded from $HARNESS_ENV_FILE if present):
  DISCORD_HARNESS_WEBHOOK_URL   (required for live send)
  DISCORD_HARNESS_MENTION       e.g. <@427999592986968074>
  HARNESS_REPORT_BASE_URL       default: https://harness.slimyai.xyz
  HARNESS_NOTIFY_ON_SUCCESS     1 = mention on success too, 0 = off
  HARNESS_NOTIFY_ATTACH_HTML    1 = attach generated .html snapshot
USG
}

# ---- arg parsing -----------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --require-webhook)
      REQUIRE_WEBHOOK=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      REPORT_PATH="${1:-}"
      break
      ;;
    -*)
      echo "[$SCRIPT_NAME] ERROR: unknown flag: $1" >&2
      usage >&2
      exit 64
      ;;
    *)
      REPORT_PATH="$1"
      shift
      ;;
  esac
done

# ---- env loading (autodetected) -------------------------------------------

if [[ -f "$HARNESS_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  . "$HARNESS_ENV_FILE"
  set +a
fi

# ---- helpers ---------------------------------------------------------------

log()      { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$SCRIPT_NAME] $*"; }
warn_log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$SCRIPT_NAME] WARN: $*" >&2; }
err_log()  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$SCRIPT_NAME] ERROR: $*" >&2; }

redact() {
  # Replace any literal webhook URL with REDACT_TOKEN. Handles either env
  # name being already in the string (eg. ${DISCORD_HARNESS_WEBHOOK_URL})
  # and the URL itself.
  local s="${1-}"
  s="${s//https:\/\/discord.com\/api\/webhooks\/[A-Za-z0-9_/-]*/$REDACT_TOKEN}"
  s="${s//DISCORD_HARNESS_WEBHOOK_URL/$REDACT_TOKEN}"
  printf '%s' "$s"
}

ensure_log_dir() {
  if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || true
  fi
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

cleanup() {
  local rc=$?
  local _f
  for _f in "${TMPDIR_PAYLOAD:-}" "${TMPDIR_BODY:-}" "${TMPDIR_HTML:-}" "${PARSER_TMP:-}" "${RETRY_PARSER_TMP:-}"; do
    if [[ -n "$_f" && -f "$_f" ]]; then
      rm -f "$_f" 2>/dev/null || true
    fi
  done
  exit "$rc"
}
trap cleanup EXIT INT TERM

# ---- validate input --------------------------------------------------------

if [[ -z "$REPORT_PATH" ]]; then
  err_log "no session-report.json path given"
  usage >&2
  exit 64
fi
if [[ ! -f "$REPORT_PATH" ]]; then
  err_log "session report not found: $REPORT_PATH"
  exit 66
fi

# ---- parse JSON (best-effort) ---------------------------------------------

# Use a here-doc fed into python3 via stdin (no $() wrapping the heredoc,
# which would confuse bash's parser).  Capture output via a tempfile.
PARSER_TMP="$(mktemp -t parser.XXXXXX.py)"
cat > "$PARSER_TMP" <<'PYEOF'
import json, os, sys

path = os.environ.get("REPORT_PATH", "")
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception as e:
    print(f"PARSE_ERROR: {e}", file=sys.stderr)
    sys.exit(2)

def s(v):
    if v is None:
        return ""
    if isinstance(v, (dict, list)):
        try:
            return json.dumps(v, ensure_ascii=False)
        except Exception:
            return str(v)
    return str(v)

out = {
    "feature_id": s(data.get("feature_id", "")),
    "repo": s(data.get("project", data.get("repo", ""))),
    "agent": s(data.get("agent", "")),
    "nuc": s(data.get("nuc", "")),
    "status_raw": s(data.get("status", "unknown")),
    "summary": s(data.get("summary", "")),
    "proof_dir": s(data.get("proof_dir", data.get("proof_directory", ""))),
    "commit": s(data.get("commit", data.get("commit_hash", ""))),
    "session_id": s(data.get("session_id", data.get("timestamp", ""))),
    "changes": data.get("changes", []) if isinstance(data.get("changes"), list) else [],
    "timestamp": s(data.get("timestamp", "")),
    "duration_minutes": data.get("duration_minutes", 0) or 0,
    "tests_passed": bool(data.get("tests", {}).get("passed", False)) if isinstance(data.get("tests"), dict) else False,
    "blockers": data.get("blockers", []) if isinstance(data.get("blockers"), list) else [],
}
print(json.dumps(out, ensure_ascii=False))
PYEOF

PARSED_JSON="$(REPORT_PATH="$REPORT_PATH" python3 "$PARSER_TMP" 2>/dev/null || echo "")"
rm -f "$PARSER_TMP" 2>/dev/null || true

if [[ -z "$PARSED_JSON" || "$PARSED_JSON" == "PARSE_ERROR:"* ]]; then
  err_log "could not parse session report: $REPORT_PATH"
  if [[ "$REQUIRE_WEBHOOK" -eq 1 ]]; then
    exit 65
  fi
  exit 0
fi

# Materialise fields via Python so quoting is bullet-proof. We use a
# single-line output with NUL separators (bash read -d '' reads until NUL)
# so that fields containing spaces or newlines survive intact.
FIELDS_TMP="$(mktemp -t fields.XXXXXX.py)"
cat > "$FIELDS_TMP" <<'PYEOF'
import json, sys
d = json.loads(sys.argv[1])
# 14 fields, NUL-separated, in this order
fields = [
    d.get("feature_id", ""),
    d.get("repo", ""),
    d.get("agent", ""),
    d.get("nuc", ""),
    d.get("status_raw", "unknown"),
    d.get("summary", ""),
    d.get("proof_dir", ""),
    d.get("commit", ""),
    d.get("session_id", ""),
    json.dumps(d.get("changes", []), ensure_ascii=False),
    d.get("timestamp", ""),
    str(d.get("duration_minutes", 0) or 0),
    "1" if d.get("tests_passed") else "0",
    json.dumps(d.get("blockers", []), ensure_ascii=False),
]
sys.stdout.write("\n".join(fields))
sys.stdout.write("\n")
PYEOF

# Read all 14 lines into bash variables
_line_num=0
FEATURE_ID=""; REPO=""; AGENT=""; NUC=""; STATUS_RAW=""
SUMMARY=""; PROOF_DIR=""; COMMIT=""; SESSION_ID=""
CHANGES_JSON=""; TIMESTAMP=""; DURATION=""; TESTS_PASSED=""; BLOCKERS_JSON=""
while IFS= read -r _line; do
  case "$_line_num" in
    0)  FEATURE_ID="$_line" ;;
    1)  REPO="$_line" ;;
    2)  AGENT="$_line" ;;
    3)  NUC="$_line" ;;
    4)  STATUS_RAW="$_line" ;;
    5)  SUMMARY="$_line" ;;
    6)  PROOF_DIR="$_line" ;;
    7)  COMMIT="$_line" ;;
    8)  SESSION_ID="$_line" ;;
    9)  CHANGES_JSON="$_line" ;;
    10) TIMESTAMP="$_line" ;;
    11) DURATION="$_line" ;;
    12) TESTS_PASSED="$_line" ;;
    13) BLOCKERS_JSON="$_line" ;;
  esac
  _line_num=$((_line_num + 1))
done < <(python3 "$FIELDS_TMP" "$PARSED_JSON" 2>/dev/null)
unset _line _line_num
rm -f "$FIELDS_TMP" 2>/dev/null || true

# Truncate summary to keep the Discord embed small
SUMMARY_TRIMMED="$(printf '%s' "$SUMMARY" | head -c 480)"

# ---- normalise status -> one of success/warning/failure/blocked ------------

normalize_status() {
  local s
  s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$s" in
    completed|pass|passed|success|ok|done) printf 'success' ;;
    warn|warning|partial)                   printf 'warning' ;;
    fail|failed|error|errored)              printf 'failure' ;;
    blocked|block)                          printf 'blocked' ;;
    *)                                      printf 'warning' ;;
  esac
}

STATUS_KIND="$(normalize_status "$STATUS_RAW")"

STATUS_EMOJI="$REDACT_TOKEN"
case "$STATUS_KIND" in
  success)  STATUS_EMOJI="✅" ;;
  warning)  STATUS_EMOJI="⚠️" ;;
  failure)  STATUS_EMOJI="❌" ;;
  blocked)  STATUS_EMOJI="⛔" ;;
  *)        STATUS_EMOJI="❔" ;;
esac

# ---- public URL ------------------------------------------------------------

HARNESS_REPORT_BASE_URL="${HARNESS_REPORT_BASE_URL:-https://harness.slimyai.xyz}"
HARNESS_REPORT_BASE_URL="${HARNESS_REPORT_BASE_URL%/}"
REPORT_BASENAME="$(basename "$REPORT_PATH")"
# Minimal URL-encode for slashes/spaces in filename. We deliberately use
# python urllib to keep the logic simple and safe.
ENCODED_BASENAME="$(printf '%s' "$REPORT_BASENAME" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe='.-_~'))")"
PUBLIC_REPORT_URL="${HARNESS_REPORT_BASE_URL}/reports/sessions/${ENCODED_BASENAME}"

# ---- mention decision ------------------------------------------------------

SHOULD_MENTION=0
if [[ "$STATUS_KIND" != "success" ]]; then
  SHOULD_MENTION=1
elif [[ "${HARNESS_NOTIFY_ON_SUCCESS:-0}" == "1" ]]; then
  SHOULD_MENTION=1
fi

MENTION_TEXT=""
if [[ "$SHOULD_MENTION" -eq 1 && -n "${DISCORD_HARNESS_MENTION:-}" ]]; then
  MENTION_TEXT="${DISCORD_HARNESS_MENTION} "
fi

# ---- render HTML attachment ------------------------------------------------

ATTACH_HTML=0
HTML_PATH=""
if [[ "${HARNESS_NOTIFY_ATTACH_HTML:-1}" == "1" ]]; then
  if [[ -x "$RENDERER" || -f "$RENDERER" ]]; then
    TMPDIR_HTML="$(mktemp -t session-report.XXXXXX.html)"
    if python3 "$RENDERER" --report-url "$PUBLIC_REPORT_URL" "$REPORT_PATH" "$TMPDIR_HTML" >/dev/null 2>&1; then
      HTML_PATH="$TMPDIR_HTML"
      ATTACH_HTML=1
    else
      warn_log "HTML renderer failed; continuing without HTML attachment"
    fi
  else
    warn_log "renderer not found at $RENDERER; continuing without HTML attachment"
  fi
fi

# ---- build Discord content / payload ---------------------------------------

# Discord max message 2000 chars, attachment #1 is file (we send at most 2 files)
PROOF_LINE=""
if [[ -n "$PROOF_DIR" ]]; then
  PROOF_LINE="• proof: \`${PROOF_DIR}\`"
fi

# Trim summary further if it has odd whitespace / control chars
SUMMARY_TRIMMED="$(printf '%s' "$SUMMARY_TRIMMED" | tr '\r\n\t' '   ' | sed 's/  */ /g')"

CONTENT="$(printf '%s%s **%s** — %s
• feature_id: \`%s\`
• repo: \`%s\`
• status: **%s** (\`%s\`)
• agent: %s • nuc: %s
• report: %s
%s
• summary: %s
%s
' \
  "$MENTION_TEXT" \
  "$STATUS_EMOJI" \
  "${FEATURE_ID:-unknown}" \
  "${STATUS_RAW:-unknown}" \
  "${FEATURE_ID:-unknown}" \
  "${REPO:-unknown}" \
  "${STATUS_KIND}" \
  "${STATUS_RAW:-unknown}" \
  "${AGENT:-?}" \
  "${NUC:-?}" \
  "$PUBLIC_REPORT_URL" \
  "$PROOF_LINE" \
  "${SUMMARY_TRIMMED:-(no summary)}" \
  "$( [[ $ATTACH_HTML -eq 1 ]] && echo '• HTML + JSON attached' || echo '• JSON attached' )"
)"

# Clip to 1900 to leave headroom
if [[ "${#CONTENT}" -gt 1900 ]]; then
  CONTENT="${CONTENT:0:1900}…"
fi

# ---- build payload_json via python so escaping is correct ------------------

TMPDIR_PAYLOAD="$(mktemp -t payload.XXXXXX.json)"
python3 - "$CONTENT" > "$TMPDIR_PAYLOAD" <<'PY'
import json, sys
content = sys.argv[1]
payload = {"content": content}
# Discord allows username/avatar_override; harmless to omit.
print(json.dumps(payload, ensure_ascii=False))
PY

# ---- dry-run path ----------------------------------------------------------

if [[ "$DRY_RUN" -eq 1 ]]; then
  _WEBHOOK_LEN="${#DISCORD_HARNESS_WEBHOOK_URL}"
  _WEBHOOK_LEN="${_WEBHOOK_LEN:-0}"
  _DRY_OUT="$(cat <<DRY
[$SCRIPT_NAME] dry-run
  feature_id:        $FEATURE_ID
  repo:              $REPO
  agent:             $AGENT
  nuc:               $NUC
  status_raw:        $STATUS_RAW
  status_kind:       $STATUS_KIND
  status_emoji:      $STATUS_EMOJI
  mention:           $( [[ "$SHOULD_MENTION" -eq 1 ]] && echo "yes ($MENTION_TEXT)" || echo "no" )
  public_report_url: $PUBLIC_REPORT_URL
  proof_dir:         ${PROOF_DIR:-(none)}
  html_attachment:   $( [[ $ATTACH_HTML -eq 1 ]] && echo "$HTML_PATH" || echo "(skipped)" )
  json_attachment:   $REPORT_PATH
  content_chars:     ${#CONTENT}
  payload_preview:   $( head -c 220 "$TMPDIR_PAYLOAD" )...
  webhook_url:       $REDACT_TOKEN (length=$_WEBHOOK_LEN)
DRY
)"
  redact "$_DRY_OUT"
  unset _DRY_OUT _WEBHOOK_LEN
  exit 0
fi

# ---- live send -------------------------------------------------------------

WEBHOOK_URL="${DISCORD_HARNESS_WEBHOOK_URL:-}"
if [[ -z "$WEBHOOK_URL" ]]; then
  if [[ "$REQUIRE_WEBHOOK" -eq 1 ]]; then
    err_log "DISCORD_HARNESS_WEBHOOK_URL is empty; --require-webhook was set; exiting non-zero"
    exit 67
  fi
  warn_log "DISCORD_HARNESS_WEBHOOK_URL is empty; skipping live send (no --require-webhook)"
  ensure_log_dir
  printf '%s skip status=%s feature_id=%s url=%s reason=%s\n' \
    "$(now_iso)" "$STATUS_KIND" "${FEATURE_ID:-unknown}" "$PUBLIC_REPORT_URL" \
    "no-webhook" >> "$LOG_FILE"
  exit 0
fi

# Discord hard limit 25 MiB on attachments. Refuse anything bigger.
MAX_BYTES=$((25 * 1024 * 1024))
JSON_SIZE=$(wc -c < "$REPORT_PATH" | tr -d ' ')
if [[ "$JSON_SIZE" -gt "$MAX_BYTES" ]]; then
  err_log "session-report.json is $JSON_SIZE bytes (>25 MiB); refusing to attach"
  ensure_log_dir
  printf '%s skip status=%s feature_id=%s url=%s reason=%s\n' \
    "$(now_iso)" "$STATUS_KIND" "${FEATURE_ID:-unknown}" "$PUBLIC_REPORT_URL" \
    "json-too-large" >> "$LOG_FILE"
  exit 0
fi
if [[ "$ATTACH_HTML" -eq 1 ]]; then
  HTML_SIZE=$(wc -c < "$HTML_PATH" | tr -d ' ')
  if [[ "$HTML_SIZE" -gt "$MAX_BYTES" ]]; then
    warn_log "rendered HTML is $HTML_SIZE bytes (>25 MiB); dropping HTML attachment"
    rm -f "$HTML_PATH"
    HTML_PATH=""
    ATTACH_HTML=0
  fi
fi

# Build curl args. We use multipart/form-data with payload_json as a
# form field plus file1 (HTML) and file2 (JSON).
CURL_ARGS=(
  -sS
  -o /tmp/notify_body.$$.txt
  -w '%{http_code}'
  --max-time 30
  -H 'User-Agent: slimy-harness/1.0'
  -F "payload_json=@${TMPDIR_PAYLOAD};type=application/json"
  -F "file2=@${REPORT_PATH};type=application/json;filename=${REPORT_BASENAME}"
)
if [[ "$ATTACH_HTML" -eq 1 ]]; then
  HTML_BASENAME="${REPORT_BASENAME%.json}.html"
  CURL_ARGS+=( -F "file1=@${HTML_PATH};type=text/html;filename=${HTML_BASENAME}" )
fi

send_once() {
  curl "${CURL_ARGS[@]}" "$WEBHOOK_URL"
}

HTTP_CODE="$(send_once)"

# Handle 429 once: parse retry_after and sleep
if [[ "$HTTP_CODE" == "429" ]]; then
  BODY_FILE="/tmp/notify_body.$$.txt"
  RETRY_PARSER_TMP="$(mktemp -t retry_parser.XXXXXX.py)"
  cat > "$RETRY_PARSER_TMP" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    ra = data.get("retry_after", 0)
    if isinstance(ra, (int, float)) and ra > 0:
        s = float(ra)
        if s > 10:
            s = 10
        print(f"{s:.2f}")
except Exception:
    print("")
PYEOF
  RETRY_AFTER="$(python3 "$RETRY_PARSER_TMP" "$BODY_FILE" 2>/dev/null || echo "")"
  rm -f "$RETRY_PARSER_TMP" 2>/dev/null || true
  if [[ -n "$RETRY_AFTER" ]]; then
    warn_log "Discord returned 429; sleeping ${RETRY_AFTER}s then retrying once"
    sleep "$RETRY_AFTER"
    HTTP_CODE="$(send_once)"
  fi
fi

# Cleanup body file
BODY_FILE="/tmp/notify_body.$$.txt"
BODY_PREVIEW=""
if [[ -f "$BODY_FILE" ]]; then
  BODY_PREVIEW="$(head -c 200 "$BODY_FILE" | tr '\n' ' ')"
  rm -f "$BODY_FILE" 2>/dev/null || true
fi

# Log (redacted)
ensure_log_dir
LOG_LINE="$(printf '%s send status=%s http=%s feature_id=%s url=%s html=%s json=%s body=%s' \
  "$(now_iso)" "$STATUS_KIND" "$HTTP_CODE" "${FEATURE_ID:-unknown}" \
  "$PUBLIC_REPORT_URL" \
  "$( [[ $ATTACH_HTML -eq 1 ]] && echo "yes" || echo "no" )" \
  "$REPORT_BASENAME" \
  "$(redact "$BODY_PREVIEW")"
)"
printf '%s\n' "$LOG_LINE" >> "$LOG_FILE"

# Also echo a redacted summary line to stderr for the closeout log
log "discord http=$HTTP_CODE status=$STATUS_KIND feature_id=${FEATURE_ID:-unknown} url=$PUBLIC_REPORT_URL"

# Decide final exit
if [[ "$HTTP_CODE" =~ ^2 ]]; then
  if [[ "$REQUIRE_WEBHOOK" -eq 1 ]]; then
    exit 0
  fi
  exit 0
fi

if [[ "$REQUIRE_WEBHOOK" -eq 1 ]]; then
  err_log "Discord returned HTTP $HTTP_CODE; --require-webhook is set; exiting non-zero"
  exit 68
fi

# Otherwise: notification failure must not break closeout
warn_log "Discord returned HTTP $HTTP_CODE; treating as non-fatal (closeout continues)"
exit 0
