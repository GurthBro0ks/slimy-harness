# Goal-Runner Integration — Phase 4 (auto-sequence.sh wire)

This document describes how `sequencer/goal_runner.py` is wired into
`sequencer/auto-sequence.sh` behind an explicit opt-in safety gate.

## Current State (Phase 4)

The goal-runner is **dormant by default**. Legacy single-shot dispatch
continues to run unless explicitly enabled.

### Opt-In Gate

```bash
HARNESS_USE_GOAL_RUNNER=1   # must be "1" to activate goal-runner path
```

If this variable is unset or any other value, `run_dispatch()` runs the
existing legacy dispatch path unchanged.

### Environment Controls

| Variable | Default | Purpose |
|----------|---------|---------|
| `HARNESS_USE_GOAL_RUNNER` | (unset) | Master opt-in. Must be `1` to activate. |
| `HARNESS_GOAL_RUNNER_LIVE_DISPATCH` | (unset) | If `1`, passes `--live-dispatch` to goal_runner.py. Otherwise passes `--dry-run`. |
| `HARNESS_GOAL_RUNNER_ALLOW_RETRY` | (unset) | If `1`, exports `GOAL_RUNNER_ALLOW_RETRY=1` and allows `max_attempts > 1`. |
| `HARNESS_GOAL_RUNNER_MAX_ATTEMPTS` | `1` | Number of attempts. Fails closed if `>1` and `ALLOW_RETRY` is not `1`. |
| `HARNESS_GOAL_RUNNER_NOTIFY_MODE` | `disabled` | One of `disabled`, `dry-run`, `runtime`. `runtime` is downgraded to `disabled` in Phase 4. |
| `HARNESS_GOAL_RUNNER_WORKTREE_ROOT` | `/tmp/slimy-goals` | Parent directory for per-attempt git worktrees. |
| `HARNESS_GOAL_RUNNER_GOALS_DIR` | `/home/slimy/harness-logs/goals` | Directory for goal state files. |

### Fail-Closed Behavior

- If `HARNESS_USE_GOAL_RUNNER=1` but `goal_runner.py` is missing: exits non-zero.
- If `goal_runner.py` exits non-zero: recorded as `goal_runner:error`, does not continue as success.
- If `HARNESS_GOAL_RUNNER_NOTIFY_MODE=runtime`: downgraded to `disabled` with a WARN log.
- If `HARNESS_GOAL_RUNNER_MAX_ATTEMPTS > 1` but `HARNESS_GOAL_RUNNER_ALLOW_RETRY != 1`: exits non-zero with clear message.

### How It Works

In `auto-sequence.sh:run_dispatch()`:

1. The function runs through stop-file checks, session report archival,
   auto-close, Discord notification, blocker report, feature selection,
   Qwen dispatch, and HIGH-risk approval gate exactly as before.
2. After the HIGH-risk gate, if `HARNESS_USE_GOAL_RUNNER=1`:
   - Calls `run_goal_runner_dispatch()` helper.
   - The helper builds the goal_runner.py command with all env-controlled flags.
   - State file and Discord notification are updated after the goal-runner call.
   - `DISPATCH_RESULT` is set to `goal_runner:passed`, `goal_runner:escalated`, or `goal_runner:error`.
   - Returns immediately (skips legacy dispatch).
3. If `HARNESS_USE_GOAL_RUNNER` is not `1`, the legacy dispatch path runs unchanged.

### Legacy Default Behavior (unchanged)

Without `HARNESS_USE_GOAL_RUNNER=1`, the dispatch path is:

1. Qwen model selects next feature.
2. Agent prompt is built with MANDATORY STARTUP + feature + SkillOpt + SHUTDOWN.
3. Dispatched via `opencode run` in tmux (or fallback).
4. State update + Discord notification.

## Phase 5 (future)

To enable live dispatch:

```bash
export HARNESS_USE_GOAL_RUNNER=1
export HARNESS_GOAL_RUNNER_LIVE_DISPATCH=1
export HARNESS_GOAL_RUNNER_MAX_ATTEMPTS=2
export HARNESS_GOAL_RUNNER_ALLOW_RETRY=1
export HARNESS_GOAL_RUNNER_NOTIFY_MODE=dry-run   # or runtime when approved
```

Phase 5 may also:
- Set `HARNESS_GOAL_RUNNER_MAX_ATTEMPTS=2` or `3`.
- Enable `HARNESS_GOAL_RUNNER_NOTIFY_MODE=runtime` with an explicit allow flag.

## Rollback

To disable the goal-runner path:

```bash
unset HARNESS_USE_GOAL_RUNNER
```

Or revert the Phase 4 commit entirely:

```bash
git revert <phase4-commit-sha>
```

Legacy dispatch is completely preserved and runs when the gate is off.

## Exit Codes

The `run_goal_runner_dispatch()` helper returns goal_runner.py's exit code:

| Exit | Meaning | DISPATCH_RESULT |
|------|---------|-----------------|
| `0`  | Goal passed (QA verdict=pass) | `goal_runner:passed` |
| `2`  | Goal escalated (max attempts or stuck) | `goal_runner:escalated` |
| `1`  | Internal error (feature not found, safety violation) | `goal_runner:error` |

## Why goal-runner Does NOT Set passes:true

The goal-runner is a pre-QA controller. It runs truth gates and decides
whether the agent's report is self-consistent. It does NOT set `passes:true`.
The existing `auto-close.sh` chain handles that per the established QA separation.

## Phase History

- **Phase 1**: Dry-run controller (`--dry-run` enforced). Tests + fixtures.
- **Phase 2**: Controlled live single-attempt mode (`--live-dispatch` + worktree).
- **Phase 3**: Controlled live retry mode (max_attempts > 1 + fix-packet).
- **Phase 4**: Wire into `auto-sequence.sh` behind opt-in gate (this phase).
- **Phase 5**: (future) Enable live dispatch from auto-sequence with retry.
