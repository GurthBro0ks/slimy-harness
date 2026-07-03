# Loop Status Snapshot Exporter

`ops/loop-status-export` produces a sanitized static JSON snapshot for a
future read-only Habitat loop dashboard. It is owned by Slimy Harness and is
manual-only in this phase.

The exporter does not run agents, execute prompts, call models, call the
network, send Discord, restart services, change cron/systemd/tmux/Caddy/DNS,
read `.env`, mutate production, or wire itself into automation. It reads an
explicit queue file and writes only the explicit `--out` path.

## Usage

```bash
ops/loop-status-export --help
ops/loop-status-export --queue /tmp/queue.json --out /tmp/loop-status.json
ops/loop-status-export --queue /tmp/queue.json --out /tmp/loop-status.json --proof-root /tmp
```

`--proof-root` is optional. When supplied, an item's `proof_dir` is inspected
only if it resolves under that explicit root. Proof inspection uses the local
`proof_gate_checker.evaluate_proof_dir()` helper and exports only counts,
verdicts, and next-gate labels. Raw proof text and command output are never
included in the snapshot.

## Schema

The frozen Phase 1 schema is `loop-status.v1`.

Top-level fields:

- `schema_version`
- `generated_at`
- `generator`
- `source.queue_path`
- `source.proof_root`
- `summary`
- `items`
- `safety`
- `errors`
- `warnings`

`summary` contains:

- `total_items`
- `by_status`
- `by_gate`
- `highest_risk_state`
- `has_blockers`
- `has_failures`
- `stale_count`

Each item contains only:

- `id`
- `phase`
- `title`
- `target_machine`
- `target_repo`
- `model_recommendation`
- `glm_thinking_level`
- `status`
- `safety_level`
- `proof_dir`
- `proof_gate_verdict`
- `manual_qa_status`
- `next_required_gate`
- `blocked_reason`
- `updated_at`
- `warnings_count`
- `reasons_count`

The `safety` object always reports:

- `shell_execution_present: false`
- `mutation_controls_present: false`
- `request_time_shell_required: false`
- `secrets_redacted: true`
- `owner_gate_required_for_ui: true`

## Display States

The exported item `status` is one of five frozen display states:

- `OK`
- `WARN`
- `BLOCKED`
- `FAIL`
- `UNKNOWN`

Queue `HOLD` and proof `BLOCKED` become `BLOCKED`. Queue `REJECTED` and proof
`FAIL` become `FAIL`. Ready states become `OK` only when they are not
contradicted by the proof gate. Invalid or missing data becomes `UNKNOWN`.

## Sanitization

The snapshot excludes raw notes, history, proof text, command output, approval
statements, tokens, secret/env values, webhook URLs, raw cron lines, tracebacks,
mutation controls, and action URLs. Allowed scalar fields are bounded and
redacted if they contain secret-like markers.

Missing or invalid queues do not crash the exporter. They produce a static
snapshot with `highest_risk_state: UNKNOWN`, `has_blockers: true`, and a
sanitized error entry.

## Phase Boundary

This phase intentionally does not touch Habitat or GH Tracker UI files. A
later Phase 2 may consume this static JSON from an owner-gated read-only view
after separate review and approval.
