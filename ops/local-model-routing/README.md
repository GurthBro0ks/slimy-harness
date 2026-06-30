# Local Model Routing Policy

Read-only tooling for the local model routing policy.

Policy file:

```bash
config/local-model-routing.policy.json
```

Run the validator:

```bash
bash ops/local-model-routing/validate-policy.sh
```

The validator is read-only. It does not call Ollama, pull models, make network calls, or enable live routing.

Safety invariants:

- qwen2.5:1.5b is tiny helper only and advisory only.
- qwen3:4b is disabled for hot-path use.
- NUC2 is report/relay only and must not perform hot-path inference.
- Hermes remains disabled until identified.
- Harness QA and operator QA remain the source of truth.
- No local model may handle secrets, Discord webhooks, production edits, Caddy/DNS/systemd/cron/tmux changes, database migrations, or final QA.

Phase 3 may add a dry-run route helper later. That is not implemented here.

## Phase 3 — Dry-Run Route Helper

A read-only, policy-only decision helper is available:

```bash
python3 ops/local-model-routing/dry-run-route.py \
  --task route_hint \
  --risk LOW \
  --touches none \
  --machine nuc1
```

Supported options:

- `--policy`: defaults to `config/local-model-routing.policy.json`
- `--task`: required task name
- `--risk`: `LOW` (default), `MEDIUM`, or `HIGH`
- `--touches`: comma-separated surface list (e.g. `secrets,caddy`)
- `--machine`: `nuc1` (default) or `nuc2`
- `--json`: emit JSON output

Always prints:

- `DRY_RUN_ONLY=yes`
- `LIVE_ROUTING_ENABLED=no`
- `OLLAMA_CALLED=no`
- `MODELS_PULLED=no`

Decision rules (deterministic, policy-only):

1. `risk=HIGH` -> deny.
2. Any `touches` value in `routingRules.protectedSurfaces.surfaces` -> deny.
3. `machine=nuc2` -> deny (NUC2 local inference is disabled).
4. Task in `machines.nuc1.ollama.allowedModels["qwen2.5:1.5b"].deniedTasks` -> deny.
5. Task in `allowedTinyHelperTasks` -> allow advisory routing to `nuc1:qwen2.5:1.5b`, max output 8 tokens, reason `tiny_helper_allowed`.
6. Task matches `routingRules.resultMdDraft` -> allow `batch_only` with `requires_review=yes`.
7. Otherwise deny by default.

Safety invariants:

- Does not call Ollama, pull models, or open network sockets.
- Uses only `argparse`, `json`, `pathlib`, `sys` from the standard library.
- Does not read `.env`, secrets, or Discord webhook URLs.
- Does not send Discord messages or modify runtime state.
- Does not touch goal-runner, auto-sequence, notifier, Caddy, DNS, cron, systemd, or tmux.

This helper is policy-only and read-only. It is not wired into goal-runner
or auto-sequence. Live routing remains disabled and requires operator QA.

## Phase 4 — Proof-Only Route Decision Recorder

A proof-only, audit-only wrapper that records routing decisions into a
proof directory is available:

```bash
bash ops/local-model-routing/record-route-decision.sh \
  --proof-dir "$PROOF/route-recording-samples/allow-route-hint" \
  --task route_hint \
  --risk LOW \
  --touches none \
  --machine nuc1
```

Supported options:

- `--proof-dir`: required; proof directory (created with mode 0700 if missing)
- `--policy`: defaults to `config/local-model-routing.policy.json`
- `--task`: required task name
- `--risk`: `LOW` (default), `MEDIUM`, or `HIGH`
- `--touches`: comma-separated surface list (e.g. `secrets,caddy`)
- `--machine`: `nuc1` (default) or `nuc2`
- `-h`, `--help`: show usage

The recorder runs the committed policy validator and the committed
dry-run helper, then writes the following proof artifacts into
`--proof-dir`:

- `route-decision.txt` — key/value decision output from the dry-run helper
- `route-decision.json` — JSON decision output from the dry-run helper
- `route-decision.env` — shell-safe `LOCAL_MODEL_*` key/value lines
- `route-decision-command.txt` — exact recorded command and metadata
- `route-decision-policy-validator.txt` — full validator stdout/stderr

The recorder is fail-closed. If the policy validator or the dry-run
helper fails, the recorder writes whatever proof artifacts it can and
exits non-zero so the caller can branch on the result.

Safety invariants (in addition to the Phase 3 invariants):

- Does not call Ollama, pull models, or open network sockets.
- Does not use `curl`, `wget`, `nc`, or `socat`.
- Refuses obviously dangerous `--proof-dir` targets such as `/etc`,
  `/`, `/bin`, `/sbin`, `/usr`, `/var`, `/root`, or `/boot`.
- Creates the proof directory with mode 0700 if it does not exist.
- Does not wire into goal-runner, auto-sequence, notifier, Caddy, DNS,
  cron, systemd, or tmux.
- Does not read `.env`, secrets, or Discord webhook URLs.
- Does not send Discord messages.

This recorder is proof-only and audit-only. It is not wired into
goal-runner or auto-sequence. Live routing remains disabled and
requires operator QA.

## Phase 5B — qwen2.5 Recovery Benchmark Tooling

Phase 5 produced a local-only NUC1 WARN commit (`16d0207`) and a
PM-recorded qwen2.5:1.5b micro-benchmark result, but the original
benchmark proof directory was not recovered after the outage. The
forensic record for that missing proof states:

- original Phase 5 proof directory: missing
- direct local benchmark proof recovered: no
- PM-recorded Phase 5 result: `WARN`
- PM-recorded benchmark verdict: `inconclusive`
- qwen2.5 decision: `do_not_wire_into_harness`

Phase 5B keeps qwen2.5 unavailable for harness routing and adds a
recovery benchmark helper that can create complete deferred proof
artifacts without calling Ollama:

```bash
bash ops/local-model-routing/benchmark-qwen25-tiny.sh \
  --proof-dir "$PROOF/benchmark" \
  --defer-model-run \
  --defer-reason "operator deferred real NUC1 benchmark"
```

Deferred mode must be used for recovery/operator QA that is not a real
NUC1 benchmark. It writes:

- `ollama-command.txt`
- `ollama-list.txt`
- `model-presence.txt`
- `benchmark-output.txt`
- `benchmark-summary.json`
- `benchmark-summary.txt`
- `benchmark-subset-summary.txt`
- `artifact-presence.txt`

Required deferred fields:

- `BENCHMARK_RUN=no`
- `BENCHMARK_VERDICT=deferred_until_nuc1_online`
- `QWEN25_RECOMMENDATION=none`
- `QWEN25_DECISION=do_not_wire_into_harness`
- `MODELS_PULLED=no`
- `OLLAMA_PULL_ATTEMPTED=no`
- `OLLAMA_CALLED=no`
- `LIVE_ROUTING_CHANGED=no`

The helper also preserves a manual real-run mode for a later NUC1 Phase
5B benchmark. That future run is proof-only, must be invoked directly by
an operator, and still does not accept qwen2.5 for harness routing by
itself. A separate operator QA decision is required before any future
local model routing change.

Safety invariants:

- Deferred mode does not call Ollama and does not pull models.
- The helper is not wired into goal-runner, auto-sequence, notifier,
  Caddy, DNS, cron, systemd, or tmux.
- No local model may handle secrets, Discord webhooks, production edits,
  database migrations, or final QA.
- qwen2.5 remains advisory/recovery-only and must not be wired into the
  harness.
