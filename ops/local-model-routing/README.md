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
