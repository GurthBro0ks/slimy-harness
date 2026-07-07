# Manual Loop Status Snapshot Workflow

This workflow publishes a sanitized `loop-status.v1` snapshot for the accepted
Habitat `/harness/loop` read-only dashboard. It is manual-only and operator
invoked.

## Scope

- Reads one explicit local queue JSON file.
- Optionally reads proof-gate summaries under one explicit proof root.
- Writes one explicit snapshot JSON output.
- Does not run agents, prompts, models, network calls, Discord, services, cron,
  systemd timers, tmux sessions, Caddy, DNS, or queue/proof mutation controls.
- Does not change the Habitat UI.

The Habitat UI expects:

```text
/home/slimy/harness-logs/loop-status-snapshot/latest.json
```

When the file is absent, the UI safely remains in fixture fallback mode.

## Validate First With /tmp

Use a temporary output path before any canonical write:

```bash
cd /home/slimy/slimy-harness
ops/loop-status-export-latest \
  --queue /path/to/reviewed/manual-queue.json \
  --out /tmp/loop-status-latest-smoke.json \
  --dry-run

ops/loop-status-export-latest \
  --queue /path/to/reviewed/manual-queue.json \
  --out /tmp/loop-status-latest-smoke.json
```

Optional proof-gate enrichment remains explicit:

```bash
ops/loop-status-export-latest \
  --queue /path/to/reviewed/manual-queue.json \
  --proof-root /tmp \
  --out /tmp/loop-status-latest-smoke.json
```

Then validate:

```bash
python3 -m json.tool /tmp/loop-status-latest-smoke.json >/dev/null
python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path("/tmp/loop-status-latest-smoke.json").read_text())
assert data["schema_version"] == "loop-status.v1"
assert data["safety"]["shell_execution_present"] is False
assert data["safety"]["mutation_controls_present"] is False
assert data["safety"]["request_time_shell_required"] is False
assert data["safety"]["secrets_redacted"] is True
assert data["safety"]["owner_gate_required_for_ui"] is True
PY
```

## Canonical Manual Write

Only after fresh live operator approval for a canonical write:

```bash
cd /home/slimy/slimy-harness
ops/loop-status-export-latest \
  --queue /path/to/reviewed/manual-queue.json \
  --confirm-canonical-latest
```

The helper creates `/home/slimy/harness-logs/loop-status-snapshot` only when it
is explicitly invoked for a real write with `--confirm-canonical-latest`,
refuses symlink output parents, and delegates atomic temp-file replacement to
`ops/loop-status-export`. The default canonical output path is refused without
that confirmation flag.

## Manual QA

After a separately approved canonical write:

- Log in as owner.
- Open `https://habitat.slimyai.xyz/harness/loop`.
- Confirm snapshot mode renders instead of fixture-only mode.
- Confirm summary counts and item cards render.
- Confirm badges for relevant states render.
- Confirm safety summary shows no shell execution, no mutation controls, no
  request-time shell, and secrets redacted.
- Confirm no raw proof text, command output, approval statement, env value,
  token, webhook URL, cron line, `target_machine`, `target_repo`, `proof_dir`,
  forms, buttons, or mutation controls are visible.
- Confirm logged-out `/harness/loop` still redirects to `/login`.

## No-Go List

- No cron.
- No systemd timer.
- No tmux automation.
- No Discord.
- No service restart.
- No request-time shell.
- No queue/proof mutation controls from the Habitat UI.
- No raw proof text.
- No secrets.
- No AGNT/Hermes/Ollama/model execution.
