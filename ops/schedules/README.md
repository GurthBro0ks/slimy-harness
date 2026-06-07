# Schedule Inventory and Dry-Run Controls

This directory contains:

- Ops-3 read-only schedule inventory tooling
- Ops-4B read-only, registry-backed schedule control planning and dry-run tooling

## Purpose

Inventory cron sources, systemd timers, keyword-matched units, and optional
read-only NUC2 schedule surfaces, plus provide plan/dry-run previews for
future schedule controls without changing schedule state.

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
- `schedule-registry.json`
  - allowlisted schedule control targets for Ops-4B dry-run planning
  - includes managed mode, risk, approval level, and live flags (all false)
- `schedule-plan.sh`
  - read-only schedule planner for one `schedule_id`
- `schedule-dry-run.sh`
  - read-only future enable/disable preview as `WOULD_RUN` text only
- `schedule-run-once-dry-run.sh`
  - read-only future one-shot trigger preview as `WOULD_RUN` text only
- `validate-schedule-controls.sh`
  - validates registry, script safety, redaction markers, and dry-run-only
    contract for Ops-4B controls

## CLI

```bash
ops/harness-ops help
ops/harness-ops schedule inventory
ops/harness-ops schedule validate
ops/harness-ops schedule plan <schedule_id>
ops/harness-ops schedule dry-run <schedule_id> --action enable|disable
ops/harness-ops schedule run-once-dry-run <schedule_id>
ops/harness-ops schedule controls-validate
```

All schedule commands in Ops-3/Ops-4B are read-only.

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
bash ops/schedules/validate-schedule-controls.sh
```

## Safety Notes

- Root crontab is skipped in an unprivileged pass unless it is safely readable
  without elevation.
- NUC2 inspection is optional and is not required for PASS.
- Redaction covers webhook URLs, bearer values, embedded credentials, and
  secret-looking env assignments.
- Ops-4B does not implement live enable/disable/run-once.
- Any future mutation flow must remain gated behind plan + dry-run + validate +
  explicit flags and proof-dir capture.
