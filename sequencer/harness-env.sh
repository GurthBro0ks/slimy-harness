#!/usr/bin/env bash
# harness-env.sh — shared harness environment loader
#
# Loads /home/slimy/.slimy-harness.env if present and exports the variables.
# This provides consistent env indirection for all harness scripts that need
# webhook URLs or other harness configuration.
#
# Usage:
#   source /home/slimy/slimy-harness/sequencer/harness-env.sh
#
# Exports:
#   DISCORD_HARNESS_WEBHOOK_URL  Discord webhook for harness notifications
#   DISCORD_HARNESS_MENTION       Discord user ID mention string
#   HARNESS_REPORT_BASE_URL       Base URL for harness report links
#   HARNESS_NOTIFY_ON_SUCCESS     1 = mention on success too
#   HARNESS_NOTIFY_ATTACH_HTML   1 = attach HTML snapshot (opt-in)
#   HARNESS_NOTIFY_ATTACH_JSON   1 = attach JSON report (opt-in)
#   HARNESS_NOTIFY_PING_ON_SUCCESS alias for HARNESS_NOTIFY_ON_SUCCESS
#   HARNESS_NOTIFY_RELAY_HOST    NUC hostname for NUC2->NUC1 relay
#   HARNESS_NOTIFY_STATE_DIR     Directory for dedupe markers
#
# Safety:
#   - Silently succeeds even if the env file is missing.
#   - Never prints the webhook URL.
#   - Returns 0 unconditionally.

set -euo pipefail

_HARNESS_ENV_FILE="${HARNESS_ENV_FILE:-/home/slimy/.slimy-harness.env}"

if [ -f "$_HARNESS_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$_HARNESS_ENV_FILE"
  set +a
fi

return 0 2>/dev/null || true
