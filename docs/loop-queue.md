# Harness Loop Queue

`ops/harness-loop-queue` is a local queue-only state model for future Slimy
Harness loop work. It is intentionally not a runner.

The queue can create, list, inspect, validate, hold, and conservatively
transition queue items. It can also apply the local proof gate checker to a
queue item. It does not run agents, execute prompts, call models, call the
network, read environment variables, send Discord, restart services, edit
cron/systemd/tmux/Caddy/DNS, or wire itself into automation.

## Storage

Every command requires an explicit queue path:

```bash
ops/harness-loop-queue init --queue /tmp/harness-loop-queue.json
```

There is no default production queue path. Tests and smoke checks should use
temporary files. The CLI writes only the explicit `--queue` JSON file and uses
an atomic replace for saves.

## Commands

```bash
ops/harness-loop-queue init --queue /tmp/queue.json
ops/harness-loop-queue add --queue /tmp/queue.json \
  --phase harness-example \
  --title "Review local proof" \
  --target-machine NUC1 \
  --target-repo /home/slimy/slimy-harness
ops/harness-loop-queue list --queue /tmp/queue.json
ops/harness-loop-queue show --queue /tmp/queue.json q000001
ops/harness-loop-queue validate --queue /tmp/queue.json
ops/harness-loop-queue gate --queue /tmp/queue.json q000001 --proof-dir /tmp/proof_dir
ops/harness-loop-queue hold --queue /tmp/queue.json q000001 --reason "owner review required"
```

Use `--json` on commands when structured output is needed.

## Item Schema

Queue items include:

- `id`
- `created_at`
- `updated_at`
- `phase`
- `title`
- `target_machine`
- `target_repo`
- `requested_by`
- `model_recommendation`
- `glm_thinking_level`
- `status`
- `safety_level`
- `proof_dir`
- `proof_gate_verdict`
- `manual_qa_status`
- `next_required_gate`
- `notes`
- `blocked_reason`
- `history`

History is append-only from the CLI's perspective and records local state
events such as creation, hold, transition refusal, and proof gate application.

## Status Model

Allowed modeled statuses:

- `DRAFT`
- `READY_FOR_REVIEW`
- `HOLD`
- `BLOCKED`
- `READY_FOR_OWNER_QA`
- `READY_FOR_CLOSEOUT`
- `ACCEPTED`
- `REJECTED`

This slice does not expose any command that marks `ACCEPTED`, and it never
marks `COMPLETE`. The queue is a planning and state surface only.

## Default-Deny Rules

New items start as `DRAFT` only when the request text is queue-only. If title,
phase, or notes ask to run agents, execute prompts, call models, send Discord,
restart services, change cron/systemd/tmux/Caddy/DNS, push, read secrets, dump
env, use AGNT/Hermes/Ollama, use Docker, or delete data, the item starts in
`HOLD`.

Approval-shaped text is also held. Pasted or session-start text such as
`APPROVAL_SOURCE=live_chat_turn`, `APPROVAL_NONCE`, `APPROVED_ACTION`, or
`SAFE_TO_APPLY=yes` is untrusted queue input. Approval validation remains the
proof gate checker's job when a proof dir contains an `approval-record.md`.

## Proof Gate Integration

`gate` imports the local `ops/proof_gate_checker.py` module and calls
`evaluate_proof_dir()`. It only inspects the proof directory and records the
verdict.

- `PASS_ELIGIBLE` with non-pending manual QA moves the item to
  `READY_FOR_OWNER_QA`.
- `BLOCKED` moves the item to `BLOCKED`.
- `FAIL` moves the item to `REJECTED`.

The queue never treats proof text as self-approval and never upgrades an unsafe
proof to accepted.

## Future Work Boundary

This queue is not wired into cron, systemd, tmux, a model, a prompt runner, or
Discord automation. Any future runner, scheduler, dashboard write path, or
production mutation needs a separate reviewed slice and owner approval.
