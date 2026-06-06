#!/usr/bin/env bash
# notify-proof-dir-complete.sh — send a Discord completion notification from a
# proof directory when no session-report.json exists.
#
# Direct-task agents (SLIMY HARNESS DIRECT TASK) produce proof dirs with
# RESULT.md but no session-report.json. This adapter bridges the gap by
# creating a minimal session report from the proof dir, archiving it to
# the KB, and calling notify-session-complete.sh.
#
# Supports harness-metadata.json for rich source metadata.
# On NUC2 without webhook, relays to NUC1 via SSH.
#
# Usage:
#   notify-proof-dir-complete.sh [--dry-run] [--force] [--require-webhook] \
#     --proof-dir PATH [--repo-path PATH] [--repo-name NAME] \
#     [--feature-id ID] [--task-title TITLE] [--agent NAME] \
#     [--source-nuc nuc1|nuc2] [--source-hostname NAME] \
#     [--commit HASH] [--status STATUS] [--summary TEXT] \
#     <proof_dir>
#   notify-proof-dir-complete.sh --help
set -euo pipefail

SCRIPT_NAME="notify-proof-dir"
HARNESS_ROOT="${HARNESS_ROOT:-/home/slimy/slimy-harness}"
SEQUENCER_DIR="${HARNESS_ROOT}/sequencer"
KB_SESSIONS_DIR="${HARNESS_KB_SESSIONS:-/home/slimy/slimy-kb/raw/sessions}"
SESSION_REPORT_DEFAULT="/home/slimy/session-report.json"

DRY_RUN=0
FORCE=0
REQUIRE_WEBHOOK=0
FORWARD_FLAGS=()
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

usage() {
  cat <<USG
$SCRIPT_NAME — Discord completion notification from a proof directory

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
  --dry-run               Show what would be sent; do not call Discord
  --force                 Bypass dedupe check
  --require-webhook       Exit non-zero if webhook URL is missing

If harness-metadata.json exists in the proof dir, it is used as the metadata
source of truth. CLI flags override metadata file values. Missing fields are
inferred from the environment (hostname, git repo, etc.) and labelled
"unknown" if unavailable.

On NUC2 without DISCORD_HARNESS_WEBHOOK_URL, relays the session report to
NUC1 via SSH (requires HARNESS_NOTIFY_RELAY_HOST=nuc1 in env).
USG
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      FORWARD_FLAGS+=("--dry-run")
      shift
      ;;
    --force)
      FORCE=1
      FORWARD_FLAGS+=("--force")
      shift
      ;;
    --require-webhook)
      REQUIRE_WEBHOOK=1
      FORWARD_FLAGS+=("--require-webhook")
      shift
      ;;
    --proof-dir)
      PROOF_DIR="${2:-}"
      shift 2
      ;;
    --repo-path)
      OPT_REPO_PATH="$2"
      shift 2
      ;;
    --repo-name)
      OPT_REPO_NAME="$2"
      shift 2
      ;;
    --feature-id)
      OPT_FEATURE_ID="$2"
      shift 2
      ;;
    --task-title)
      OPT_TASK_TITLE="$2"
      shift 2
      ;;
    --agent)
      OPT_AGENT="$2"
      shift 2
      ;;
    --source-nuc)
      OPT_SOURCE_NUC="$2"
      shift 2
      ;;
    --source-hostname)
      OPT_SOURCE_HOSTNAME="$2"
      shift 2
      ;;
    --commit)
      OPT_COMMIT="$2"
      shift 2
      ;;
    --status)
      OPT_STATUS="$2"
      shift 2
      ;;
    --summary)
      OPT_SUMMARY="$2"
      shift 2
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
RESOLVED_FILE="$PROOF_DIR/harness-metadata.resolved.json"

if [[ ! -f "$RESULT_FILE" ]]; then
  warn "RESULT.md not found in $PROOF_DIR; creating minimal report from directory name"
fi

NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PROOF_BASENAME="$(basename "$PROOF_DIR")"
CURRENT_HOSTNAME="$(hostname 2>/dev/null || echo unknown)"

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
  local guessed
  guessed="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$guessed" ]]; then
    echo "$guessed"
    return
  fi
  echo ""
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
    return
  fi
  echo "unknown"
}

infer_commit() {
  if [[ -n "$OPT_COMMIT" ]]; then
    echo "$OPT_COMMIT"
    return
  fi
  local rpath
  rpath="$(infer_repo_path)"
  if [[ -n "$rpath" && -d "$rpath/.git" ]]; then
    git -C "$rpath" rev-parse --short HEAD 2>/dev/null || echo ""
  else
    echo ""
  fi
}

infer_branch() {
  local rpath
  rpath="$(infer_repo_path)"
  if [[ -n "$rpath" && -d "$rpath/.git" ]]; then
    git -C "$rpath" branch --show-current 2>/dev/null || echo ""
  else
    echo ""
  fi
}

FEATURE_ID=""
STATUS="completed"
VERDICT="PASS"
SUMMARY="Agent completed. Proof: $PROOF_DIR"
AGENT="opencode"
TASK_TITLE=""

if [[ -f "$RESULT_FILE" ]]; then
  VERDICT="$(grep -iE '^\*\*PASS\*\*|^## Verdict|^Verdict:|^PASS' "$RESULT_FILE" | head -1 || true)"
  if echo "$VERDICT" | grep -qiE 'FAIL'; then
    STATUS="fail"
  elif echo "$VERDICT" | grep -qiE 'WARN'; then
    STATUS="warn"
  fi
  FIRST_SUMMARY="$(sed -n '/^### What Was Done/,/^###/p' "$RESULT_FILE" | head -5 | tr '\n' ' ' | head -c 400 || true)"
  if [[ -n "$FIRST_SUMMARY" ]]; then
    SUMMARY="$FIRST_SUMMARY"
  fi
fi

FEATURE_GUESS="$(echo "$PROOF_BASENAME" | sed -E 's/^proof_//; s/_[0-9]{8}T[0-9]{6}Z$//' | head -c 120)"

PROGRESS_FILE="/home/slimy/claude-progress.md"
if [[ -f "$PROGRESS_FILE" ]]; then
  FEATURE_ID="$(grep -oP 'feature_id.*?:.*?"\K[^"]+' "$PROGRESS_FILE" | head -1 || true)"
  if [[ -z "$FEATURE_ID" ]]; then
    FEATURE_ID="$(grep -oP 'feature_list\.json.*?id.*?:.*?"\K[^"]+' "$PROGRESS_FILE" | head -1 || true)"
  fi
fi
if [[ -z "$FEATURE_ID" ]]; then
  FEATURE_ID="$FEATURE_GUESS"
fi

INFERRED_NUC="$(infer_nuc_from_hostname "$CURRENT_HOSTNAME")"
INFERRED_REPO_PATH="$(infer_repo_path)"
INFERRED_REPO_NAME="$(infer_repo_name)"
INFERRED_COMMIT="$(infer_commit)"
INFERRED_BRANCH="$(infer_branch)"

RESOLVE_TMP="$(mktemp -t resolve-metadata.XXXXXX.py)"
cat > "$RESOLVE_TMP" <<'PYEOF'
import json, os, sys

metadata_file = os.environ.get("METADATA_FILE", "")
resolved_file = os.environ.get("RESOLVED_FILE", "")

def g(key):
    v = os.environ.get("OPT_" + key, "")
    if v:
        return v
    v = os.environ.get("META_" + key, "")
    if v:
        return v
    return os.environ.get("INFERRED_" + key, "")

meta = {}
if metadata_file and os.path.isfile(metadata_file):
    try:
        with open(metadata_file, "r") as f:
            meta = json.load(f)
        if not isinstance(meta, dict):
            meta = {}
    except Exception:
        meta = {}

env_meta = {}
for k in ("feature_id", "task_title", "status", "agent", "source_nuc",
          "source_hostname", "repo_name", "repo_path", "commit", "branch",
          "proof_dir", "summary"):
    if k in meta:
        env_meta["META_" + k] = str(meta[k])

for k, v in env_meta.items():
    os.environ[k] = v

resolved = {
    "feature_id": g("feature_id") or "unknown",
    "task_title": g("task_title") or "",
    "status": g("status") or "completed",
    "agent": g("agent") or "opencode",
    "source_nuc": g("source_nuc") or "unknown",
    "source_hostname": g("source_hostname") or "unknown",
    "repo_name": g("repo_name") or "unknown",
    "repo_path": g("repo_path") or "",
    "commit": g("commit") or "",
    "branch": g("branch") or "",
    "proof_dir": g("proof_dir") or "",
    "summary": g("summary") or "Agent completed.",
}

for k in ("source_nuc", "repo_name", "source_hostname"):
    if not resolved[k]:
        resolved[k] = "unknown"

print(json.dumps(resolved, indent=2, ensure_ascii=False))
PYEOF

METADATA_FILE="$METADATA_FILE" \
RESOLVED_FILE="$RESOLVED_FILE" \
OPT_feature_id="$OPT_FEATURE_ID" \
OPT_task_title="$OPT_TASK_TITLE" \
OPT_status="$OPT_STATUS" \
OPT_agent="$OPT_AGENT" \
OPT_source_nuc="$OPT_SOURCE_NUC" \
OPT_source_hostname="$OPT_SOURCE_HOSTNAME" \
OPT_repo_name="$OPT_REPO_NAME" \
OPT_repo_path="$OPT_REPO_PATH" \
OPT_commit="$OPT_COMMIT" \
OPT_summary="$OPT_SUMMARY" \
INFERRED_feature_id="$FEATURE_ID" \
INFERRED_status="$STATUS" \
INFERRED_source_nuc="$INFERRED_NUC" \
INFERRED_source_hostname="$CURRENT_HOSTNAME" \
INFERRED_repo_name="$INFERRED_REPO_NAME" \
INFERRED_repo_path="$INFERRED_REPO_PATH" \
INFERRED_commit="$INFERRED_COMMIT" \
INFERRED_branch="$INFERRED_BRANCH" \
INFERRED_proof_dir="$PROOF_DIR" \
INFERRED_summary="$SUMMARY" \
python3 "$RESOLVE_TMP" > /tmp/resolve-output.$$.json 2>/dev/null || true
RESOLVED_META="$(cat /tmp/resolve-output.$$.json 2>/dev/null || echo "{}")"
rm -f /tmp/resolve-output.$$.json
rm -f "$RESOLVE_TMP"

if [[ -n "$RESOLVED_META" && "$RESOLVED_META" != "{}" ]]; then
  echo "$RESOLVED_META" > "$RESOLVED_FILE"
  log "Resolved metadata written to $RESOLVED_FILE"
fi

python3 -c "import json; json.load(open('$RESOLVED_FILE')); print('metadata valid')" 2>/dev/null || {
  warn "Resolved metadata is invalid JSON; using fallback"
  echo '{}' > "$RESOLVED_FILE"
}

R_FEATURE_ID="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('feature_id','unknown'))" 2>/dev/null || echo unknown)"
R_TASK_TITLE="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('task_title',''))" 2>/dev/null || echo "")"
R_STATUS="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('status','completed'))" 2>/dev/null || echo completed)"
R_AGENT="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('agent','opencode'))" 2>/dev/null || echo opencode)"
R_SOURCE_NUC="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('source_nuc','unknown'))" 2>/dev/null || echo unknown)"
R_SOURCE_HOSTNAME="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('source_hostname','unknown'))" 2>/dev/null || echo unknown)"
R_REPO_NAME="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('repo_name','unknown'))" 2>/dev/null || echo unknown)"
R_REPO_PATH="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('repo_path',''))" 2>/dev/null || echo "")"
R_COMMIT="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('commit',''))" 2>/dev/null || echo "")"
R_BRANCH="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('branch',''))" 2>/dev/null || echo "")"
R_SUMMARY="$(python3 -c "import json; d=json.load(open('$RESOLVED_FILE')); print(d.get('summary',''))" 2>/dev/null || echo "")"

TMP_REPORT="$(mktemp -t session-report-from-proof.XXXXXX.json)"
python3 > "$TMP_REPORT" << PYEOF
import json, os

proof_dir = "$PROOF_DIR"
result_file = "$RESULT_FILE"
feature_id = "$R_FEATURE_ID"
status = "$R_STATUS"
summary = "$R_SUMMARY"
agent = "$R_AGENT"
source_nuc = "$R_SOURCE_NUC"
source_hostname = "$R_SOURCE_HOSTNAME"
repo_name = "$R_REPO_NAME"
repo_path = "$R_REPO_PATH"
commit = "$R_COMMIT"
branch = "$R_BRANCH"
task_title = "$R_TASK_TITLE"
now = "$NOW_ISO"
basename = "$PROOF_BASENAME"

files_changed = []
for f in os.listdir(proof_dir):
    fp = os.path.join(proof_dir, f)
    if os.path.isfile(fp) and f not in ("RESULT.md", "harness-metadata.json", "harness-metadata.resolved.json"):
        files_changed.append(f)

report = {
    "session_id": now,
    "agent": agent or "unknown",
    "nuc": source_nuc or "unknown",
    "source_nuc": source_nuc or "unknown",
    "source_hostname": source_hostname or "unknown",
    "project": repo_name or "unknown",
    "repo_name": repo_name or "unknown",
    "repo_path": repo_path or "",
    "commit": commit or "",
    "branch": branch or "",
    "task_title": task_title or "",
    "feature_id": feature_id or "unknown",
    "prompt_type": "direct",
    "status": status or "completed",
    "summary": (summary or "Agent completed.")[:500],
    "changes": files_changed[:20],
    "tests": {"ran": True, "passed": status in ("completed", "pass"), "details": "Proof dir adapter: status from RESULT.md + metadata"},
    "blockers": [],
    "recommendation": {"next_feature_id": None, "reasoning": "", "risk_notes": ""},
    "kb_learnings": [],
    "duration_minutes": 0,
    "timestamp": now,
    "proof_dir": proof_dir,
    "proof_basename": basename,
    "generated_by": "notify-proof-dir-complete.sh"
}

print(json.dumps(report, indent=2, ensure_ascii=False))
PYEOF

python3 -c "import json; json.load(open('$TMP_REPORT')); print('report valid')" || {
  echo "[$SCRIPT_NAME] ERROR: generated report is invalid JSON" >&2
  rm -f "$TMP_REPORT"
  exit 65
}

REPORT_SLUG="$(printf '%s' "$PROOF_BASENAME" | tr -c 'a-zA-Z0-9.-' '_' | head -c 120)"
REPORT_BASENAME="report-proof-${REPORT_SLUG}.json"
ARCHIVE_PATH="${KB_SESSIONS_DIR}/${REPORT_BASENAME}"

if [[ -f "$ARCHIVE_PATH" ]]; then
  log "Archive already exists: $ARCHIVE_PATH (reusing for dedupe)"
else
  mkdir -p "$KB_SESSIONS_DIR"
  cp "$TMP_REPORT" "$ARCHIVE_PATH"
  log "Archived session report to $ARCHIVE_PATH"
fi

HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-/home/slimy/.slimy-harness.env}"
if [[ -f "$HARNESS_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$HARNESS_ENV_FILE"
  set +a
fi

WEBHOOK_URL="${DISCORD_HARNESS_WEBHOOK_URL:-}"
RELAY_HOST="${HARNESS_NOTIFY_RELAY_HOST:-}"

if [[ -z "$WEBHOOK_URL" ]]; then
  INFERRED_NUC_CHECK="$(infer_nuc_from_hostname "$CURRENT_HOSTNAME")"
  if [[ "$INFERRED_NUC_CHECK" == "nuc2" && -n "$RELAY_HOST" ]]; then
    log "No webhook on NUC2; relaying to $RELAY_HOST"
    RELAY_DIR="/tmp/harness-notify-relay"
    RELAY_PAYLOAD="/tmp/harness-notify-relay/${REPORT_BASENAME}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY-RUN: would relay $ARCHIVE_PATH to $RELAY_HOST:$RELAY_PAYLOAD"
      log "DRY-RUN: would ssh-exec notify-session-complete.sh on $RELAY_HOST"
    else
      ssh "$RELAY_HOST" "mkdir -p '$RELAY_DIR'" 2>/dev/null || {
        warn "Cannot mkdir on relay host $RELAY_HOST; skipping relay"
        rm -f "$TMP_REPORT"
        exit 0
      }
      scp "$ARCHIVE_PATH" "$RELAY_HOST:$RELAY_PAYLOAD" 2>/dev/null || {
        warn "Cannot scp to relay host $RELAY_HOST; skipping relay"
        rm -f "$TMP_REPORT"
        exit 0
      }
      RELAY_ARCHIVE="/home/slimy/slimy-kb/raw/sessions/${REPORT_BASENAME}"
      ssh "$RELAY_HOST" "mkdir -p /home/slimy/slimy-kb/raw/sessions && cp '$RELAY_PAYLOAD' '$RELAY_ARCHIVE' 2>/dev/null; bash /home/slimy/slimy-harness/sequencer/notify-session-complete.sh '$RELAY_ARCHIVE'" 2>&1 || {
        warn "Relay notify on $RELAY_HOST failed (non-fatal)"
      }
      log "Relay to $RELAY_HOST complete"
    fi
    rm -f "$TMP_REPORT"
    exit 0
  elif [[ -z "$RELAY_HOST" ]]; then
    if [[ "$REQUIRE_WEBHOOK" -eq 1 ]]; then
      echo "[$SCRIPT_NAME] ERROR: no webhook URL and no HARNESS_NOTIFY_RELAY_HOST set" >&2
      echo "[$SCRIPT_NAME] To enable NUC2 notifications, add to /home/slimy/.slimy-harness.env:" >&2
      echo "[$SCRIPT_NAME]   HARNESS_NOTIFY_RELAY_HOST=nuc1" >&2
      rm -f "$TMP_REPORT"
      exit 67
    fi
    warn "No webhook URL and no relay host; skipping notification"
    rm -f "$TMP_REPORT"
    exit 0
  fi
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  SYNC_SCRIPT="$SEQUENCER_DIR/sync-session-reports-to-nuc2.sh"
  if [[ -f "$SYNC_SCRIPT" ]]; then
    bash "$SYNC_SCRIPT" 2>&1 || warn "Session report sync to NUC2 failed (non-fatal)"
  fi
fi

NOTIFIER="$SEQUENCER_DIR/notify-session-complete.sh"
if [[ ! -f "$NOTIFIER" ]]; then
  echo "[$SCRIPT_NAME] ERROR: notifier not found at $NOTIFIER" >&2
  rm -f "$TMP_REPORT"
  exit 67
fi

log "Calling notify-session-complete.sh with ${FORWARD_FLAGS[*]} $ARCHIVE_PATH"
bash "$NOTIFIER" "${FORWARD_FLAGS[@]}" "$ARCHIVE_PATH"
NOTIFY_RC=$?

rm -f "$TMP_REPORT"

exit $NOTIFY_RC
