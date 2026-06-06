# Notification Registry

This directory is the read-only groundwork for a future Harness Ops Manager.

## Purpose

Document the current notification surfaces without storing or printing
secret values.

This is not a notifier rewrite. It does not change runtime behavior.

## Files

- `registry.json`
  - machine-readable inventory of notification channels, env key names,
    dedupe marker paths, relay marker paths, report URL bases, and
    ownership boundaries
- `validate-notifications.sh`
  - read-only validator that checks registry integrity, expected scripts,
    env-key presence only, marker directories, relay assumptions, and
    redaction safety
- `notify-status.sh`
  - notification health summary: registry, env keys, channels, markers,
    ownership assumptions, legacy cleanup flags
- `notify-dry-run.sh`
  - preview a Discord-style notification without sending anything
- `dedupe-check.sh`
  - inspect dedupe marker status for a proof dir or session ID

## Rules

- env key names only, never values
- no webhook URLs
- no secret copying into docs or logs
- no Discord sends

## Current Model

- NUC1 owns the webhook env key(s)
- NUC2 owns the relay-host pointer only
- completion notifications are deduped with `.sent` markers
- NUC2 relay is deduped with `.relay-sent` / `.relay-failed` markers
- report links use `https://harness.slimyai.xyz/reports/sessions/...`

## Validation

```bash
bash ops/notifications/validate-notifications.sh
```

Optional proof-dir scan:

```bash
bash ops/notifications/validate-notifications.sh --proof-dir /tmp/proof_...
```

## CLI

The read-only ops CLI is at `ops/harness-ops`:

```bash
ops/harness-ops help
ops/harness-ops notify status
ops/harness-ops notify dry-run
ops/harness-ops notify dedupe-check <proof_dir_or_session_id>
```

All CLI commands are read-only. No Discord messages are sent. No secrets
are printed. Real sends still happen only through the existing sequencer
notifier scripts.
