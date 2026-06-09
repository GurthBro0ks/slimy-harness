# Goal-Runner Integration (Phase 2 — Plan)

This document describes how `sequencer/goal_runner.py` is intended to
plug into the existing dispatch loop in `sequencer/auto-sequence.sh`.
**No existing sequencer script is modified by this Phase 1 build.** This
doc is planning-only.

## Current Flow (auto-sequence.sh `run_dispatch`)

The relevant section is `sequencer/auto-sequence.sh` lines 44-593.
The dispatch cycle inside `run_dispatch()` does, in order:

1. (lines 47-65) Stop-file and prerequisite checks.
2. (lines 92-101) Archive the prior `session-report.json` and run
   `auto-close.sh` to update `feature_list.json`.
3. (lines 109-115) Send a Discord completion notification for the prior
   session.
4. (lines 117-118) Run `blocker-report.sh`.
5. (lines 126-159) Build the available-features list and short-circuit
   if empty.
6. (lines 193-258) Build a dispatch prompt for the Qwen model and
   query it.
7. (lines 316-362) Validate the Qwen response and pick a fallback
   deterministically if invalid.
8. (lines 370-394) High-risk approval gate.
9. (lines 396-416) In `--dry-run`, just log what would happen.
10. (lines 418-506) Build the actual agent prompt with
    `MANDATORY STARTUP` + feature description + `FAILED APPROACHES`
    SkillOpt block + `MANDATORY SHUTDOWN` (write
    `session-report.json`).
11. (lines 510-553) Resolve the project directory and dispatch via
    `tmux new-session` running `opencode run` (or fallback to
    `slimy-run auto` or manual).
12. (lines 555-585) Update state file and ping Discord.

The block the loop then waits on is `lines 656-660`:

```bash
while tmux has-session -t "$AGENT_SESSION" 2>/dev/null; do
  sleep 30
done
```

After the tmux session ends, `lines 662-666` run `auto-close.sh` again.

## Proposed Phase 2 Flow

Replace the "build dispatch prompt + tmux spawn" step
(`auto-sequence.sh` lines 396-553) with a single call into the new
goal-runner. Concretely, `run_dispatch()` would invoke:

```bash
python3 /home/slimy/slimy-harness/sequencer/goal_runner.py \
  "$DISPATCH_FEATURE_ID" \
  --max-attempts 3 \
  --wall-clock-minutes 90 \
  --feature-list /home/slimy/feature_list.json \
  --goals-dir   /home/slimy/harness-logs/goals \
  --notify-mode runtime

GR_EXIT=$?
```

The post-loop behavior would then be driven by the goal-runner exit
code:

| Exit | Meaning | What auto-sequence.sh should do |
|------|---------|---------------------------------|
| `0`  | Goal passed (qa verdict=pass) | Run `auto-close.sh` so the QA gate / operator can decide on `passes:true`. Continue to next feature. |
| `2`  | Goal escalated (max attempts or stuck) | Run `auto-close.sh` (it will set `status=blocked`, log to `failed-approaches.json`). Run `blocker-report.sh`. Continue to next feature. |
| `1`  | Internal error (feature not found, malformed feature list, etc.) | Log to `sequencer-errors.log`. Skip this feature. Continue. |

### Lines That Change in `auto-sequence.sh`

The change is bounded. These line ranges (relative to the current
file) need to be replaced or wrapped:

- `auto-sequence.sh:396-553` — the dispatch block. Replace with a
  single `goal_runner.py` invocation followed by handling of the
  exit code. **The Qwen dispatch, prompt assembly, and tmux spawn are
  removed** (goal-runner owns its own prompt, dispatch, and gate).
- `auto-sequence.sh:662-666` — the post-dispatch `auto-close.sh`
  call. **Keep as-is.** `goal_runner.py` does not modify
  `feature_list.json`; the close-out is still `auto-close.sh`'s job.
- `auto-sequence.sh:568-585` — the per-dispatch Discord ping and
  blocker report. **Keep as-is.** `goal_runner.py`'s own notification
  is a SECOND notification focused on the goal outcome (passed or
  escalated), distinct from the per-attempt session notification.

### Replacement Code (sketch)

```bash
log "Dispatching: $DISPATCH_FEATURE_ID in $DISPATCH_PROJECT [risk=$DISPATCH_RISK]"

if [ "$DRY_RUN" = "1" ]; then
  log "DRY RUN: would run goal_runner.py for $DISPATCH_FEATURE_ID"
  python3 /home/slimy/slimy-harness/sequencer/goal_runner.py \
    "$DISPATCH_FEATURE_ID" \
    --max-attempts 3 \
    --wall-clock-minutes 90 \
    --feature-list /home/slimy/feature_list.json \
    --goals-dir   /home/slimy/harness-logs/goals \
    --dry-run \
    --notify-mode dry-run
  DISPATCH_RESULT="goal_runner_dry_run"
  return 0
fi

python3 /home/slimy/slimy-harness/sequencer/goal_runner.py \
  "$DISPATCH_FEATURE_ID" \
  --max-attempts 3 \
  --wall-clock-minutes 90 \
  --feature-list /home/slimy/feature_list.json \
  --goals-dir   /home/slimy/harness-logs/goals \
  --notify-mode runtime
GR_EXIT=$?

case "$GR_EXIT" in
  0)  DISPATCH_RESULT="goal_passed"  ;;
  2)  DISPATCH_RESULT="goal_escalated" ;;
  *)  DISPATCH_RESULT="goal_error" ;;
esac
return 0
```

### Why goal-runner Does NOT Set `passes:true`

This is intentional and important. The current close-out chain is:

1. `auto-sequence.sh` dispatches a feature.
2. The agent does the work and writes `session-report.json`.
3. `auto-close.sh` reads the report and sets `passes:true` ONLY when
   `status=completed AND tests.passed=true`.

`goal_runner.py` is a **pre-QA** controller. It runs the truth gate
(via `qa-gate.sh`) and decides whether the *agent's report* is
self-consistent (status=completed + tests.passed + no stubs). It does
NOT do the human / operator / QA-agent review that establishes
"this feature is genuinely done".

A passing goal-runner run produces `goal.json` with
`status="passed"`. The next run of `auto-close.sh` (which the
existing dispatch loop already calls on the new
`session-report.json`) will then set `passes:true` per the
existing rules. The harness's existing QA separation is preserved.

### Environment Variables `goal_runner.py` Will Need

These are all already present in the harness environment:

- `DISCORD_HARNESS_WEBHOOK_URL` — for `--notify-mode runtime`. Read
  via the existing `notify-session-complete.sh` path (goal-runner
  does not call Discord directly).
- Standard `PATH`, `HOME`, `USER`. No new env vars are required.

The `--goals-dir` defaults to `/home/slimy/harness-logs/goals`
(matches existing harness-logs convention). The `--feature-list`
default is `/home/slimy/feature_list.json` (the live one). For
tests, both flags accept overrides.

### Harness CLI Subcommands (proposed)

A future `harness goal` family of subcommands would wrap the
goal-runner. Skeleton:

```text
harness goal run <feature_id> [--max-attempts N] [--dry-run]
harness goal status <feature_id>
harness goal logs <feature_id> [--attempt N]
harness goal stop <feature_id>
```

`harness goal run` would just call `goal_runner.py` with the same
flags, defaulting `--notify-mode runtime` for the live CLI and
`--notify-mode dry-run` when `--dry-run` is set.

### Phase 2 Worktree Strategy (DESIGN — not implemented)

In real mode, `goal_runner.py` will create a git worktree per
attempt, isolated from the main repo:

```
/tmp/slimy-goals/<feature_id>/attempt-<N>/worktree
```

- Worktree is created from the project's current `HEAD` at the
  start of each attempt.
- The main repo is never modified by `goal_runner.py` directly.
- A successful attempt (`qa verdict=pass`) is merged or cherry-picked
  back to the main repo.
- A failed attempt is archived (commit ref + diff + session report)
  and the worktree is removed.
- **No `git reset --hard` is ever used.** Rollback is always via
  worktree removal.

### Sequencing Rule

The outer `auto-sequence.sh` loop should only call `goal_runner.py`
when a `feature_id` is selected. The dispatch loop's existing
`session-report.json` -> `auto-close.sh` -> next-feature flow is
unchanged. goal-runner does not need to know about other features.

## Phase 1 Status

This document ships with the Phase 1 dry-run build. No line of
`auto-sequence.sh` is changed yet. The build at HEAD only adds the
new files needed for goal-runner, qa-gate, build_fix_packet, the
schema, and tests.
