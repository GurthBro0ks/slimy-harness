#!/usr/bin/env bash
# Sync an exact, validated allowlist of session-report JSON files to the fixed
# NUC2 report directory. This helper never discovers files or reads Discord
# configuration.
set -euo pipefail

SCRIPT_NAME="sync-session-reports"
DEFAULT_LOCAL_ROOT="/home/slimy/slimy-kb/raw/sessions"
DEFAULT_REMOTE_HOST="nuc2"
DEFAULT_REMOTE_ROOT="/home/slimy/slimy-kb/raw/sessions"
DEFAULT_STATE_DIR="/home/slimy/harness-logs/notify-state"
MAX_FILES=8

AUTHORIZED=0
DRY_RUN=0
FORCE_SYNC=0
FILES=()

REMOTE_HOST="$DEFAULT_REMOTE_HOST"
REMOTE_ROOT="$DEFAULT_REMOTE_ROOT"
if [[ "${HARNESS_NOTIFIER_TEST_MODE:-0}" == "1" ]]; then
  LOCAL_ROOT="${HARNESS_SYNC_LOCAL_ROOT:-$DEFAULT_LOCAL_ROOT}"
  STATE_DIR="${HARNESS_SYNC_STATE_DIR:-$DEFAULT_STATE_DIR}"
  STUB_ROOT="$(realpath -e -- "${HARNESS_NOTIFIER_STUB_ROOT:-/nonexistent}" 2>/dev/null || true)"
  SSH_COMMAND="$(command -v ssh 2>/dev/null || true)"
  RSYNC_COMMAND="$(command -v rsync 2>/dev/null || true)"
  if [[ -z "$STUB_ROOT" || "$SSH_COMMAND" != "$STUB_ROOT/"* || "$RSYNC_COMMAND" != "$STUB_ROOT/"* ]]; then
    echo "STATE=REFUSED_UNAUTHORIZED_MODE"
    echo "ERROR=test_mode_requires_path_stubs" >&2
    exit 69
  fi
else
  LOCAL_ROOT="$DEFAULT_LOCAL_ROOT"
  STATE_DIR="$DEFAULT_STATE_DIR"
fi

usage() {
  cat <<USAGE
$SCRIPT_NAME — exact-file report synchronization to NUC2

Usage:
  $SCRIPT_NAME --sync-authorized --file PATH [--file PATH ...]
               [--dry-run] [--force-sync]

Options:
  --sync-authorized  Required for a real sync.
  --file PATH        Exact JSON file to sync; repeat for each file.
  --dry-run          Validate and print redacted preflight; no ssh/rsync/marker.
  --force-sync       Bypass only the sync dedupe marker.
  --help             Show this help.

Files must be regular, non-symlink JSON files directly under:
  $LOCAL_ROOT

The destination is fixed and cannot be supplied by the caller:
  $REMOTE_HOST:$REMOTE_ROOT/

Exit codes: 0 complete/deduped/preflight, 64 usage, 65 invalid allowlist,
69 unauthorized, 71 ssh/rsync failure.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sync-authorized)
      AUTHORIZED=1
      shift
      ;;
    --file)
      [[ $# -ge 2 ]] || { echo "STATE=REFUSED_INVALID_ALLOWLIST"; echo "ERROR=--file_requires_path" >&2; exit 65; }
      FILES+=("$2")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force-sync)
      FORCE_SYNC=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "STATE=REFUSED_INVALID_ALLOWLIST"
      echo "ERROR=unknown_argument:$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

refuse_allowlist() {
  echo "STATE=REFUSED_INVALID_ALLOWLIST"
  echo "SYNC_ATTEMPTED=no"
  echo "SYNC_RESULT=REFUSED_INVALID_ALLOWLIST"
  echo "NUC2_ACCESSED=no"
  echo "ERROR=$1" >&2
  exit 65
}

[[ ${#FILES[@]} -gt 0 ]] || refuse_allowlist "empty_allowlist"
[[ ${#FILES[@]} -le $MAX_FILES ]] || refuse_allowlist "allowlist_exceeds_${MAX_FILES}_files"

LOCAL_ROOT_REAL="$(realpath -e -- "$LOCAL_ROOT" 2>/dev/null)" \
  || refuse_allowlist "approved_local_root_missing"
[[ -d "$LOCAL_ROOT_REAL" ]] || refuse_allowlist "approved_local_root_not_directory"

VALIDATED=()
BASENAMES=()
HASHES=()
declare -A SEEN_PATHS=()
declare -A SEEN_BASENAMES=()

for candidate in "${FILES[@]}"; do
  [[ "$candidate" != *'*'* && "$candidate" != *'?'* && "$candidate" != *'['* && "$candidate" != *']'* ]] \
    || refuse_allowlist "wildcard_or_glob_rejected"
  [[ -e "$candidate" ]] || refuse_allowlist "missing_file"
  [[ ! -L "$candidate" ]] || refuse_allowlist "symlink_rejected"
  [[ -f "$candidate" ]] || refuse_allowlist "non_regular_file_rejected"
  [[ "$candidate" == *.json ]] || refuse_allowlist "non_json_file_rejected"

  canonical="$(realpath -e -- "$candidate" 2>/dev/null)" || refuse_allowlist "realpath_failed"
  [[ "$(dirname "$canonical")" == "$LOCAL_ROOT_REAL" ]] || refuse_allowlist "outside_approved_root"
  [[ -z "${SEEN_PATHS[$canonical]:-}" ]] || refuse_allowlist "duplicate_file"

  basename_value="$(basename "$canonical")"
  [[ -z "${SEEN_BASENAMES[$basename_value]:-}" ]] || refuse_allowlist "duplicate_destination_basename"
  python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$canonical" 2>/dev/null \
    || refuse_allowlist "invalid_json_file"

  digest="$(sha256sum -- "$canonical" | awk '{print $1}')"
  SEEN_PATHS[$canonical]=1
  SEEN_BASENAMES[$basename_value]=1
  VALIDATED+=("$canonical")
  BASENAMES+=("$basename_value")
  HASHES+=("$digest")
done

DEDUPE_KEY="$({
  printf 'destination=%s:%s\n' "$REMOTE_HOST" "$REMOTE_ROOT"
  for i in "${!VALIDATED[@]}"; do
    printf '%s|%s\n' "${VALIDATED[$i]}" "${HASHES[$i]}"
  done
} | sha256sum | awk '{print $1}')"
SYNC_MARKER="$STATE_DIR/${DEDUPE_KEY}.sync-sent"
DEDUPE_STATUS="absent"
[[ -f "$SYNC_MARKER" ]] && DEDUPE_STATUS="present"

printf 'STATE=PREFLIGHT_OK\n'
printf 'SYNC_AUTHORIZED=%s\n' "$([[ $AUTHORIZED -eq 1 ]] && echo yes || echo no)"
printf 'SYNC_ALLOWLIST_COUNT=%s\n' "${#VALIDATED[@]}"
for i in "${!VALIDATED[@]}"; do
  printf 'SYNC_FILE_%s=%s sha256=%s\n' "$((i + 1))" "${BASENAMES[$i]}" "${HASHES[$i]}"
done
printf 'SYNC_DESTINATION=%s:%s/\n' "$REMOTE_HOST" "$REMOTE_ROOT"
printf 'SYNC_DEDUPE_STATUS=%s\n' "$DEDUPE_STATUS"
printf 'SYNC_COMMAND=ssh [fixed-host] mkdir-fixed-destination; rsync [exact-files] [fixed-destination]\n'
printf 'SYNC_EXTERNAL_SIDE_EFFECT_COUNT=1\n'

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "SYNC_ATTEMPTED=no"
  echo "SYNC_RESULT=PREFLIGHT_OK"
  echo "NUC2_ACCESSED=no"
  exit 0
fi

if [[ "$AUTHORIZED" -ne 1 ]]; then
  echo "STATE=REFUSED_UNAUTHORIZED_MODE"
  echo "SYNC_ATTEMPTED=no"
  echo "SYNC_RESULT=REFUSED_UNAUTHORIZED_MODE"
  echo "NUC2_ACCESSED=no"
  exit 69
fi

if [[ "$FORCE_SYNC" -ne 1 && -f "$SYNC_MARKER" ]]; then
  echo "STATE=SYNC_DEDUPED"
  echo "SYNC_ATTEMPTED=no"
  echo "SYNC_RESULT=SYNC_DEDUPED"
  echo "NUC2_ACCESSED=no"
  exit 0
fi

if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST" "mkdir -p '$REMOTE_ROOT'" >/dev/null 2>&1; then
  echo "STATE=SYNC_FAILED"
  echo "SYNC_ATTEMPTED=yes"
  echo "SYNC_RESULT=SYNC_FAILED_SSH"
  echo "NUC2_ACCESSED=no"
  exit 71
fi

if ! rsync -t --protect-args -- "${VALIDATED[@]}" "$REMOTE_HOST:$REMOTE_ROOT/" >/dev/null 2>&1; then
  echo "STATE=SYNC_FAILED"
  echo "SYNC_ATTEMPTED=yes"
  echo "SYNC_RESULT=SYNC_FAILED_RSYNC"
  echo "NUC2_ACCESSED=yes"
  exit 71
fi

mkdir -p "$STATE_DIR"
{
  printf 'timestamp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'destination=%s:%s/\n' "$REMOTE_HOST" "$REMOTE_ROOT"
  for i in "${!BASENAMES[@]}"; do
    printf 'file=%s sha256=%s\n' "${BASENAMES[$i]}" "${HASHES[$i]}"
  done
} > "$SYNC_MARKER"
chmod 0600 "$SYNC_MARKER" 2>/dev/null || true

echo "STATE=SYNC_COMPLETE"
echo "SYNC_ATTEMPTED=yes"
echo "SYNC_RESULT=SYNC_COMPLETE"
echo "NUC2_ACCESSED=yes"
