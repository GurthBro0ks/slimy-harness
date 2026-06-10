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
| `HARNESS_GOAL_RUNNER_AGENT_CMD` | (unset) | If set, passed as `--agent-cmd` to goal_runner.py. Defaults to `opencode` when unset. |

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

## Phase 5 (controlled auto-sequence smoke)

Phase 5 adds smoke/test environment overrides to auto-sequence.sh so the
goal-runner path can be exercised against synthetic state without touching
production files.

### Smoke/Test Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `HARNESS_SMOKE_ROOT` | (unset) | When set, redirects all mutable paths to `$HARNESS_SMOKE_ROOT/...`. Production paths unchanged when unset. |
| `HARNESS_SKIP_ENV_FILE` | (unset) | When `1`, skips sourcing `/home/slimy/.slimy-harness.env`. |

### Paths Redirected by HARNESS_SMOKE_ROOT

When `HARNESS_SMOKE_ROOT` is set:
- `STOP_FILE` → `$HARNESS_SMOKE_ROOT/harness-stop`
- `LOOP_LOG_DIR` → `$HARNESS_SMOKE_ROOT/logs`
- `SESSION_REPORT` → `$HARNESS_SMOKE_ROOT/session-report.json`
- `FEATURE_LIST` → `$HARNESS_SMOKE_ROOT/feature_list.json`
- `FAILED_APPROACHES` → `$HARNESS_SMOKE_ROOT/failed-approaches.json`
- `STATE_FILE` → `$HARNESS_SMOKE_ROOT/sequencer-state.json`
- `KB_SESSIONS_DIR` → `$HARNESS_SMOKE_ROOT/kb-sessions`
- `ERROR_LOG` → `$HARNESS_SMOKE_ROOT/logs/sequencer-errors.log`
- `PENDING_APPROVAL` → `$HARNESS_SMOKE_ROOT/pending-approval.json`
- `DISPATCH_OUTPUT` → `$HARNESS_SMOKE_ROOT/qwen-dispatch-output.json`

Note: `SEQUNCER_DIR` and `NARRATIVE` are NOT redirected (they point to the
real harness repo). For smoke runs that need a stub `goal_runner.py`, use a
modified copy of auto-sequence.sh with `SEQUNCER_DIR` pointing to a stub dir.

### Smoke Example

```bash
HARNESS_SMOKE_ROOT=/tmp/smoke-root \
HARNESS_SKIP_ENV_FILE=1 \
HARNESS_USE_GOAL_RUNNER=1 \
HARNESS_GOAL_RUNNER_NOTIFY_MODE=disabled \
HARNESS_GOAL_RUNNER_MAX_ATTEMPTS=1 \
bash sequencer/auto-sequence.sh
```

## Phase 6 (controlled live auto-sequence smoke)

Phase 6 proves the real goal_runner.py can run in LIVE single-attempt mode
through auto-sequence.sh's `run_goal_runner_dispatch()` with synthetic state.

### New Environment Variable

| Variable | Default | Purpose |
|----------|---------|---------|
| `HARNESS_GOAL_RUNNER_AGENT_CMD` | (unset) | Override the agent CLI. Passed as `--agent-cmd` to goal_runner.py. Used for smoke/testing with deterministic agents. |

### Live Smoke Example

```bash
# Direct goal_runner.py invocation (simulating auto-sequence.sh dispatch):
python3 sequencer/goal_runner.py <feature-id> \
    --live-dispatch \
    --max-attempts 1 \
    --notify-mode disabled \
    --feature-list $HARNESS_SMOKE_ROOT/feature_list.json \
    --goals-dir $HARNESS_SMOKE_ROOT/goals \
    --worktree-root $HARNESS_SMOKE_ROOT/worktrees \
    --agent-cmd sequencer/tests/fixtures/test-agent-live-smoke.sh \
    --poll-interval-seconds 2

# Through auto-sequence.sh:
HARNESS_SMOKE_ROOT=/tmp/smoke-root \
HARNESS_SKIP_ENV_FILE=1 \
HARNESS_USE_GOAL_RUNNER=1 \
HARNESS_GOAL_RUNNER_LIVE_DISPATCH=1 \
HARNESS_GOAL_RUNNER_NOTIFY_MODE=disabled \
HARNESS_GOAL_RUNNER_MAX_ATTEMPTS=1 \
HARNESS_GOAL_RUNNER_AGENT_CMD=/path/to/deterministic-agent \
bash sequencer/auto-sequence.sh
```

### Deterministic Test Agent

`sequencer/tests/fixtures/test-agent-live-smoke.sh` is a deterministic agent that:
- Accepts the standard `run --dir <worktree> --dangerously-skip-permissions <prompt>` invocation
- Extracts the session report path from the prompt preamble
- Writes `src/main.py` with `print("smoke_ok")` in the worktree
- Writes a passing session-report.json
- Exits 0

### Bug Fix

Phase 6 also fixes an undefined `warn()` function bug in auto-sequence.sh.
Two `|| warn "..."` calls in `run_dispatch()` (sync and notify) referenced
a function that didn't exist. Added `warn()` alongside `log()` and `err()`.

## Phase 7 (controlled live auto-sequence retry smoke)

Phase 7 proves the real auto-sequence.sh entrypoint can invoke goal_runner.py
in LIVE retry mode with `max_attempts=2`, performing a full two-attempt cycle
through synthetic state.

### Retry Smoke Example

```bash
# Through auto-sequence.sh (recommended):
HARNESS_SMOKE_ROOT=/tmp/smoke-root \
HARNESS_SKIP_ENV_FILE=1 \
HARNESS_USE_GOAL_RUNNER=1 \
HARNESS_GOAL_RUNNER_LIVE_DISPATCH=1 \
HARNESS_GOAL_RUNNER_NOTIFY_MODE=disabled \
HARNESS_GOAL_RUNNER_MAX_ATTEMPTS=2 \
HARNESS_GOAL_RUNNER_ALLOW_RETRY=1 \
HARNESS_GOAL_RUNNER_WORKTREE_ROOT=/tmp/smoke-root/worktrees \
HARNESS_GOAL_RUNNER_GOALS_DIR=/tmp/smoke-root/goals \
HARNESS_GOAL_RUNNER_AGENT_CMD=sequencer/tests/fixtures/test-agent-live-retry-smoke.sh \
bash sequencer/auto-sequence.sh

# Direct goal_runner.py invocation:
GOAL_RUNNER_ALLOW_RETRY=1 python3 sequencer/goal_runner.py <feature-id> \
    --live-dispatch \
    --max-attempts 2 \
    --notify-mode disabled \
    --feature-list $HARNESS_SMOKE_ROOT/feature_list.json \
    --goals-dir $HARNESS_SMOKE_ROOT/goals \
    --worktree-root $HARNESS_SMOKE_ROOT/worktrees \
    --agent-cmd sequencer/tests/fixtures/test-agent-live-retry-smoke.sh \
    --poll-interval-seconds 2
```

### Deterministic Retry Test Agent

`sequencer/tests/fixtures/test-agent-live-retry-smoke.sh` is a deterministic agent that:
- Detects attempt number from the worktree path (`attempt-N` directory)
- Extracts the session report path from the prompt preamble
- Attempt 1: writes `src/main.py` with `print("wrong")` and a failing session report
- Attempt 2: writes `src/main.py` with `print("retry_ok")` and a passing session report
- Never touches production paths, never sends Discord, never pushes

### Known Side-Effect

When running the real `auto-sequence.sh` entrypoint with `HARNESS_SMOKE_ROOT`,
the `auto-close.sh` step runs against the synthetic session report and may
update the production `feature_list.json`. This is expected: auto-close is a
legacy side-effect of running through the full auto-sequence.sh path. The
goal-runner itself does not modify `feature_list.json`.

## Future Phases

To enable live dispatch with runtime notification:

```bash
export HARNESS_GOAL_RUNNER_NOTIFY_MODE=runtime   # requires GOAL_RUNNER_ALLOW_RUNTIME_NOTIFY=1
```

Future phases may also:
- Set `HARNESS_GOAL_RUNNER_MAX_ATTEMPTS=3`.
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
- **Phase 4**: Wire into `auto-sequence.sh` behind opt-in gate.
- **Phase 5**: Controlled auto-sequence smoke with `HARNESS_SMOKE_ROOT` and `HARNESS_SKIP_ENV_FILE` overrides.
- **Phase 6**: Controlled live auto-sequence smoke with `HARNESS_GOAL_RUNNER_LIVE_DISPATCH=1`, deterministic test agent, and `HARNESS_GOAL_RUNNER_AGENT_CMD` support.
- **Phase 7**: Controlled live auto-sequence retry smoke with `MAX_ATTEMPTS=2`, `ALLOW_RETRY=1`, deterministic retry agent, and full two-attempt cycle (fail→fix→pass).
