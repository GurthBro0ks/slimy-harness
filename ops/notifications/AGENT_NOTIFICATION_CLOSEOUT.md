# Agent Notification Closeout

This document defines when and how autonomous agent sessions must handle
Discord harness notifications before closing.

## When Notification Is Required

Every implementation, fix, or closeout session that creates a proof directory
must handle notification before final response. This includes sessions that:

- Created or modified code, configs, or docs
- Created a proof directory under `/tmp/proof_*`
- Ran validation or tests as part of a harness task

## When Notification Is Disabled

Notification may be skipped ONLY for:

- **Discovery/read-only sessions** that made no changes and created no proof
  dir requiring notification (but must still include closeout fields in final
  response)
- **Sessions explicitly told not to notify** by the task prompt
- **Safety hold**: when a webhook URL is found in logs, output, or files
  (notification is blocked until the URL is rotated/regenerated)

## NUC1 vs NUC2 Behavior

| Aspect | NUC1 | NUC2 |
|--------|------|------|
| Webhook env | Present (sends directly) | Absent (must relay) |
| Notifier script | `sequencer/notify-proof-dir-complete.sh` | Same script, relay path |
| Relay required | No | Yes, via SSH to NUC1 |
| Relay env key | Not needed | `HARNESS_NOTIFY_RELAY_HOST=nuc1` |
| Dedupe markers | `.sent` files in notify-state | `.relay-sent` files in notify-state |
| Webhook URL storage | In `.slimy-harness.env` | MUST NOT be stored on NUC2 |

## Required Final Fields

Every agent session final response must include:

```
DISCORD_SENT=yes/no
NOTIFY_MODE=runtime/relay/dry-run/disabled
DEDUPE_RESULT=sent/skipped/not_checked
REPORT_URL=https://harness.slimyai.xyz/reports/sessions/... or none
NOTIFY_REASON=<sent, dedupe skipped, disabled by prompt, discovery-only, approved test required, or failure reason>
```

## Secret Safety Rules

- Never print webhook URLs in logs, stdout, or proof files
- Never dump `.env` files
- Never store webhook URLs on NUC2
- If a webhook URL appears anywhere in agent output, stop and recommend
  rotation/regeneration without repeating the URL
- The notifier scripts handle redaction internally; agents must not bypass this

## Dedupe Behavior

- Dedupe is file-based: `sha256(absolute_path + mtime + size)`
- NUC1 uses `.sent` markers in `/home/slimy/harness-logs/notify-state/`
- NUC2 uses `.relay-sent` markers in the same directory
- If dedupe skips a notification, the agent must report the dedupe marker path
- Use `--force` to bypass dedupe for manual retest only
- Markers older than 30 days are garbage-collected automatically

## Approved Report URL Format

```
https://harness.slimyai.xyz/reports/sessions/<filename>
```

Report URLs are owner-gated (Caddy 307 redirect to login). Unauthenticated
access returns a redirect, not the report content.

## Approved Notification Commands

### NUC1 (direct send)

```bash
# Always dry-run first:
bash /home/slimy/slimy-harness/sequencer/notify-proof-dir-complete.sh \
  --dry-run \
  --proof-dir /tmp/proof_... \
  --repo-path /path/to/repo \
  --repo-name repo-name \
  --feature-id feature-id \
  --task-title "Task Title" \
  --agent opencode \
  --source-nuc nuc1 \
  --status completed \
  --summary "Brief summary"

# Then send (remove --dry-run):
bash /home/slimy/slimy-harness/sequencer/notify-proof-dir-complete.sh \
  --proof-dir /tmp/proof_... \
  --repo-path /path/to/repo \
  --repo-name repo-name \
  --feature-id feature-id \
  --task-title "Task Title" \
  --agent opencode \
  --source-nuc nuc1 \
  --status completed \
  --summary "Brief summary"
```

### NUC2 (relay through NUC1)

Same command with `--source-nuc nuc2`. The script detects the missing webhook
and relays via SSH to `HARNESS_NOTIFY_RELAY_HOST`.

## Validation Commands (read-only, no sends)

```bash
ops/harness-ops notify status       # Check notification pipeline health
ops/harness-ops notify dry-run      # Preview a notification without sending
ops/harness-ops notify dedupe-check # Check dedupe marker state
```

## Discord Naming Convention

- Discord-facing text must use **GurthBr0oks**, never Jason or any other name.
- Agent names in notifications: opencode, claude, codex, manual.
- NUC names: nuc1, nuc2.

## History

- 2026-06-07: Created after discovery that 8 recent agent sessions did not
  invoke notification hooks at session end (no system outage; pipeline was
  healthy). Root cause was procedural: AGENTS.md had no notification closeout
  gate.
