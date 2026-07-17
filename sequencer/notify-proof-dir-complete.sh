#!/usr/bin/env bash
# notify-proof-dir-complete.sh — send a Discord completion notification from a
# proof directory when no session-report.json exists.
#
# Direct-task agents (SLIMY HARNESS DIRECT TASK) produce proof dirs with
# RESULT.md but no session-report.json. This adapter bridges the gap by
# creating a minimal session report from the proof dir, archiving it to
# the KB, and calling notify-session-complete.sh.
#
# Supports harness-metadata.json for rich source metadata. Discord delivery
# and NUC2 report synchronization are separate, explicitly authorized modes.
#
# Usage:
#   notify-proof-dir-complete.sh --mode MODE [--dry-run] [--force] \
#     [--discord-authorized] [--sync-authorized] [--sync-file PATH ...] \
#     [--require-webhook] \
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
PROOF_INDEX_DEFAULT="/home/slimy/harness-logs/state/proof-index.json"

DRY_RUN=0
FORCE=0
FORCE_SYNC=0
MODE=""
DISCORD_AUTHORIZED=0
SYNC_AUTHORIZED=0
SYNC_FILES=()
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
  --mode MODE            Required: discord-only, sync-only, or both
  --discord-authorized   Authorize the Discord action selected by MODE
  --sync-authorized      Authorize the NUC2 sync action selected by MODE
  --sync-file PATH       Exact JSON file to sync; repeat for each file
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
  --dry-run               Redacted preflight only; no external command/marker
  --force                 Bypass Discord dedupe only
  --force-sync            Bypass sync dedupe only
  --require-webhook       Exit non-zero if webhook URL is missing

If harness-metadata.json exists in the proof dir, it is used as the metadata
source of truth. CLI flags override metadata file values. Missing fields are
inferred from the environment (hostname, git repo, etc.) and labelled
"unknown" if unavailable.

No mode is inferred from webhook, host, relay, or NUC2 availability. With no
--mode the command refuses before creating reports, markers, or side effects.
discord-only never invokes ssh, rsync, or the sync helper. sync-only never
loads Discord configuration or invokes the Discord notifier.
USG
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --discord-authorized)
      DISCORD_AUTHORIZED=1
      shift
      ;;
    --sync-authorized)
      SYNC_AUTHORIZED=1
      shift
      ;;
    --sync-file)
      SYNC_FILES+=("${2:-}")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --force-sync)
      FORCE_SYNC=1
      shift
      ;;
  --require-webhook)
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

emit_no_action() {
  echo "STATE=NO_ACTION"
  echo "DISCORD_SENT=no"
  echo "NOTIFY_MODE=none"
  echo "DEDUPE_RESULT=not_checked"
  echo "SYNC_ATTEMPTED=no"
  echo "SYNC_RESULT=NO_ACTION"
  echo "NUC2_ACCESSED=no"
  echo "REPORT_URL=none"
}

if [[ -z "$MODE" ]]; then
  emit_no_action
  echo "ERROR=explicit_--mode_required" >&2
  usage >&2
  exit 64
fi

case "$MODE" in
  discord-only|sync-only|both) ;;
  *)
    emit_no_action
    echo "STATE=REFUSED_UNAUTHORIZED_MODE"
    echo "ERROR=invalid_mode:$MODE" >&2
    exit 64
    ;;
esac

if [[ "$DRY_RUN" -eq 0 ]]; then
  if [[ ( "$MODE" == "discord-only" || "$MODE" == "both" ) && "$DISCORD_AUTHORIZED" -ne 1 ]]; then
    echo "STATE=REFUSED_UNAUTHORIZED_MODE"
    echo "DISCORD_SENT=no"
    echo "NOTIFY_MODE=$MODE"
    echo "DEDUPE_RESULT=not_checked"
    echo "SYNC_ATTEMPTED=no"
    echo "SYNC_RESULT=NO_ACTION"
    echo "NUC2_ACCESSED=no"
    echo "REPORT_URL=none"
    echo "ERROR=discord_authorization_required" >&2
    exit 69
  fi
  if [[ ( "$MODE" == "sync-only" || "$MODE" == "both" ) && "$SYNC_AUTHORIZED" -ne 1 ]]; then
    echo "STATE=REFUSED_UNAUTHORIZED_MODE"
    echo "DISCORD_SENT=no"
    echo "NOTIFY_MODE=$MODE"
    echo "DEDUPE_RESULT=not_checked"
    echo "SYNC_ATTEMPTED=no"
    echo "SYNC_RESULT=NO_ACTION"
    echo "NUC2_ACCESSED=no"
    echo "REPORT_URL=none"
    echo "ERROR=sync_authorization_required" >&2
    exit 69
  fi
fi

if [[ ( "$MODE" == "sync-only" || "$MODE" == "both" ) && ${#SYNC_FILES[@]} -eq 0 ]]; then
  echo "STATE=REFUSED_INVALID_ALLOWLIST"
  echo "DISCORD_SENT=no"
  echo "NOTIFY_MODE=$MODE"
  echo "DEDUPE_RESULT=not_checked"
  echo "SYNC_ATTEMPTED=no"
  echo "SYNC_RESULT=REFUSED_INVALID_ALLOWLIST"
  echo "NUC2_ACCESSED=no"
  echo "REPORT_URL=none"
  echo "ERROR=sync_mode_requires_exact_--sync-file_allowlist" >&2
  exit 65
fi

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$SCRIPT_NAME] $*"; }
warn() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$SCRIPT_NAME] WARN: $*" >&2; }

redact_diagnostic() {
  sed -E \
    -e 's#(https://discord(app)?\.com/api/webhooks/)[^[:space:]]+#\1[REDACTED]#g' \
    -e 's#(password=)[^&[:space:]]+#\1[REDACTED]#gi' \
    -e 's#(token|secret|key)=([^[:space:]]+)#\1=[REDACTED]#gi'
}

refresh_proof_index() {
  local trace_store="${SEQUENCER_DIR}/trace-store.py"
  local refresh_log
  local refresh_rc=0
  local refresh_tail

  if [[ ! -f "$trace_store" ]]; then
    warn "PROOF_INDEX_REFRESH=skipped reason=trace_store_missing path=$trace_store"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    warn "PROOF_INDEX_REFRESH=skipped reason=python3_missing"
    return 0
  fi

  refresh_log="$(mktemp -t proof-index-refresh.XXXXXX.log)" || {
    warn "PROOF_INDEX_REFRESH=skipped reason=tempfile_unavailable"
    return 0
  }

  if python3 "$trace_store" >"$refresh_log" 2>&1; then
    log "PROOF_INDEX_REFRESH=ok output=$PROOF_INDEX_DEFAULT"
  else
    refresh_rc=$?
    refresh_tail="$(tail -5 "$refresh_log" 2>/dev/null | tr '\n' ' ' | redact_diagnostic || true)"
    warn "PROOF_INDEX_REFRESH=warn rc=$refresh_rc output=$PROOF_INDEX_DEFAULT error=${refresh_tail:-none}"
  fi

  rm -f "$refresh_log"
  return 0
}

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

REPORT_SLUG="$(printf '%s' "$PROOF_BASENAME" | tr -c 'a-zA-Z0-9.-' '_' | head -c 120)"
REPORT_BASENAME="report-proof-${REPORT_SLUG}.json"
ARCHIVE_PATH="${KB_SESSIONS_DIR}/${REPORT_BASENAME}"
PUBLIC_REPORT_URL="${HARNESS_REPORT_BASE_URL:-https://harness.slimyai.xyz}/reports/sessions/${REPORT_BASENAME}"

TMP_REPORT="$(mktemp -t session-report-from-proof.XXXXXX.json)"
python3 > "$TMP_REPORT" << PYEOF
import json, os
import re
import sys

sys.path.insert(0, "$SEQUENCER_DIR")
from proof_report_evidence import collect_report_evidence

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
report_url = "$PUBLIC_REPORT_URL"

def parse_result_fields(path):
    fields = {}
    if not os.path.isfile(path):
        return fields
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                if re.fullmatch(r"[A-Z0-9_]+", key):
                    fields[key] = value.strip()
    except OSError:
        return fields
    return fields

def classify_tests(path, status_value):
    fields = parse_result_fields(path)
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

    fail_markers = r"test fail|tests fail|lint fail|typecheck fail|build fail|validation fail"
    if re.search(fail_markers, normalized):
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

files_changed = []
for f in os.listdir(proof_dir):
    fp = os.path.join(proof_dir, f)
    if os.path.isfile(fp) and f not in ("RESULT.md", "harness-metadata.json", "harness-metadata.resolved.json"):
        files_changed.append(f)

evidence = collect_report_evidence(
    proof_dir,
    result_file,
    status,
    now,
    summary,
)
tests = evidence["tests"]

report = {
    "report_schema_version": "2",
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
    "result": evidence["result_fields"].get("RESULT", status),
    "summary": (summary or "Agent completed.")[:500],
    # Compatibility alias for the currently deployed renderer. The richer
    # artifacts object distinguishes proof totals from displayed names.
    "changes": evidence["artifacts"]["displayed_files"],
    "tests": tests,
    "validation_summary": evidence["validation_summary"],
    "artifacts": evidence["artifacts"],
    "blockers": [],
    "recommendation": {"next_feature_id": None, "reasoning": evidence["next_action"], "risk_notes": ""},
    "next_action": evidence["next_action"],
    "kb_learnings": [],
    "duration_minutes": evidence["duration"]["duration_minutes"],
    "duration_source": evidence["duration"]["duration_source"],
    "started_at": evidence["duration"]["started_at"],
    "completed_at": evidence["duration"]["completed_at"],
    "timestamp": now,
    "created_at": now,
    "archived_at": now,
    "proof_dir": proof_dir,
    "proof_basename": basename,
    "report_url": report_url,
    "discord_sent": False,
    "notify_mode": "runtime" if "$DRY_RUN" == "0" else "dry-run",
    "dedupe_result": "not_checked",
    "run_id": evidence["run_id"],
    "subject_id": evidence["subject_id"],
    "pushed": evidence["pushed"],
    "production_storage_state": evidence["production_storage_state"],
    "underlying_functional_qa": evidence["underlying_functional_qa"],
    "manual_qa_status": evidence["manual_qa_status"],
    "operator_qa": evidence["operator_qa"],
    "generated_by": "notify-proof-dir-complete.sh"
}

print(json.dumps(report, indent=2, ensure_ascii=False))
PYEOF

python3 -c "import json; json.load(open('$TMP_REPORT')); print('report valid')" || {
  echo "[$SCRIPT_NAME] ERROR: generated report is invalid JSON" >&2
  rm -f "$TMP_REPORT"
  exit 65
}

ACTION_REPORT_PATH="$ARCHIVE_PATH"
ARCHIVE_CREATED=0
if [[ "$DRY_RUN" -eq 1 ]]; then
  ACTION_REPORT_PATH="$TMP_REPORT"
  log "DRY-RUN: would archive session report to $ARCHIVE_PATH"
elif [[ -f "$ARCHIVE_PATH" ]]; then
  log "Archive already exists: $ARCHIVE_PATH (reusing for dedupe)"
else
  mkdir -p "$KB_SESSIONS_DIR"
  cp "$TMP_REPORT" "$ARCHIVE_PATH"
  ARCHIVE_CREATED=1
  log "Archived session report to $ARCHIVE_PATH"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  INDEX_OUTPUT="${HARNESS_SESSION_INDEX_OUTPUT:-${KB_SESSIONS_DIR}/harness-session-index.json}"
  EXPORTER="$SEQUENCER_DIR/export-session-index.sh"
  if [[ "$ARCHIVE_CREATED" -eq 0 && -f "$INDEX_OUTPUT" ]]; then
    log "Session index already covers reused archive: $INDEX_OUTPUT"
  elif [[ -f "$EXPORTER" ]]; then
    bash "$EXPORTER" --sessions-dir "$KB_SESSIONS_DIR" --output "$INDEX_OUTPUT" 2>&1 \
      || warn "Session index regeneration failed after archive (non-fatal)"
  else
    warn "Session index exporter not found at $EXPORTER"
  fi
fi

NOTIFIER="$SEQUENCER_DIR/notify-session-complete.sh"
SYNC_SCRIPT="$SEQUENCER_DIR/sync-session-reports-to-nuc2.sh"
if [[ "${HARNESS_NOTIFIER_TEST_MODE:-0}" == "1" ]]; then
  NOTIFIER="${HARNESS_NOTIFY_SESSION_SCRIPT:-$NOTIFIER}"
  SYNC_SCRIPT="${HARNESS_SYNC_SESSION_SCRIPT:-$SYNC_SCRIPT}"
fi
DISCORD_SELECTED=0
SYNC_SELECTED=0
[[ "$MODE" == "discord-only" || "$MODE" == "both" ]] && DISCORD_SELECTED=1
[[ "$MODE" == "sync-only" || "$MODE" == "both" ]] && SYNC_SELECTED=1

discord_dedupe_status() {
  local report="$1"
  local state_dir="${HARNESS_NOTIFY_STATE_DIR:-/home/slimy/harness-logs/notify-state}"
  if [[ ! -f "$report" ]]; then
    echo "not_checked"
    return
  fi
  local abspath mtime size key
  abspath="$(readlink -f -- "$report" 2>/dev/null || true)"
  mtime="$(stat -c '%Y' -- "$report" 2>/dev/null || echo 0)"
  size="$(stat -c '%s' -- "$report" 2>/dev/null || echo 0)"
  key="$(printf '%s|%s|%s' "$abspath" "$mtime" "$size" | sha256sum | awk '{print $1}')"
  if [[ -f "$state_dir/$key.sent" ]]; then
    echo "present"
  else
    echo "absent"
  fi
}

DISCORD_DEDUPE_STATUS="not_applicable"
[[ "$DISCORD_SELECTED" -eq 1 ]] && DISCORD_DEDUPE_STATUS="$(discord_dedupe_status "$ACTION_REPORT_PATH")"
EXTERNAL_COUNT=0
[[ "$DISCORD_SELECTED" -eq 1 ]] && EXTERNAL_COUNT=$((EXTERNAL_COUNT + 1))
[[ "$SYNC_SELECTED" -eq 1 ]] && EXTERNAL_COUNT=$((EXTERNAL_COUNT + 1))

echo "STATE=PREFLIGHT_OK"
echo "NOTIFY_MODE=$MODE"
echo "DISCORD_AUTHORIZED=$([[ $DISCORD_AUTHORIZED -eq 1 ]] && echo yes || echo no)"
echo "SYNC_AUTHORIZED=$([[ $SYNC_AUTHORIZED -eq 1 ]] && echo yes || echo no)"
echo "REPORT_PATH=$(basename "$ARCHIVE_PATH")"
echo "REPORT_URL=$PUBLIC_REPORT_URL"
echo "DISCORD_DEDUPE_STATUS=$DISCORD_DEDUPE_STATUS"
echo "DISCORD_COMMAND=$([[ $DISCORD_SELECTED -eq 1 ]] && echo 'notify-session-complete.sh [redacted-webhook] [exact-report]' || echo none)"
echo "SYNC_COMMAND=$([[ $SYNC_SELECTED -eq 1 ]] && echo 'sync-session-reports-to-nuc2.sh [exact-allowlist] [fixed-destination]' || echo none)"
echo "EXTERNAL_SIDE_EFFECT_COUNT=$EXTERNAL_COUNT"

SYNC_PREFLIGHT=""
if [[ "$SYNC_SELECTED" -eq 1 ]]; then
  [[ -f "$SYNC_SCRIPT" ]] || { echo "STATE=SYNC_FAILED"; echo "ERROR=sync_helper_missing" >&2; rm -f "$TMP_REPORT"; exit 71; }
  SYNC_PREFLIGHT_ARGS=(--dry-run)
  for sync_file in "${SYNC_FILES[@]}"; do
    SYNC_PREFLIGHT_ARGS+=(--file "$sync_file")
  done
  if ! SYNC_PREFLIGHT="$(bash "$SYNC_SCRIPT" "${SYNC_PREFLIGHT_ARGS[@]}" 2>&1)"; then
    printf '%s\n' "$SYNC_PREFLIGHT"
    echo "DISCORD_SENT=no"
    echo "DEDUPE_RESULT=not_checked"
    echo "SYNC_ATTEMPTED=no"
    echo "SYNC_RESULT=REFUSED_INVALID_ALLOWLIST"
    echo "NUC2_ACCESSED=no"
    rm -f "$TMP_REPORT"
    exit 65
  fi
  printf '%s\n' "$SYNC_PREFLIGHT"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "STATE=PREFLIGHT_OK"
  echo "DISCORD_SENT=no"
  echo "DEDUPE_RESULT=not_checked"
  echo "SYNC_ATTEMPTED=no"
  echo "SYNC_RESULT=$([[ $SYNC_SELECTED -eq 1 ]] && echo PREFLIGHT_OK || echo NO_ACTION)"
  echo "NUC2_ACCESSED=no"
  echo "REPORT_URL=$PUBLIC_REPORT_URL"
  rm -f "$TMP_REPORT"
  exit 0
fi

if [[ "${HARNESS_DISABLE_PROOF_INDEX_REFRESH:-0}" != "1" ]]; then
  refresh_proof_index
fi

DISCORD_RC=0
DISCORD_RESULT="NO_ACTION"
DISCORD_SENT_VALUE="no"
DEDUPE_RESULT_VALUE="not_checked"
if [[ "$DISCORD_SELECTED" -eq 1 ]]; then
  if [[ ! -f "$NOTIFIER" ]]; then
    DISCORD_RC=70
    DISCORD_RESULT="DISCORD_FAILED"
  else
    DISCORD_ARGS=(--require-webhook)
    [[ "$FORCE" -eq 1 ]] && DISCORD_ARGS+=(--force)
    DISCORD_OUTPUT=""
    if DISCORD_OUTPUT="$(bash "$NOTIFIER" "${DISCORD_ARGS[@]}" "$ARCHIVE_PATH" 2>&1)"; then
      DISCORD_RC=0
      if grep -q 'already_notified' <<<"$DISCORD_OUTPUT" || [[ "$DISCORD_DEDUPE_STATUS" == "present" ]]; then
        DISCORD_RESULT="DISCORD_DEDUPED"
        DEDUPE_RESULT_VALUE="skipped"
      else
        DISCORD_RESULT="DISCORD_SENT"
        DISCORD_SENT_VALUE="yes"
        DEDUPE_RESULT_VALUE="sent"
      fi
    else
      DISCORD_RC=$?
      DISCORD_RESULT="DISCORD_FAILED"
      DEDUPE_RESULT_VALUE="not_checked"
    fi
    printf '%s\n' "$DISCORD_OUTPUT"
  fi
fi

SYNC_RC=0
SYNC_RESULT_VALUE="NO_ACTION"
SYNC_ATTEMPTED_VALUE="no"
NUC2_ACCESSED_VALUE="no"
if [[ "$SYNC_SELECTED" -eq 1 ]]; then
  SYNC_ARGS=(--sync-authorized)
  [[ "$FORCE_SYNC" -eq 1 ]] && SYNC_ARGS+=(--force-sync)
  for sync_file in "${SYNC_FILES[@]}"; do
    SYNC_ARGS+=(--file "$sync_file")
  done
  SYNC_OUTPUT=""
  if SYNC_OUTPUT="$(bash "$SYNC_SCRIPT" "${SYNC_ARGS[@]}" 2>&1)"; then
    SYNC_RC=0
  else
    SYNC_RC=$?
  fi
  printf '%s\n' "$SYNC_OUTPUT"
  SYNC_RESULT_VALUE="$(awk -F= '/^SYNC_RESULT=/{v=$2} END{print v}' <<<"$SYNC_OUTPUT")"
  SYNC_ATTEMPTED_VALUE="$(awk -F= '/^SYNC_ATTEMPTED=/{v=$2} END{print v}' <<<"$SYNC_OUTPUT")"
  NUC2_ACCESSED_VALUE="$(awk -F= '/^NUC2_ACCESSED=/{v=$2} END{print v}' <<<"$SYNC_OUTPUT")"
  [[ -n "$SYNC_RESULT_VALUE" ]] || SYNC_RESULT_VALUE="SYNC_FAILED"
  [[ -n "$SYNC_ATTEMPTED_VALUE" ]] || SYNC_ATTEMPTED_VALUE="no"
  [[ -n "$NUC2_ACCESSED_VALUE" ]] || NUC2_ACCESSED_VALUE="no"
fi

FINAL_STATE="NO_ACTION"
FINAL_RC=0
if [[ "$MODE" == "discord-only" ]]; then
  FINAL_STATE="$DISCORD_RESULT"
  [[ "$DISCORD_RC" -eq 0 ]] || FINAL_RC=70
elif [[ "$MODE" == "sync-only" ]]; then
  FINAL_STATE="$SYNC_RESULT_VALUE"
  [[ "$SYNC_RC" -eq 0 ]] || FINAL_RC=71
else
  if [[ "$DISCORD_RC" -eq 0 && "$SYNC_RC" -eq 0 ]]; then
    if [[ "$DISCORD_RESULT" == "DISCORD_DEDUPED" && "$SYNC_RESULT_VALUE" == "SYNC_DEDUPED" ]]; then
      FINAL_STATE="SYNC_DEDUPED"
    else
      FINAL_STATE="SYNC_COMPLETE"
    fi
  elif [[ "$DISCORD_RC" -eq 0 && "$SYNC_RC" -ne 0 ]]; then
    FINAL_STATE="DISCORD_OK_SYNC_FAILED"
    FINAL_RC=72
  elif [[ "$DISCORD_RC" -ne 0 && "$SYNC_RC" -eq 0 ]]; then
    FINAL_STATE="SYNC_OK_DISCORD_FAILED"
    FINAL_RC=72
  else
    FINAL_STATE="DISCORD_FAILED"
    FINAL_RC=72
  fi
fi

echo "STATE=$FINAL_STATE"
echo "DISCORD_SENT=$DISCORD_SENT_VALUE"
echo "DISCORD_RESULT=$DISCORD_RESULT"
echo "NOTIFY_MODE=$MODE"
echo "DEDUPE_RESULT=$DEDUPE_RESULT_VALUE"
echo "SYNC_ATTEMPTED=$SYNC_ATTEMPTED_VALUE"
echo "SYNC_RESULT=$SYNC_RESULT_VALUE"
echo "NUC2_ACCESSED=$NUC2_ACCESSED_VALUE"
echo "REPORT_URL=$PUBLIC_REPORT_URL"

rm -f "$TMP_REPORT"
exit "$FINAL_RC"
