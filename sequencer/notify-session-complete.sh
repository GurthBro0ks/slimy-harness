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
#   notify-session-complete.sh [--dry-run] [--force] [--mark-dry-run]
#                              [--require-webhook] <session-report.json>
#   notify-session-complete.sh --help
#
# Idempotency / dedupe:
#   - By default, AT MOST ONE Discord notification is sent per session report
#     (identified by absolute path + file mtime + file size).
#   - After a successful send, a marker file is written under
#         /home/slimy/harness-logs/notify-state/<key>.sent
#   - A subsequent invocation that would target the same dedupe key will
#     log "already_notified" and exit 0 WITHOUT calling Discord.
#   - --force bypasses the dedupe check (manual retest only).
#   - --mark-dry-run makes --dry-run write the marker (for unit tests of
#     the dedupe logic that do not want to call Discord).
#   - dry-run NEVER writes a marker unless --mark-dry-run is also passed.
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
#   - Default mode is clean link-only. Attachments are opt-in:
#       HARNESS_NOTIFY_ATTACH_HTML=1  attach rendered .html snapshot
#       HARNESS_NOTIFY_ATTACH_JSON=1  attach the raw session-report.json
#     In multipart mode, payload_json is sent as a STRING form field, never
#     as a Discord file attachment.
#   - Writes a redacted log line to
#         /home/slimy/harness-logs/notifications.log
#   - Handles Discord 429 once by honouring retry_after. A successful 200/204
#     is NEVER retried.
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
STATE_DIR="${HARNESS_NOTIFY_STATE_DIR:-/home/slimy/harness-logs/notify-state}"
HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-/home/slimy/.slimy-harness.env}"
SEQUNCER_DIR_DEFAULT="/home/slimy/slimy-harness/sequencer"
RENDERER="${RENDERER:-${SEQUNCER_DIR_DEFAULT}/render-session-report-html.py}"
HARNESS_ROOT_DEFAULT="/home/slimy/slimy-harness"
HARNESS_ROOT="${HARNESS_ROOT:-$HARNESS_ROOT_DEFAULT}"
REDACT_TOKEN="[REDACTED-WEBHOOK]"

DRY_RUN=0
REQUIRE_WEBHOOK=0
FORCE=0
MARK_DRY_RUN=0
REPORT_PATH=""

usage() {
  cat <<USG
$SCRIPT_NAME — Discord completion webhook for harness agent runs

Usage:
  $SCRIPT_NAME [--dry-run] [--force] [--mark-dry-run]
               [--require-webhook] <session-report.json>
  $SCRIPT_NAME --help

Options:
  --dry-run           Show what would be sent; do not call Discord.
                      Does NOT create a dedupe marker (unless --mark-dry-run).
  --force             Bypass the dedupe check and send even if a marker
                      already exists. Manual retest only.
  --mark-dry-run      When combined with --dry-run, write the dedupe marker
                      so the next call (without --force) will skip. Useful
                      for tests of the dedupe logic.
  --require-webhook   Exit non-zero if the webhook URL is missing.
  --help              Show this help.

Environment (loaded from $HARNESS_ENV_FILE if present):
  DISCORD_HARNESS_WEBHOOK_URL   (required for live send)
  DISCORD_HARNESS_MENTION       e.g. <@427999592986968074>
  HARNESS_REPORT_BASE_URL       default: https://harness.slimyai.xyz
  HARNESS_NOTIFY_ON_SUCCESS     1 = mention on success too, 0 = off
  HARNESS_NOTIFY_PING_ON_SUCCESS  alias for HARNESS_NOTIFY_ON_SUCCESS
  HARNESS_NOTIFY_ATTACH_HTML    1 = attach generated .html snapshot (opt-in)
  HARNESS_NOTIFY_ATTACH_JSON    1 = attach raw session-report.json (opt-in)
USG
}

# ---- arg parsing -----------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --mark-dry-run)
      MARK_DRY_RUN=1
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

ensure_state_dir() {
  if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR" 2>/dev/null || true
  fi
}

# Compute a stable dedupe key for the report file. The key changes if the
# file's path, mtime, or size changes — which is the right behaviour
# because a NEW run that overwrites the same path SHOULD be notified.
compute_dedupe_key() {
  local path="$1"
  local abspath mtime size
  abspath="$(readlink -f -- "$path" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$path")"
  # stat -c '%Y' is mtime (seconds); %s is size. We want a stable hash
  # even if the file was just touched by a second agent run.
  mtime="$(stat -c '%Y' -- "$path" 2>/dev/null || stat -f '%m' -- "$path" 2>/dev/null || echo 0)"
  size="$(stat -c '%s' -- "$path" 2>/dev/null || stat -f '%z' -- "$path" 2>/dev/null || echo 0)"
  printf '%s|%s|%s' "$abspath" "$mtime" "$size" | python3 -c "
import sys, hashlib
data = sys.stdin.read().encode('utf-8')
print(hashlib.sha256(data).hexdigest())
"
}

# Write a marker file recording that we notified for this dedupe key.
# The marker is a small JSON-like text file (NOT a Discord attachment).
write_marker() {
  local key="$1"
  local marker_path="$STATE_DIR/$key.sent"
  local now="$2"
  local report_path_esc="$3"
  local status="$4"
  local feature_id="$5"
  local report_url="$6"
  local http_code="$7"
  local msg_id="${8:-}"
  ensure_state_dir
  cat > "$marker_path" <<MEOF
timestamp:    $now
report_path:  $report_path_esc
status:       $status
feature_id:   $feature_id
report_url:   $report_url
http_code:    $http_code
message_id:   ${msg_id:-}
MEOF
  # Restrictive perms — markers can include a Discord message id and we
  # treat the state dir as sensitive even though no secrets live there.
  chmod 0600 "$marker_path" 2>/dev/null || true
}

# Returns 0 if a marker exists for the key, 1 otherwise.
marker_exists() {
  local key="$1"
  [[ -f "$STATE_DIR/$key.sent" ]]
}

# Returns 0 if any .sent marker in STATE_DIR is older than MAX_AGE days.
# Used as a soft GC so the dir doesn't grow forever. Failures are silent.
gc_old_markers() {
  local max_age_days="${HARNESS_NOTIFY_MARKER_MAX_AGE_DAYS:-30}"
  [[ -d "$STATE_DIR" ]] || return 0
  find "$STATE_DIR" -maxdepth 1 -type f -name '*.sent' -mtime "+${max_age_days}" -delete 2>/dev/null || true
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

# Mention on WARN/FAIL/BLOCKED, and on SUCCESS when either
# HARNESS_NOTIFY_ON_SUCCESS=1 OR HARNESS_NOTIFY_PING_ON_SUCCESS=1.
SHOULD_MENTION=0
if [[ "$STATUS_KIND" != "success" ]]; then
  SHOULD_MENTION=1
elif [[ "${HARNESS_NOTIFY_ON_SUCCESS:-0}" == "1" || "${HARNESS_NOTIFY_PING_ON_SUCCESS:-0}" == "1" ]]; then
  SHOULD_MENTION=1
fi

MENTION_TEXT=""
MENTION_USER_ID=""
if [[ "$SHOULD_MENTION" -eq 1 && -n "${DISCORD_HARNESS_MENTION:-}" ]]; then
  MENTION_TEXT="${DISCORD_HARNESS_MENTION} "
  # Extract numeric user id from <@427999592986968074> or <@!427999592986968074>
  MENTION_USER_ID="$(printf '%s' "$DISCORD_HARNESS_MENTION" | python3 -c "
import sys, re
s = sys.stdin.read()
m = re.search(r'<@!?(\d+)>', s)
print(m.group(1) if m else '')
" 2>/dev/null || echo "")"
fi

# ---- attachments (default: NONE) -------------------------------------------
# By default the message is a clean, readable link-only notification. HTML
# and JSON attachments are opt-in and must be explicitly enabled. The
# payload body is NEVER sent as a Discord attachment.

ATTACH_HTML=0
HTML_PATH=""
# Default is 0 (clean link-only). Opt-in by setting HARNESS_NOTIFY_ATTACH_HTML=1.
if [[ "${HARNESS_NOTIFY_ATTACH_HTML:-0}" == "1" ]]; then
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

ATTACH_JSON=0
# Default is 0 (clean link-only). Opt-in by setting HARNESS_NOTIFY_ATTACH_JSON=1.
if [[ "${HARNESS_NOTIFY_ATTACH_JSON:-0}" == "1" ]]; then
  ATTACH_JSON=1
fi

# ---- build Discord content / embeds ---------------------------------------
# Discord max content 2000 chars; embeds have a separate limit of 6000 chars
# (title 256, description 4096, field name 256, field value 1024, total
# across all fields 6000). The report URL is the OWNER-GATED full HTML
# report served by mission-control on NUC2.

PROOF_LINE=""
if [[ -n "$PROOF_DIR" ]]; then
  PROOF_LINE="• proof: \`${PROOF_DIR}\`"
fi

# Trim summary further if it has odd whitespace / control chars
SUMMARY_TRIMMED="$(printf '%s' "$SUMMARY_TRIMMED" | tr '\r\n\t' '   ' | sed 's/  */ /g')"
if [[ "${#SUMMARY_TRIMMED}" -gt 380 ]]; then
  SUMMARY_TRIMMED="${SUMMARY_TRIMMED:0:380}…"
fi

# Content: mention (if any) + status line + report URL.
# We keep the report URL on its own line for easy copy/click.
if [[ -n "$MENTION_TEXT" ]]; then
  CONTENT="${MENTION_TEXT}${STATUS_EMOJI} **${FEATURE_ID:-unknown}** — ${STATUS_RAW:-unknown}
${PROOF_LINE}
Full HTML report: ${PUBLIC_REPORT_URL}"
else
  CONTENT="${STATUS_EMOJI} **${FEATURE_ID:-unknown}** — ${STATUS_RAW:-unknown}
${PROOF_LINE}
Full HTML report: ${PUBLIC_REPORT_URL}"
fi

# Clip to 1900 to leave headroom
if [[ "${#CONTENT}" -gt 1900 ]]; then
  CONTENT="${CONTENT:0:1900}…"
fi

# ---- build full payload as JSON (content + allowed_mentions + embeds) -----

TMPDIR_PAYLOAD="$(mktemp -t payload.XXXXXX.json)"
ATTACH_HTML_FLAG="$ATTACH_HTML"
ATTACH_JSON_FLAG="$ATTACH_JSON"
MENTION_USER_ID="$MENTION_USER_ID" \
REPO="${REPO:-}" \
AGENT="${AGENT:-}" \
NUC="${NUC:-}" \
SUMMARY_TRIMMED="$SUMMARY_TRIMMED" \
PROOF_DIR="$PROOF_DIR" \
PUBLIC_REPORT_URL="$PUBLIC_REPORT_URL" \
FEATURE_ID="${FEATURE_ID:-unknown}" \
STATUS_RAW="${STATUS_RAW:-unknown}" \
STATUS_KIND="$STATUS_KIND" \
STATUS_EMOJI="$STATUS_EMOJI" \
CONTENT="$CONTENT" \
REPORT_BASENAME="$REPORT_BASENAME" \
ATTACH_HTML_FLAG="$ATTACH_HTML_FLAG" \
ATTACH_JSON_FLAG="$ATTACH_JSON_FLAG" \
python3 - > "$TMPDIR_PAYLOAD" <<'PY'
import json, os, sys

def s(v):
    if v is None:
        return ""
    return str(v)

content = s(os.environ.get("CONTENT", ""))
feature_id = s(os.environ.get("FEATURE_ID", "unknown"))
status_raw = s(os.environ.get("STATUS_RAW", "unknown"))
status_kind = s(os.environ.get("STATUS_KIND", "unknown"))
status_emoji = s(os.environ.get("STATUS_EMOJI", ""))
repo = s(os.environ.get("REPO", ""))
agent = s(os.environ.get("AGENT", ""))
nuc = s(os.environ.get("NUC", ""))
proof_dir = s(os.environ.get("PROOF_DIR", ""))
public_report_url = s(os.environ.get("PUBLIC_REPORT_URL", ""))
summary = s(os.environ.get("SUMMARY_TRIMMED", ""))
mention_user_id = s(os.environ.get("MENTION_USER_ID", ""))
attach_html = s(os.environ.get("ATTACH_HTML_FLAG", "0")) == "1"
attach_json = s(os.environ.get("ATTACH_JSON_FLAG", "0")) == "1"
report_basename = s(os.environ.get("REPORT_BASENAME", ""))

# Discord limits: embed title 256, description 4096, field name 256, field value 1024.
embed_title = "Open full HTML session report"
if len(embed_title) > 256:
    embed_title = embed_title[:253] + "…"

# Description: short summary, no URL repetition (URL is in embed.url already).
desc = ""
if summary:
    desc = summary
if attach_html or attach_json:
    bits = []
    if attach_html:
        bits.append("HTML snapshot attached")
    if attach_json:
        bits.append("session-report.json attached")
    if bits:
        desc = (desc + "\n\n" if desc else "") + "• " + " • ".join(bits)
if not desc:
    desc = "Harness agent run complete. Click the title to open the full report."
if len(desc) > 4096:
    desc = desc[:4093] + "…"

embed = {
    "title": embed_title,
    "url": public_report_url,
    "description": desc,
    "color": {
        "success":  0x22c55e,
        "warning":  0xf59e0b,
        "failure":  0xef4444,
        "blocked":  0xa855f7,
    }.get(status_kind, 0x94a3b8),
    "fields": [
        {"name": "Status",  "value": f"`{status_raw}`", "inline": True},
        {"name": "Repo",    "value": f"`{repo or '?'}`", "inline": True},
        {"name": "Agent",   "value": f"`{agent or '?'}`", "inline": True},
        {"name": "NUC",     "value": f"`{nuc or '?'}`", "inline": True},
    ],
    "footer": {"text": "slimy-harness • notify-session-complete"},
}
if proof_dir:
    # field value limit 1024
    pv = proof_dir if len(proof_dir) <= 1024 else proof_dir[:1021] + "…"
    embed["fields"].append({"name": "Proof", "value": f"`{pv}`", "inline": False})
# Always add a final field that points to the report URL explicitly so it
# appears in the embed body too, not just in the URL link.
embed["fields"].append({"name": "Report", "value": public_report_url, "inline": False})

# allowed_mentions: explicit allow-list, no general parse.
# If we have a user id, allow that user. Never allow role/everyone/here.
allowed_mentions = {"parse": []}
if mention_user_id:
    allowed_mentions["users"] = [mention_user_id]

payload = {
    "content": content,
    "allowed_mentions": allowed_mentions,
    "embeds": [embed],
}

# Discord rejects payloads > 8 KiB. Hard-clip the description if needed.
raw = json.dumps(payload, ensure_ascii=False)
if len(raw) > 7800:
    embed["description"] = (embed["description"][:200] + "…") if embed["description"] else ""
    payload = {
        "content": content,
        "allowed_mentions": allowed_mentions,
        "embeds": [embed],
    }
print(json.dumps(payload, ensure_ascii=False))
PY

# ---- dry-run path ----------------------------------------------------------

if [[ "$DRY_RUN" -eq 1 ]]; then
  _WEBHOOK_LEN="${#DISCORD_HARNESS_WEBHOOK_URL}"
  _WEBHOOK_LEN="${_WEBHOOK_LEN:-0}"
  # Compute dedupe key (read-only; dry-run does not write unless --mark-dry-run).
  _DEDUPE_KEY="$(compute_dedupe_key "$REPORT_PATH")"
  _MARKER_STATE="absent"
  if marker_exists "$_DEDUPE_KEY"; then
    _MARKER_STATE="present (would skip with already_notified)"
  fi
  _DRY_OUT="$(cat <<DRY
[notify-session-complete] dry-run
  feature_id:        $FEATURE_ID
  repo:              $REPO
  agent:             $AGENT
  nuc:               $NUC
  status_raw:        $STATUS_RAW
  status_kind:       $STATUS_KIND
  status_emoji:      $STATUS_EMOJI
  mention:           $( [[ "$SHOULD_MENTION" -eq 1 ]] && echo "yes" || echo "no" )
  mention_user_id:   ${MENTION_USER_ID:-(none)}
  public_report_url: $PUBLIC_REPORT_URL
  proof_dir:         ${PROOF_DIR:-(none)}
  attach_html:       $( [[ $ATTACH_HTML -eq 1 ]] && echo "yes ($HTML_PATH)" || echo "no" )
  attach_json:       $( [[ $ATTACH_JSON -eq 1 ]] && echo "yes ($REPORT_PATH)" || echo "no" )
  content_chars:     ${#CONTENT}
  payload_bytes:     $( wc -c < "$TMPDIR_PAYLOAD" | tr -d ' ' )
  dedupe_key:        ${_DEDUPE_KEY:0:16}...
  dedupe_marker:     $_MARKER_STATE
  force:             $( [[ $FORCE -eq 1 ]] && echo "yes (would bypass dedupe)" || echo "no" )
  mark_dry_run:      $( [[ $MARK_DRY_RUN -eq 1 ]] && echo "yes (would write marker after dry-run)" || echo "no" )
  payload_json:
$( head -c 1500 "$TMPDIR_PAYLOAD" )
DRY
)"
  redact "$_DRY_OUT"
  unset _DRY_OUT _WEBHOOK_LEN _DEDUPE_KEY _MARKER_STATE
  if [[ "$MARK_DRY_RUN" -eq 1 ]]; then
    _DEDUPE_KEY="$(compute_dedupe_key "$REPORT_PATH")"
    write_marker "$_DEDUPE_KEY" \
      "$(now_iso)" \
      "$REPORT_PATH" \
      "$STATUS_KIND" \
      "${FEATURE_ID:-unknown}" \
      "$PUBLIC_REPORT_URL" \
      "dry-run" \
      ""
    log "dry-run wrote dedupe marker ${_DEDUPE_KEY:0:12}..."
  fi
  exit 0
fi

# ---- dedupe / idempotency --------------------------------------------------

# Default: at most one Discord notification per dedupe key. The key is
# (absolute report path, mtime, size) — a new run on the same path with
# different content gets a NEW key (and is therefore notified once).
DEDUPE_KEY="$(compute_dedupe_key "$REPORT_PATH")"

# Best-effort GC of very old markers (default 30 days, overridable).
gc_old_markers || true

if [[ "$FORCE" -ne 1 ]] && marker_exists "$DEDUPE_KEY"; then
  # Already notified. Log a skip line, exit 0, do NOT touch Discord.
  ensure_log_dir
  printf '%s skip status=%s feature_id=%s url=%s reason=%s\n' \
    "$(now_iso)" "$STATUS_KIND" "${FEATURE_ID:-unknown}" "$PUBLIC_REPORT_URL" \
    "already_notified" >> "$LOG_FILE"
  log "already_notified: dedupe_key=${DEDUPE_KEY:0:12}... report=${REPORT_PATH}"
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

# Build curl args.
# - Default (no attachments): plain application/json POST with the full
#   payload as the request body. Discord returns 204 No Content.
# - With attachments: multipart/form-data where payload_json is sent as
#   a STRING form field (NOT a file), and the actual files go in the
#   files[] array. This keeps the message clean and avoids a visible
#   payload_*.json file in the Discord channel.
# - ?wait=true is appended so Discord returns the message body, which
#   we use to log the delivered message id and to verify the send.

USE_MULTIPART=0
if [[ "$ATTACH_HTML" -eq 1 || "$ATTACH_JSON" -eq 1 ]]; then
  USE_MULTIPART=1
fi

BODY_FILE="/tmp/notify_body.$$.txt"
CURL_ARGS=( -sS -o "$BODY_FILE" -w '%{http_code}' --max-time 30
            -H 'User-Agent: slimy-harness/1.0' )

if [[ "$USE_MULTIPART" -eq 1 ]]; then
  # payload_json is sent as a STRING form field, never a file.
  PAYLOAD_STRING="$(cat "$TMPDIR_PAYLOAD")"
  CURL_ARGS+=( -F "payload_json=${PAYLOAD_STRING}" )
  unset PAYLOAD_STRING
  if [[ "$ATTACH_HTML" -eq 1 ]]; then
    HTML_BASENAME="${REPORT_BASENAME%.json}.html"
    CURL_ARGS+=( -F "files[0]=@${HTML_PATH};type=text/html;filename=${HTML_BASENAME}" )
  fi
  if [[ "$ATTACH_JSON" -eq 1 ]]; then
    CURL_ARGS+=( -F "files[1]=@${REPORT_PATH};type=application/json;filename=${REPORT_BASENAME}" )
  fi
  WEBHOOK_URL_WITH_WAIT="${WEBHOOK_URL}?wait=true"
else
  # application/json POST with the full payload as the body.
  CURL_ARGS+=( -H 'Content-Type: application/json; charset=utf-8'
               --data-binary "@${TMPDIR_PAYLOAD}" )
  WEBHOOK_URL_WITH_WAIT="${WEBHOOK_URL}?wait=true"
fi

send_once() {
  curl "${CURL_ARGS[@]}" "$WEBHOOK_URL_WITH_WAIT"
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
MSG_ID=""
if [[ -f "$BODY_FILE" ]]; then
  # Extract the Discord message id BEFORE the body file is removed so the
  # dedupe marker can record the delivered message id.
  MSG_ID="$(python3 -c "
import json, sys
try:
    with open('$BODY_FILE', 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(data.get('id', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")"
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
  if [[ -n "$MSG_ID" ]]; then
    log "discord delivered message_id=$MSG_ID"
  fi
  # Write dedupe marker so the next invocation skips.
  write_marker "$DEDUPE_KEY" \
    "$(now_iso)" \
    "$REPORT_PATH" \
    "$STATUS_KIND" \
    "${FEATURE_ID:-unknown}" \
    "$PUBLIC_REPORT_URL" \
    "$HTTP_CODE" \
    "$MSG_ID"
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
