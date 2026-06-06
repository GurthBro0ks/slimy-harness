#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/notifications/registry.json"

log() { echo "[notify-dry-run] $*"; }

FAKE_REPO="slimy-harness"
FAKE_TASK="example-task-slug"
FAKE_COMMIT="abcd1234"
FAKE_RESULT="PASS"
FAKE_PROOF_DIR="/tmp/proof_example_task_20260606T120000Z"
FAKE_SESSION_REPORT="report-proof-example-task-slug.json"
FAKE_SOURCE_NUC="nuc1"
FAKE_HOSTNAME="slimy-nuc1"
FAKE_MENTION_ID="427999592986968074"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)       FAKE_REPO="${2:-}";       shift 2 ;;
    --task)       FAKE_TASK="${2:-}";       shift 2 ;;
    --commit)     FAKE_COMMIT="${2:-}";     shift 2 ;;
    --result)     FAKE_RESULT="${2:-}";     shift 2 ;;
    --proof-dir)  FAKE_PROOF_DIR="${2:-}";  shift 2 ;;
    --source-nuc) FAKE_SOURCE_NUC="${2:-}"; shift 2 ;;
    --help|-h)
      cat <<'USG'
notify-dry-run.sh — preview a Discord notification without sending

Usage:
  ops/harness-ops notify dry-run [options]

Options:
  --repo REPO         Repository name (default: slimy-harness)
  --task TASK         Task title/slug
  --commit HASH       Commit hash
  --result RESULT     PASS/WARN/FAIL
  --proof-dir PATH    Proof directory path
  --source-nuc NUC    Source NUC (nuc1/nuc2)

Behavior:
  - renders a safe preview of a readable Discord-style message
  - does NOT send anything
  - does NOT call curl to Discord
  - uses fake example data unless arguments are provided
USG
      exit 0 ;;
    *) echo "[notify-dry-run] ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$REGISTRY" ]]; then
  echo "[notify-dry-run] ERROR: registry.json not found" >&2
  exit 1
fi

report_base="$(jq -r '.report_url_base' "$REGISTRY")"
session_pattern="$(jq -r '.session_report_url_pattern' "$REGISTRY")"
mention_id="$(jq -r '.mention_target_id' "$REGISTRY")"

report_url="${session_pattern//<filename>/$FAKE_SESSION_REPORT}"

mention_render=""
if [[ -n "$mention_id" && "$mention_id" != "null" ]]; then
  mention_render="<@\${mention_target_id}> (mention suppressed in dry-run)"
fi

log "╔══════════════════════════════════════════════════════╗"
log "║          DRY RUN — NO DISCORD MESSAGE SENT          ║"
log "╚══════════════════════════════════════════════════════╝"
log ""
log "--- Discord Embed Preview ---"
log ""
log "  Title:   Harness Session Complete"
log "  Result:  $FAKE_RESULT"
log "  Repo:    $FAKE_REPO"
log "  Commit:  $FAKE_COMMIT"
log "  Task:    $FAKE_TASK"
log "  NUC:     $FAKE_SOURCE_NUC"
log "  Host:    $FAKE_HOSTNAME"
log "  Proof:   $FAKE_PROOF_DIR"
log "  Report:  $report_url"
log "  Mention: $mention_render"
log ""
log "--- Report URL ---"
log "  $report_url"
log ""
log "--- Markdown Body ---"
log ""
log "  **$FAKE_RESULT** — $FAKE_TASK"
log "  Repo: \`$FAKE_REPO\` | Commit: \`$FAKE_COMMIT\`"
log "  Source: $FAKE_SOURCE_NUC / $FAKE_HOSTNAME"
log "  [Full Report]($report_url)"
log ""
log "╔══════════════════════════════════════════════════════╗"
log "║          DRY RUN — NO DISCORD MESSAGE SENT          ║"
log "╚══════════════════════════════════════════════════════╝"

exit 0
