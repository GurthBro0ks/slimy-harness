#!/usr/bin/env bash
# notify-proof-dir-complete.sh — send a Discord completion notification from a
# proof directory when no session-report.json exists.
#
# Direct-task agents (SLIMY HARNESS DIRECT TASK) produce proof dirs with
# RESULT.md but no session-report.json. This adapter bridges the gap by
# creating a minimal session report from the proof dir, archiving it to
# the KB, and calling notify-session-complete.sh.
#
# Usage:
#   notify-proof-dir-complete.sh [--dry-run] [--force] [--require-webhook] <proof_dir>
#   notify-proof-dir-complete.sh --help
#
# Flags are forwarded to notify-session-complete.sh.
set -euo pipefail

SCRIPT_NAME="notify-proof-dir"
HARNESS_ROOT="${HARNESS_ROOT:-/home/slimy/slimy-harness}"
SEQUNCER_DIR="${HARNESS_ROOT}/sequencer"
KB_SESSIONS_DIR="${HARNESS_KB_SESSIONS:-/home/slimy/slimy-kb/raw/sessions}"
SESSION_REPORT_DEFAULT="/home/slimy/session-report.json"

DRY_RUN=0
FORCE=0
REQUIRE_WEBHOOK=0
FORWARD_FLAGS=()
PROOF_DIR=""

usage() {
  cat <<USG
$SCRIPT_NAME — Discord completion notification from a proof directory

Usage:
  $SCRIPT_NAME [--dry-run] [--force] [--require-webhook] <proof_dir>
  $SCRIPT_NAME --help

Description:
  Creates a minimal session-report.json from the proof directory's
  RESULT.md (and claude-progress.md if available), archives it to
  the KB sessions directory, and calls notify-session-complete.sh.

  Flags are forwarded to notify-session-complete.sh.
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

if [[ ! -f "$RESULT_FILE" ]]; then
  warn "RESULT.md not found in $PROOF_DIR; creating minimal report from directory name"
fi

NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PROOF_BASENAME="$(basename "$PROOF_DIR")"

FEATURE_ID=""
STATUS="completed"
VERDICT="PASS"
SUMMARY="Agent completed. Proof: $PROOF_DIR"

if [[ -f "$RESULT_FILE" ]]; then
  VERDICT="$(grep -iE '^\*\*PASS\*\*|^## Verdict|^Verdict:|^PASS' "$RESULT_FILE" | head -1 || true)"
  if echo "$VERDICT" | grep -qiE 'FAIL|WARN'; then
    STATUS="partial"
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

AGENT="opencode"
NUC="nuc1"
PROJECT=""

for candidate in /home/slimy/AGENTS.md /home/slimy/QUALITY_CRITERIA.md; do
  if grep -q "NUC1" "$candidate" 2>/dev/null; then
    NUC="nuc1"
    break
  fi
done

TMP_REPORT="$(mktemp -t session-report-from-proof.XXXXXX.json)"
python3 > "$TMP_REPORT" << PYEOF
import json, os

proof_dir = "$PROOF_DIR"
result_file = "$RESULT_FILE"
feature_id = "$FEATURE_ID"
status = "$STATUS"
summary = "$SUMMARY"
agent = "$AGENT"
nuc = "$NUC"
now = "$NOW_ISO"
basename = "$PROOF_BASENAME"

files_changed = []
for f in os.listdir(proof_dir):
    fp = os.path.join(proof_dir, f)
    if os.path.isfile(fp) and f not in ("RESULT.md",):
        files_changed.append(f)

report = {
    "session_id": now,
    "agent": agent,
    "nuc": nuc,
    "project": "",
    "feature_id": feature_id or "unknown",
    "prompt_type": "direct",
    "status": status,
    "summary": (summary or "Agent completed.")[:500],
    "changes": files_changed[:20],
    "tests": {"ran": True, "passed": status == "completed", "details": "Proof dir adapter: status inferred from RESULT.md"},
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

if [[ "$DRY_RUN" -eq 0 ]]; then
  SYNC_SCRIPT="$SEQUNCER_DIR/sync-session-reports-to-nuc2.sh"
  if [[ -f "$SYNC_SCRIPT" ]]; then
    bash "$SYNC_SCRIPT" 2>&1 || warn "Session report sync to NUC2 failed (non-fatal)"
  fi
fi

NOTIFIER="$SEQUNCER_DIR/notify-session-complete.sh"
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
