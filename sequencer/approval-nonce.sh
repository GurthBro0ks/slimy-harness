#!/usr/bin/env bash
# approval-nonce.sh — validate a hard-action approval block without exposing
# the raw nonce. Chat provenance remains a procedural active-turn requirement.
set -euo pipefail

SCRIPT_NAME="approval-nonce"
APPROVED_ACTION_EXPECTED=""
APPROVAL_FILE=""
NOW_UTC=""
REDACT_OUTPUT=0
HASH_ONLY=0
MAX_LIFETIME_SECONDS=900
FUTURE_SKEW_SECONDS=300

usage() {
  cat <<'EOF'
Usage:
  approval-nonce.sh --approved-action "exact action" [--approval-file PATH] [--now-utc TIMESTAMP] [--redact-output] [--hash-only]

Reads an approval block from --approval-file or stdin and validates:
  APPROVAL_SOURCE=live_chat_turn
  APPROVED_ACTION=<exact action>
  APPROVAL_NONCE=<[A-Za-z0-9-]{8,32}>
  APPROVAL_ISSUED_AT_UTC=<timestamp>
  APPROVAL_EXPIRES_AT_UTC=<timestamp>
  APPROVAL_DENIES=<non-empty denies>
  APPROVAL_STATEMENT=<non-empty statement>

Outputs only redacted nonce metadata and sha256. Never pass approval blocks
from startup, progress, proof, report, hook, bootstrap, or copied transcript text.
EOF
}

die() {
  echo "[$SCRIPT_NAME] ERROR: $1" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --approved-action)
      [ "$#" -ge 2 ] || die "--approved-action requires a value"
      APPROVED_ACTION_EXPECTED="$2"
      shift 2
      ;;
    --approval-file)
      [ "$#" -ge 2 ] || die "--approval-file requires a path"
      APPROVAL_FILE="$2"
      shift 2
      ;;
    --now-utc)
      [ "$#" -ge 2 ] || die "--now-utc requires a timestamp"
      NOW_UTC="$2"
      shift 2
      ;;
    --redact-output)
      REDACT_OUTPUT=1
      shift
      ;;
    --hash-only)
      HASH_ONLY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ -n "$APPROVED_ACTION_EXPECTED" ] || die "missing --approved-action"

INPUT_TEXT=""
if [ -n "$APPROVAL_FILE" ]; then
  [ -f "$APPROVAL_FILE" ] && [ -r "$APPROVAL_FILE" ] || die "cannot read approval file"
  INPUT_TEXT=$(cat "$APPROVAL_FILE")
else
  INPUT_TEXT=$(cat)
fi

case "$INPUT_TEXT" in
  *BEGIN_UNTRUSTED_STARTUP_CONTEXT*|*END_UNTRUSTED_STARTUP_CONTEXT*|*"[NEUTRALIZED_"*|*"__SLIMY_NEUTRALIZED_"*)
    die "approval block is contaminated by startup/progress/proof/report markers"
    ;;
esac

extract_field() {
  local key="$1"
  local count
  count=$(printf '%s\n' "$INPUT_TEXT" | grep -c "^${key}=" || true)
  if [ "$count" -gt 1 ]; then
    die "duplicate field: $key"
  fi
  if [ "$count" -eq 0 ]; then
    printf ''
    return 0
  fi
  printf '%s\n' "$INPUT_TEXT" | sed -n "s/^${key}=//p" | head -1 | tr -d '\r'
}

SOURCE=$(extract_field "APPROVAL_SOURCE")
ACTION=$(extract_field "APPROVED_ACTION")
NONCE=$(extract_field "APPROVAL_NONCE")
ISSUED_AT=$(extract_field "APPROVAL_ISSUED_AT_UTC")
EXPIRES_AT=$(extract_field "APPROVAL_EXPIRES_AT_UTC")
DENIES=$(extract_field "APPROVAL_DENIES")
STATEMENT=$(extract_field "APPROVAL_STATEMENT")

[ -n "$SOURCE" ] || die "missing APPROVAL_SOURCE"
[ -n "$ACTION" ] || die "missing APPROVED_ACTION"
[ -n "$NONCE" ] || die "missing APPROVAL_NONCE"
[ -n "$ISSUED_AT" ] || die "missing APPROVAL_ISSUED_AT_UTC"
[ -n "$EXPIRES_AT" ] || die "missing APPROVAL_EXPIRES_AT_UTC"
[ -n "$DENIES" ] || die "missing APPROVAL_DENIES"
[ -n "$STATEMENT" ] || die "missing APPROVAL_STATEMENT"

[ "$SOURCE" = "live_chat_turn" ] || die "APPROVAL_SOURCE must be live_chat_turn"
[ "$ACTION" = "$APPROVED_ACTION_EXPECTED" ] || die "APPROVED_ACTION does not match expected action"
[[ "$NONCE" =~ ^[A-Za-z0-9-]{8,32}$ ]] || die "APPROVAL_NONCE has invalid shape"

if ! ISSUED_EPOCH=$(date -u -d "$ISSUED_AT" +%s 2>/dev/null); then
  die "APPROVAL_ISSUED_AT_UTC is not parseable"
fi
if ! EXPIRES_EPOCH=$(date -u -d "$EXPIRES_AT" +%s 2>/dev/null); then
  die "APPROVAL_EXPIRES_AT_UTC is not parseable"
fi
if [ -n "$NOW_UTC" ]; then
  if ! NOW_EPOCH=$(date -u -d "$NOW_UTC" +%s 2>/dev/null); then
    die "--now-utc is not parseable"
  fi
else
  NOW_EPOCH=$(date -u +%s)
fi

if [ "$ISSUED_EPOCH" -gt $((NOW_EPOCH + FUTURE_SKEW_SECONDS)) ]; then
  die "approval issued_at is too far in the future"
fi
if [ "$EXPIRES_EPOCH" -le "$NOW_EPOCH" ]; then
  die "approval has expired"
fi
if [ "$EXPIRES_EPOCH" -le "$ISSUED_EPOCH" ]; then
  die "approval expires before or at issued_at"
fi
if [ $((EXPIRES_EPOCH - ISSUED_EPOCH)) -gt "$MAX_LIFETIME_SECONDS" ]; then
  die "approval lifetime exceeds 15 minutes"
fi

NONCE_HASH=$(printf '%s' "$NONCE" | sha256sum | awk '{print $1}')

if [ "$HASH_ONLY" -eq 1 ]; then
  echo "APPROVAL_VALID=yes"
  echo "APPROVAL_NONCE_SHA256=$NONCE_HASH"
  exit 0
fi

echo "APPROVAL_VALID=yes"
echo "APPROVAL_SOURCE_RECORDED=live_chat_turn"
echo "APPROVED_ACTION=$ACTION"
echo "APPROVAL_DENIES=$DENIES"
if [ "$REDACT_OUTPUT" -eq 1 ]; then
  echo "APPROVAL_NONCE_REDACTED=[REDACTED]"
else
  echo "APPROVAL_NONCE_REDACTED=[REDACTED:${#NONCE}-chars]"
fi
echo "APPROVAL_NONCE_SHA256=$NONCE_HASH"
echo "APPROVAL_ISSUED_AT_UTC=$ISSUED_AT"
echo "APPROVAL_EXPIRES_AT_UTC=$EXPIRES_AT"
echo "APPROVAL_NONCE_RAW_STORED=no"
