#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT_DIR/ops/notifications/registry.json"
STATE_DIR="${HARNESS_NOTIFY_STATE_DIR:-/home/slimy/harness-logs/notify-state}"

log()  { echo "[dedupe-check] $*"; }
warn() { echo "[dedupe-check] WARN: $*"; }

if [[ $# -lt 1 ]]; then
  cat <<'USG'
dedupe-check.sh — check dedupe marker status

Usage:
  ops/harness-ops notify dedupe-check <proof_dir_or_session_id>

Behavior:
  - checks expected dedupe marker locations for a given proof dir or session ID
  - accepts proof dir path or session report filename
  - reports whether .sent, .relay-sent, .relay-failed markers exist
  - does NOT create or delete markers
  - does NOT trigger notification sends
  - read-only inspection only
USG
  exit 2
fi

INPUT="$1"

if [[ ! -f "$REGISTRY" ]]; then
  echo "[dedupe-check] ERROR: registry.json not found" >&2
  exit 1
fi

log "input: $INPUT"
log "state_dir: $STATE_DIR"

if [[ ! -d "$STATE_DIR" ]]; then
  warn "marker state dir does not exist: $STATE_DIR"
  log "RESULT=WARN no markers found (state dir missing)"
  exit 0
fi

total_markers=0

log ""
log "=== Checking .sent markers (NUC1 send dedupe) ==="
sent_markers=()
while IFS= read -r marker; do
  [[ -z "$marker" ]] && continue
  sent_markers+=("$marker")
done < <(find "$STATE_DIR" -maxdepth 1 -name '*.sent' -type f 2>/dev/null | sort)

if [[ ${#sent_markers[@]} -eq 0 ]]; then
  log "  no .sent markers found"
else
  log "  found ${#sent_markers[@]} .sent marker(s):"
  for m in "${sent_markers[@]}"; do
    key="$(basename "$m" .sent)"
    ts=""
    if grep -q 'timestamp' "$m" 2>/dev/null; then
      ts="$(grep 'timestamp' "$m" 2>/dev/null | head -1 | sed 's/.*timestamp[=: ]*//' | tr -d '"' | tr -d ',')"
    fi
    log "    $key (ts: ${ts:-unknown})"
    total_markers=$((total_markers + 1))
  done
fi

log ""
log "=== Checking .relay-sent markers (NUC2 relay dedupe) ==="
relay_sent=()
while IFS= read -r marker; do
  [[ -z "$marker" ]] && continue
  relay_sent+=("$marker")
done < <(find "$STATE_DIR" -maxdepth 1 -name '*.relay-sent' -type f 2>/dev/null | sort)

if [[ ${#relay_sent[@]} -eq 0 ]]; then
  log "  no .relay-sent markers found"
else
  log "  found ${#relay_sent[@]} .relay-sent marker(s):"
  for m in "${relay_sent[@]}"; do
    key="$(basename "$m" .relay-sent)"
    log "    $key"
    total_markers=$((total_markers + 1))
  done
fi

log ""
log "=== Checking .relay-failed markers ==="
relay_failed=()
while IFS= read -r marker; do
  [[ -z "$marker" ]] && continue
  relay_failed+=("$marker")
done < <(find "$STATE_DIR" -maxdepth 1 -name '*.relay-failed' -type f 2>/dev/null | sort)

if [[ ${#relay_failed[@]} -eq 0 ]]; then
  log "  no .relay-failed markers found"
else
  log "  found ${#relay_failed[@]} .relay-failed marker(s):"
  for m in "${relay_failed[@]}"; do
    key="$(basename "$m" .relay-failed)"
    log "    $key"
    total_markers=$((total_markers + 1))
  done
fi

log ""
log "=== Input Match Check ==="
input_match=0

if [[ -d "$INPUT" ]]; then
  input_basename="$(basename "$INPUT")"
  log "input interpreted as proof dir: $INPUT"
  log "looking for markers matching: $input_basename"
  for m in "${sent_markers[@]}" "${relay_sent[@]}" "${relay_failed[@]}"; do
    key="$(basename "$m" | sed 's/\.\(sent\|relay-sent\|relay-failed\)$//')"
    if echo "$key" | grep -qi "$input_basename" || echo "$input_basename" | grep -qi "$key"; then
      log "  MATCH: $(basename "$m")"
      input_match=$((input_match + 1))
    fi
  done
  if [[ $input_match -eq 0 ]]; then
    log "  no markers match input proof dir basename"
  fi
elif [[ -f "$INPUT" ]]; then
  input_basename="$(basename "$INPUT")"
  log "input interpreted as file: $INPUT"
  log "looking for markers referencing: $input_basename"
  for m in "${sent_markers[@]}" "${relay_sent[@]}" "${relay_failed[@]}"; do
    if grep -q "$input_basename" "$m" 2>/dev/null; then
      log "  MATCH: $(basename "$m") references $input_basename"
      input_match=$((input_match + 1))
    fi
  done
  if [[ $input_match -eq 0 ]]; then
    log "  no markers reference this input"
  fi
else
  log "input does not exist as file or dir; checking for substring matches"
  for m in "${sent_markers[@]}" "${relay_sent[@]}" "${relay_failed[@]}"; do
    key="$(basename "$m" | sed 's/\(sent\|relay-sent\|relay-failed\)$//')"
    if echo "$key" | grep -qi "$INPUT" 2>/dev/null; then
      log "  MATCH: $(basename "$m")"
      input_match=$((input_match + 1))
    fi
  done
  if [[ $input_match -eq 0 ]]; then
    log "  no markers match input substring"
  fi
fi

log ""
log "RESULT=OK total_markers=$total_markers input_matches=$input_match"
exit 0
