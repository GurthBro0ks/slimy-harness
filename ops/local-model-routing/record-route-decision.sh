#!/usr/bin/env bash
# Local Model Routing Phase 4 — Proof-Only Route Decision Recorder
#
# Audit-only wrapper that:
#   1. Runs the existing policy validator.
#   2. Runs the existing dry-run route helper (twice: key/value + JSON).
#   3. Writes proof artifacts (txt, json, env, command, validator output)
#      into the given proof directory.
#
# This script MUST NOT:
#   * call Ollama
#   * pull models
#   * open a network socket (no curl/wget/nc/socat)
#   * read or print secrets, .env, or Discord webhook URLs
#   * send Discord messages
#   * mutate runtime state, cron, systemd, tmux, Caddy, DNS, or services
#   * wire into goal-runner or auto-sequence
#
# It is intentionally limited to: echo, printf, mkdir, bash builtins,
# the committed policy validator, the committed dry-run helper, and
# standard POSIX utilities.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-policy.sh"
DRY_RUN="$SCRIPT_DIR/dry-run-route.py"

usage() {
  cat <<'EOF'
Usage: bash record-route-decision.sh --proof-dir DIR [options]

Required:
  --proof-dir DIR         Directory to write proof artifacts into.
                          Created if it does not exist (mode 0700).

Options:
  --policy PATH           Policy JSON (default: config/local-model-routing.policy.json)
  --task NAME             Task name (required)
  --risk LEVEL            LOW (default), MEDIUM, or HIGH
  --touches LIST          Comma-separated surface list (default: none)
  --machine NAME          nuc1 (default) or nuc2
  -h, --help              Show this help

Artifacts written into --proof-dir:
  route-decision.txt
  route-decision.json
  route-decision.env
  route-decision-command.txt
  route-decision-policy-validator.txt
EOF
}

PROOF_DIR=""
POLICY="config/local-model-routing.policy.json"
TASK=""
RISK="LOW"
TOUCHES="none"
MACHINE="nuc1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proof-dir) PROOF_DIR="$2"; shift 2 ;;
    --policy)    POLICY="$2"; shift 2 ;;
    --task)      TASK="$2"; shift 2 ;;
    --risk)      RISK="$2"; shift 2 ;;
    --touches)   TOUCHES="$2"; shift 2 ;;
    --machine)   MACHINE="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *)           printf 'ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$PROOF_DIR" ]]; then
  printf 'ERROR: --proof-dir is required\n' >&2
  usage >&2
  exit 2
fi
if [[ -z "$TASK" ]]; then
  printf 'ERROR: --task is required\n' >&2
  usage >&2
  exit 2
fi
case "$RISK" in
  LOW|MEDIUM|HIGH) ;;
  *) printf 'ERROR: --risk must be LOW, MEDIUM, or HIGH (got: %s)\n' "$RISK" >&2; exit 2 ;;
esac
case "$MACHINE" in
  nuc1|nuc2) ;;
  *) printf 'ERROR: --machine must be nuc1 or nuc2 (got: %s)\n' "$MACHINE" >&2; exit 2 ;;
esac

# Refuse obvious dangerous proof-dir targets
case "$PROOF_DIR" in
  /etc|/etc/*|/|/bin|/bin/*|/sbin|/sbin/*|/usr|/usr/*|/var|/var/*|/root|/root/*|/boot|/boot/*)
    printf 'ERROR: refusing unsafe --proof-dir: %s\n' "$PROOF_DIR" >&2
    exit 2
    ;;
esac

if [[ ! -d "$PROOF_DIR" ]]; then
  mkdir -p -m 0700 "$PROOF_DIR"
fi
if [[ ! -d "$PROOF_DIR" || ! -w "$PROOF_DIR" ]]; then
  printf 'ERROR: --proof-dir is not a writable directory: %s\n' "$PROOF_DIR" >&2
  exit 2
fi

# Resolve policy path relative to repo root
if [[ "$POLICY" != /* ]]; then
  POLICY="$REPO_ROOT/$POLICY"
fi
if [[ ! -f "$POLICY" ]]; then
  printf 'ERROR: policy file not found: %s\n' "$POLICY" >&2
  exit 2
fi

# Run the committed policy validator
VALIDATOR_OUT="$PROOF_DIR/route-decision-policy-validator.txt"
EXIT_CODE=0
if ! bash "$VALIDATOR" "$POLICY" > "$VALIDATOR_OUT" 2>&1; then
  EXIT_CODE=1
fi

# Record the command that produced these artifacts
COMMAND_OUT="$PROOF_DIR/route-decision-command.txt"
{
  printf '# Local Model Routing Phase 4 — Recorded Command\n'
  printf 'RECORDED_AT_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'PROOF_DIR=%s\n' "$PROOF_DIR"
  printf 'POLICY=%s\n' "$POLICY"
  printf 'TASK=%s\n' "$TASK"
  printf 'RISK=%s\n' "$RISK"
  printf 'TOUCHES=%s\n' "$TOUCHES"
  printf 'MACHINE=%s\n' "$MACHINE"
  printf 'DRY_RUN_ONLY=yes\n'
  printf 'LIVE_ROUTING_ENABLED=no\n'
  printf 'OLLAMA_CALLED=no\n'
  printf 'MODELS_PULLED=no\n'
  printf 'GOAL_RUNNER_CHANGED=no\n'
  printf 'AUTO_SEQUENCE_CHANGED=no\n'
  printf 'DISCORD_SENT=no\n'
} > "$COMMAND_OUT"

# Run the existing dry-run helper twice: key/value then JSON
DECISION_TXT="$PROOF_DIR/route-decision.txt"
DECISION_JSON="$PROOF_DIR/route-decision.json"
DECISION_ENV="$PROOF_DIR/route-decision.env"

if ! python3 "$DRY_RUN" \
    --policy "$POLICY" \
    --task "$TASK" \
    --risk "$RISK" \
    --touches "$TOUCHES" \
    --machine "$MACHINE" \
    > "$DECISION_TXT" 2>&1; then
  EXIT_CODE=1
fi

if ! python3 "$DRY_RUN" \
    --policy "$POLICY" \
    --task "$TASK" \
    --risk "$RISK" \
    --touches "$TOUCHES" \
    --machine "$MACHINE" \
    --json \
    > "$DECISION_JSON" 2>&1; then
  EXIT_CODE=1
fi

# Build the shell-safe env file by extracting from the txt decision.
# Each line is "KEY=VALUE"; if a key is absent we write it as "none".
{
  extract() {
    local key="$1"
    local line
    line=$(grep -E "^${key}=" "$DECISION_TXT" || true)
    if [[ -n "$line" ]]; then
      printf '%s\n' "$line"
    else
      printf '%s=none\n' "$key"
    fi
  }
  printf '%s\n' "LOCAL_MODEL_ALLOWED=$(grep -E '^LOCAL_MODEL_ALLOWED=' "$DECISION_TXT" | tail -n1 | cut -d= -f2-)"
  printf '%s\n' "LOCAL_MODEL_TARGET=$(grep -E '^TARGET=' "$DECISION_TXT" | tail -n1 | cut -d= -f2-)"
  printf '%s\n' "LOCAL_MODEL_MODEL=$(grep -E '^MODEL=' "$DECISION_TXT" | tail -n1 | cut -d= -f2-)"
  printf '%s\n' "LOCAL_MODEL_MODE=$(grep -E '^MODE=' "$DECISION_TXT" | tail -n1 | cut -d= -f2-)"
  printf '%s\n' "LOCAL_MODEL_REASON=$(grep -E '^REASON=' "$DECISION_TXT" | tail -n1 | cut -d= -f2-)"
  printf '%s\n' "LOCAL_MODEL_MAX_OUTPUT_TOKENS=$(grep -E '^MAX_OUTPUT_TOKENS=' "$DECISION_TXT" | tail -n1 | cut -d= -f2-)"
  printf '%s\n' "LOCAL_MODEL_REQUIRES_REVIEW=$(grep -E '^REQUIRES_REVIEW=' "$DECISION_TXT" | tail -n1 | cut -d= -f2-)"
  printf '%s\n' "LOCAL_MODEL_DRY_RUN_ONLY=yes"
  printf '%s\n' "LOCAL_MODEL_LIVE_ROUTING_ENABLED=no"
  printf '%s\n' "LOCAL_MODEL_OLLAMA_CALLED=no"
  printf '%s\n' "LOCAL_MODEL_MODELS_PULLED=no"
} > "$DECISION_ENV"

# Defense-in-depth: forbid shell-meta characters in the .env file values.
# This is a safety net against an accidental policy-validator drift
# that emits backticks, $(), or quotes.
if grep -E '[^A-Za-z0-9_=.:/-]' "$DECISION_ENV" >/dev/null 2>&1; then
  printf 'WARN: non-safe characters detected in %s; leaving file in place for audit\n' "$DECISION_ENV" >&2
fi

exit "$EXIT_CODE"
