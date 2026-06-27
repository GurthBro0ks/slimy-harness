#!/usr/bin/env bash
# archive-proof-dir-session.sh — archive safe proof-dir metadata and refresh
# the harness session index without reading Discord env or sending notifications.
set -euo pipefail

SCRIPT_NAME="archive-proof-dir-session"
HARNESS_ROOT="${HARNESS_ROOT:-/home/slimy/slimy-harness}"
SEQUENCER_DIR="${HARNESS_ROOT}/sequencer"
KB_SESSIONS_DIR="${HARNESS_KB_SESSIONS:-/home/slimy/slimy-kb/raw/sessions}"
INDEX_OUTPUT=""
PROOF_DIR=""
OPT_REPO_PATH=""
OPT_REPO_NAME=""
OPT_FEATURE_ID=""
OPT_TASK_TITLE=""
OPT_AGENT=""
OPT_SOURCE_NUC=""
OPT_SOURCE_HOSTNAME=""
OPT_COMMIT=""
OPT_STATUS=""
OPT_SUMMARY=""
NO_INDEX=0

usage() {
  cat <<USAGE
$SCRIPT_NAME — archive a proof directory as a safe harness session report

Usage:
  $SCRIPT_NAME [OPTIONS] <proof_dir>
  $SCRIPT_NAME --help

Options:
  --proof-dir PATH        Proof directory (required, or positional arg)
  --repo-path PATH        Repository filesystem path
  --repo-name NAME        Repository display name
  --feature-id ID         Feature identifier
  --task-title TITLE      Human-readable task title
  --agent NAME            Agent name (opencode|claude|codex|manual)
  --source-nuc NUC        Source NUC (nuc1|nuc2)
  --source-hostname NAME  Source hostname
  --commit HASH           Commit hash
  --status STATUS         Task status
  --summary TEXT          Task summary
  --sessions-dir PATH     Session archive directory
  --index-output PATH     Safe session index output path
  --no-index              Archive only; do not regenerate index

This command reads RESULT.md key=value metadata and harness-metadata.json
allowlisted fields when present. It does not read .env files, Discord webhook
configuration, raw proof logs, raw diffs, raw env dumps, or private file
contents. It never sends Discord notifications.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proof-dir)
      PROOF_DIR="${2:-}"
      shift 2
      ;;
    --repo-path)
      OPT_REPO_PATH="${2:-}"
      shift 2
      ;;
    --repo-name)
      OPT_REPO_NAME="${2:-}"
      shift 2
      ;;
    --feature-id)
      OPT_FEATURE_ID="${2:-}"
      shift 2
      ;;
    --task-title)
      OPT_TASK_TITLE="${2:-}"
      shift 2
      ;;
    --agent)
      OPT_AGENT="${2:-}"
      shift 2
      ;;
    --source-nuc)
      OPT_SOURCE_NUC="${2:-}"
      shift 2
      ;;
    --source-hostname)
      OPT_SOURCE_HOSTNAME="${2:-}"
      shift 2
      ;;
    --commit)
      OPT_COMMIT="${2:-}"
      shift 2
      ;;
    --status)
      OPT_STATUS="${2:-}"
      shift 2
      ;;
    --summary)
      OPT_SUMMARY="${2:-}"
      shift 2
      ;;
    --sessions-dir)
      KB_SESSIONS_DIR="${2:-}"
      shift 2
      ;;
    --index-output)
      INDEX_OUTPUT="${2:-}"
      shift 2
      ;;
    --no-index)
      NO_INDEX=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      PROOF_DIR="${1:-}"
      break
      ;;
    -*)
      echo "[$SCRIPT_NAME] ERROR: unknown flag: $1" >&2
      usage >&2
      exit 64
      ;;
    *)
      PROOF_DIR="$1"
      shift
      ;;
  esac
done

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$SCRIPT_NAME] $*"; }
warn() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$SCRIPT_NAME] WARN: $*" >&2; }

if [[ -z "$PROOF_DIR" ]]; then
  echo "[$SCRIPT_NAME] ERROR: no proof directory given" >&2
  usage >&2
  exit 64
fi

if [[ ! -d "$PROOF_DIR" ]]; then
  echo "[$SCRIPT_NAME] ERROR: proof directory not found: $PROOF_DIR" >&2
  exit 66
fi

PROOF_DIR="$(cd "$PROOF_DIR" && pwd)"
RESULT_FILE="$PROOF_DIR/RESULT.md"
METADATA_FILE="$PROOF_DIR/harness-metadata.json"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PROOF_BASENAME="$(basename "$PROOF_DIR")"
CURRENT_HOSTNAME="$(hostname 2>/dev/null || echo unknown)"
REPORT_SLUG="$(printf '%s' "$PROOF_BASENAME" | tr -c 'a-zA-Z0-9.-' '_' | head -c 120)"
REPORT_BASENAME="report-proof-${REPORT_SLUG}.json"
ARCHIVE_PATH="${KB_SESSIONS_DIR}/${REPORT_BASENAME}"
REPORT_BASE_URL="${HARNESS_REPORT_BASE_URL:-https://harness.slimyai.xyz}"
PUBLIC_REPORT_URL="${REPORT_BASE_URL}/reports/sessions/${REPORT_BASENAME}"

if [[ -z "$INDEX_OUTPUT" ]]; then
  INDEX_OUTPUT="${KB_SESSIONS_DIR}/harness-session-index.json"
fi

infer_nuc_from_hostname() {
  local h="$1"
  if echo "$h" | grep -qiE 'nuc1|slimy-nuc1'; then
    echo "nuc1"
  elif echo "$h" | grep -qiE 'nuc2|slimy-nuc2'; then
    echo "nuc2"
  else
    echo "unknown"
  fi
}

infer_repo_path() {
  if [[ -n "$OPT_REPO_PATH" ]]; then
    echo "$OPT_REPO_PATH"
    return
  fi
  git rev-parse --show-toplevel 2>/dev/null || true
}

infer_repo_name() {
  if [[ -n "$OPT_REPO_NAME" ]]; then
    echo "$OPT_REPO_NAME"
    return
  fi
  local rpath
  rpath="$(infer_repo_path)"
  if [[ -n "$rpath" ]]; then
    basename "$rpath"
  else
    echo "unknown"
  fi
}

infer_commit() {
  if [[ -n "$OPT_COMMIT" ]]; then
    echo "$OPT_COMMIT"
    return
  fi
  local rpath
  rpath="$(infer_repo_path)"
  if [[ -n "$rpath" && -d "$rpath/.git" ]]; then
    git -C "$rpath" rev-parse --short HEAD 2>/dev/null || true
  fi
}

infer_branch() {
  local rpath
  rpath="$(infer_repo_path)"
  if [[ -n "$rpath" && -d "$rpath/.git" ]]; then
    git -C "$rpath" branch --show-current 2>/dev/null || true
  fi
}

INFERRED_NUC="$(infer_nuc_from_hostname "$CURRENT_HOSTNAME")"
INFERRED_REPO_PATH="$(infer_repo_path)"
INFERRED_REPO_NAME="$(infer_repo_name)"
INFERRED_COMMIT="$(infer_commit)"
INFERRED_BRANCH="$(infer_branch)"

TMP_REPORT="$(mktemp -t archive-proof-session.XXXXXX.json)"
cleanup() {
  rm -f "$TMP_REPORT"
}
trap cleanup EXIT

RESULT_FILE="$RESULT_FILE" \
METADATA_FILE="$METADATA_FILE" \
PROOF_DIR="$PROOF_DIR" \
PROOF_BASENAME="$PROOF_BASENAME" \
NOW_ISO="$NOW_ISO" \
PUBLIC_REPORT_URL="$PUBLIC_REPORT_URL" \
OPT_FEATURE_ID="$OPT_FEATURE_ID" \
OPT_TASK_TITLE="$OPT_TASK_TITLE" \
OPT_STATUS="$OPT_STATUS" \
OPT_AGENT="$OPT_AGENT" \
OPT_SOURCE_NUC="$OPT_SOURCE_NUC" \
OPT_SOURCE_HOSTNAME="$OPT_SOURCE_HOSTNAME" \
OPT_REPO_NAME="$OPT_REPO_NAME" \
OPT_REPO_PATH="$OPT_REPO_PATH" \
OPT_COMMIT="$OPT_COMMIT" \
OPT_SUMMARY="$OPT_SUMMARY" \
INFERRED_FEATURE_ID="$REPORT_SLUG" \
INFERRED_STATUS="completed" \
INFERRED_SOURCE_NUC="$INFERRED_NUC" \
INFERRED_SOURCE_HOSTNAME="$CURRENT_HOSTNAME" \
INFERRED_REPO_NAME="$INFERRED_REPO_NAME" \
INFERRED_REPO_PATH="$INFERRED_REPO_PATH" \
INFERRED_COMMIT="$INFERRED_COMMIT" \
INFERRED_BRANCH="$INFERRED_BRANCH" \
python3 > "$TMP_REPORT" <<'PY'
import json
import os
import re
from pathlib import Path

SAFE_METADATA_KEYS = {
    "feature_id",
    "task_title",
    "status",
    "agent",
    "source_nuc",
    "source_hostname",
    "repo_name",
    "repo_path",
    "commit",
    "branch",
    "summary",
}
SENSITIVE_NAMES = (
    "BOT_" + "TOKEN",
    "OPEN" + "AI_API_" + "KEY",
    "ANTHROPIC_API_" + "KEY",
    "GEMINI_API_" + "KEY",
    "ZAI_API_" + "KEY",
)
HOOK_PATH = "api/" + "web" + "hooks"
HOOK_URL_PATTERN = r"https" + r"://(?:[^/\s]+/)?" + re.escape(HOOK_PATH) + r"/[^\s\"']+"
SENSITIVE_PATTERNS = [
    re.compile(HOOK_URL_PATTERN, re.I),
    re.compile(r"\bsk-[A-Za-z0-9][A-Za-z0-9_-]{12,}\b"),
    re.compile(r"\b[A-Za-z0-9_-]{32,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\b"),
    re.compile(r"(?i)\b(?:pass(?:word)?|secret|token|key)\s*[:=]\s*\S+"),
    *(re.compile(re.escape(name), re.I) for name in SENSITIVE_NAMES),
]


def sensitive(text):
    return any(pattern.search(text) for pattern in SENSITIVE_PATTERNS)


def safe_string(value, limit=500):
    if value is None:
        return ""
    text = str(value).strip()
    if sensitive(text):
        return "[REDACTED]"
    return text[:limit]


def parse_result_fields(path):
    fields = {}
    if not path or not os.path.isfile(path):
        return fields
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            if re.fullmatch(r"[A-Z0-9_]+", key):
                fields[key] = safe_string(value)
    return fields


def load_metadata(path):
    if not path or not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        return {}
    if not isinstance(data, dict):
        return {}
    return {key: safe_string(data.get(key)) for key in SAFE_METADATA_KEYS if key in data}


def pick(key, result_key=None, default=""):
    opt = os.environ.get("OPT_" + key.upper(), "")
    if opt:
        return safe_string(opt)
    if key in metadata and metadata[key]:
        return metadata[key]
    if result_key and result_key in result_fields and result_fields[result_key]:
        return result_fields[result_key]
    inferred = os.environ.get("INFERRED_" + key.upper(), "")
    if inferred:
        return safe_string(inferred)
    return default


def classify_tests(fields, status_value):
    validation = fields.get("VALIDATION", "")
    manual_qa = fields.get("MANUAL_QA_STATUS", "")
    result = fields.get("RESULT", status_value)
    summary_field = fields.get("SUMMARY", "")
    combined = " ".join([validation, manual_qa, result, summary_field]).lower()
    normalized = re.sub(r"[-_]+", " ", combined)

    if re.search(r"\bsmoke only\b|\broute smoke\b|\bsmoke\b", normalized):
        return {
            "ran": False,
            "passed": False,
            "label": "SMOKE ONLY",
            "details": "Proof dir adapter: smoke-only validation from RESULT.md metadata",
        }

    if re.search(r"tests? not run|no tests run|not required|read only|discovery only", normalized):
        return {
            "ran": False,
            "passed": False,
            "label": "TESTS NOT RUN",
            "details": "Proof dir adapter: tests were not run according to RESULT.md metadata",
        }

    if re.search(r"test fail|tests fail|lint fail|typecheck fail|build fail|validation fail", normalized):
        return {
            "ran": True,
            "passed": False,
            "label": "TESTS FAIL",
            "details": "Proof dir adapter: failing test/validation command evidence from RESULT.md metadata",
        }

    ran_markers = (
        r"lint pass|typecheck pass|test pass|tests pass|build pass|"
        r"focused .* pass|shell syntax pass|validate .* pass|validation .* pass"
    )
    tests_ran = bool(re.search(ran_markers, normalized))
    result_status = str(result or status_value or "").lower()
    status_passed = result_status in ("completed", "pass", "passed", "success", "ok", "done")

    if tests_ran:
        return {
            "ran": True,
            "passed": status_passed,
            "label": "TESTS PASS" if status_passed else "TESTS FAIL",
            "details": "Proof dir adapter: test/validation command evidence from RESULT.md metadata",
        }

    if status_passed:
        return {
            "ran": False,
            "passed": False,
            "label": "TESTS NOT RUN",
            "details": "Proof dir adapter: proof passed, but no test-run evidence was found in RESULT.md metadata",
        }

    return {
        "ran": True,
        "passed": False,
        "label": "TESTS FAIL",
        "details": "Proof dir adapter: failing RESULT.md status",
    }


def bool_value(text):
    lowered = str(text or "").strip().lower()
    if lowered in {"yes", "true", "1", "pass", "passed"}:
        return True
    if lowered in {"no", "false", "0", "fail", "failed", "none"}:
        return False
    return None


def safe_proof_files(proof_dir):
    safe_names = {
        "RESULT.md",
        "harness-metadata.json",
        "machine.txt",
        "git-preflight.txt",
        "source-inspection.txt",
        "implementation-notes.md",
        "validation.txt",
        "validation-summary.txt",
    }
    result = []
    for name in sorted(safe_names):
        path = Path(proof_dir) / name
        if path.is_file():
            result.append("[REDACTED]" if sensitive(name) else name)
    return result


result_file = os.environ["RESULT_FILE"]
metadata_file = os.environ["METADATA_FILE"]
proof_dir = os.environ["PROOF_DIR"]
now = os.environ["NOW_ISO"]
basename = os.environ["PROOF_BASENAME"]
report_url = os.environ["PUBLIC_REPORT_URL"]
result_fields = parse_result_fields(result_file)
metadata = load_metadata(metadata_file)

status = pick("status", "RESULT", "completed")
if status.upper() in {"PASS", "WARN", "FAIL"}:
    status = status.lower()

feature_id = pick("feature_id", "PHASE", "unknown")
summary = pick("summary", "SUMMARY", f"Agent completed. Proof: {basename}")
repo_name = pick("repo_name", "TARGET_REPO", "unknown")
if repo_name.startswith("/"):
    repo_name = Path(repo_name).name
report = {
    "session_id": now,
    "agent": pick("agent", None, "opencode"),
    "nuc": pick("source_nuc", "TARGET_MACHINE", "unknown").lower(),
    "source_nuc": pick("source_nuc", "TARGET_MACHINE", "unknown").lower(),
    "source_hostname": pick("source_hostname", None, "unknown"),
    "project": repo_name,
    "repo_name": repo_name,
    "repo_path": pick("repo_path", "TARGET_REPO", ""),
    "commit": pick("commit", "COMMIT_SHA", ""),
    "branch": safe_string(os.environ.get("INFERRED_BRANCH", "")),
    "task_title": pick("task_title", "PHASE", ""),
    "feature_id": feature_id,
    "prompt_type": "direct",
    "status": status or "completed",
    "result": result_fields.get("RESULT", status),
    "summary": summary,
    "changes": safe_proof_files(proof_dir),
    "tests": classify_tests(result_fields, status),
    "blockers": [],
    "recommendation": {"next_feature_id": None, "reasoning": "", "risk_notes": ""},
    "kb_learnings": [],
    "duration_minutes": 0,
    "timestamp": now,
    "created_at": now,
    "archived_at": now,
    "proof_dir": proof_dir,
    "proof_basename": basename,
    "report_url": report_url,
    "discord_sent": bool_value(result_fields.get("DISCORD_SENT", "no")),
    "notify_mode": result_fields.get("NOTIFY_MODE", "archive_only"),
    "dedupe_result": result_fields.get("DEDUPE_RESULT", "not_checked"),
    "services_restarted": bool_value(result_fields.get("SERVICES_RESTARTED", "no")),
    "caddy_changed": bool_value(result_fields.get("CADDY_CHANGED", "no")),
    "dns_changed": bool_value(result_fields.get("DNS_CHANGED", "no")),
    "cron_changed": bool_value(result_fields.get("CRON_CHANGED", "no")),
    "timer_changed": bool_value(result_fields.get("TIMER_CHANGED", "no")),
    "tmux_changed": bool_value(result_fields.get("TMUX_CHANGED", "no")),
    "secrets_printed": bool_value(result_fields.get("SECRETS_PRINTED", "no")),
    "webhook_values_printed": bool_value(result_fields.get("WEBHOOK_VALUES_PRINTED", "no")),
    "generated_by": "archive-proof-dir-session.sh",
}

encoded = json.dumps(report, sort_keys=True)
if sensitive(encoded):
    raise SystemExit("generated report failed safety scan")
print(json.dumps(report, indent=2, ensure_ascii=False))
PY

python3 -c "import json; json.load(open('$TMP_REPORT')); print('REPORT_VALID=yes')" >/dev/null

if [[ -f "$ARCHIVE_PATH" ]]; then
  if cmp -s "$TMP_REPORT" "$ARCHIVE_PATH"; then
    log "Archive already exists: $ARCHIVE_PATH (reusing)"
  else
    cp "$TMP_REPORT" "$ARCHIVE_PATH"
    chmod 0600 "$ARCHIVE_PATH" 2>/dev/null || true
    log "Updated session report at $ARCHIVE_PATH"
  fi
else
  mkdir -p "$KB_SESSIONS_DIR"
  cp "$TMP_REPORT" "$ARCHIVE_PATH"
  chmod 0600 "$ARCHIVE_PATH" 2>/dev/null || true
  log "Archived session report to $ARCHIVE_PATH"
fi

INDEX_STATUS="skipped"
if [[ "$NO_INDEX" -eq 0 ]]; then
  EXPORTER="$SEQUENCER_DIR/export-session-index.sh"
  if [[ ! -f "$EXPORTER" ]]; then
    echo "[$SCRIPT_NAME] ERROR: exporter not found: $EXPORTER" >&2
    exit 67
  fi
  mkdir -p "$(dirname "$INDEX_OUTPUT")"
  INDEX_STDERR="$(mktemp -t archive-proof-index.XXXXXX.err)"
  if bash "$EXPORTER" --sessions-dir "$KB_SESSIONS_DIR" --output "$INDEX_OUTPUT" 2>"$INDEX_STDERR"; then
    INDEX_STATUS="written"
  else
    cat "$INDEX_STDERR" >&2
    rm -f "$INDEX_STDERR"
    exit 65
  fi
  rm -f "$INDEX_STDERR"
  log "Regenerated session index at $INDEX_OUTPUT"
fi

printf 'ARCHIVE_PATH=%s\n' "$ARCHIVE_PATH"
printf 'REPORT_BASENAME=%s\n' "$REPORT_BASENAME"
printf 'REPORT_URL=%s\n' "$PUBLIC_REPORT_URL"
printf 'INDEX_PATH=%s\n' "$INDEX_OUTPUT"
printf 'INDEX_STATUS=%s\n' "$INDEX_STATUS"
