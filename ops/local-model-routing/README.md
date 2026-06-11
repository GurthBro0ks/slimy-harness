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
