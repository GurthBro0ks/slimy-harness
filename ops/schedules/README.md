# Schedule Inventory

This directory adds the Ops-3 read-only schedule inventory layer for the
Slimy Harness Ops Manager.

## Purpose

Inventory cron sources, systemd timers, keyword-matched units, and optional
read-only NUC2 schedule surfaces without changing any schedule state.

This pass does not:

- edit cron
- enable/disable timers
- start/stop services
- run scheduled jobs
- send Discord messages

## Files

- `discover-schedules.sh`
  - read-only schedule discovery
  - redacts secret-looking values
  - inventories local cron and timer surfaces
  - attempts optional read-only NUC2 inspection only if `ssh nuc2` is already
    safe and non-interactive
- `validate-schedules.sh`
  - validates syntax, command availability, and mutation-scan safety for the
    Ops-3 schedule inventory layer

## CLI

```bash
ops/harness-ops help
ops/harness-ops schedule inventory
ops/harness-ops schedule validate
```

Both schedule commands are read-only.

## Output Contract

The inventory aims to report, where available:

- machine
- schedule type
- owner/user
- source
- unit or job name
- command summary with redaction
- next run / last run if available
- active/enabled state if available
- related project guess
- risk level
- notes

## Validation

```bash
bash ops/schedules/validate-schedules.sh
```

## Safety Notes

- Root crontab is skipped in an unprivileged pass unless it is safely readable
  without elevation.
- NUC2 inspection is optional and is not required for PASS.
- Redaction covers webhook URLs, bearer values, embedded credentials, and
  secret-looking env assignments.
