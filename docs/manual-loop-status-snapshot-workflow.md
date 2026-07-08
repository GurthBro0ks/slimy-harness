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

Also run a forbidden-content scan over the `/tmp` output before treating it as
safe to review further:

```bash
rg -n "raw proof|command output|approval statement|env value|webhook URL|Bearer|BOT_SYNC_SECRET|cron line|SECRET|TOKEN|PASSWORD|PRIVATE KEY" \
  /tmp/loop-status-latest-smoke.json || true
```

Any match must be classified before proceeding — `target_machine`,
`target_repo`, and `proof_dir` are expected `loop-status.v1` schema fields,
not raw proof content, but any of the other terms above appearing with a
real value (not empty string) means stop and do not proceed to a canonical
write.

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

## Future Refresh Checklist

Use this checklist for any later manual-only refresh of the existing canonical
`latest.json` file. A refresh is still a production-visible canonical rewrite,
not routine maintenance, and there is no automation approved for it.

- Get fresh live operator approval for the exact refresh. Include the reviewed
  queue path, target machine, target repo, and the no-automation constraints.
- Capture current canonical metadata before changing anything:

  ```bash
  stat /home/slimy/harness-logs/loop-status-snapshot/latest.json
  ```

- Use one explicit, reviewed temporary/operator queue for that refresh. Do not
  infer, create, or use a default production queue path, autonomous discovery,
  or generated placeholder items.
- Validate the queue and run any proof-gate enrichment against real proof
  directories. Keep truthful `BLOCKED` results when proof gates block; do not
  force a green-looking snapshot.
- Run the `/tmp` dry-run and real `/tmp` write from the validation section
  above, then re-run JSON parse, schema, safety-flag, item/status summary, and
  forbidden-content checks on the `/tmp` output.
- Only after the `/tmp` gates pass, run the canonical write once with
  `--confirm-canonical-latest`.
- Revalidate the canonical file after the write: JSON parse, `loop-status.v1`
  schema, safety flags, item/status summary, and forbidden-content scan. Capture
  the after-write `stat` output and compare it with the before-write metadata.
- Complete owner browser and mobile QA every time: confirm snapshot mode,
  counts, badges, stale/fresh wording, safety summary, absence of raw
  proof/secret/mutation content, and logged-out redirect to `/login`.
- Record accepted state and proof for the refresh after validation and QA are
  complete.
- Rollback requires separate fresh live approval. Restore a reviewed known-good
  snapshot through this helper, or remove only `latest.json` to return to
  fixture fallback.
- Keep refreshes manual and one-time. Do not add cron, systemd timers, tmux
  loops, request-time shell, queue watchers, Discord triggers, model execution,
  Caddy/DNS changes, or service restarts.

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

## Rollback

Rolling back a canonical write requires the same standard as making one:
fresh live operator approval before acting, obtained separately from the
approval that authorized the original write.

- To return the dashboard to fixture-fallback mode, remove the canonical
  file only (`/home/slimy/harness-logs/loop-status-snapshot/latest.json`);
  do not remove the parent directory unless it is empty and no longer
  needed.
- If a prior known-good snapshot was preserved outside the canonical path
  (e.g. copied to `/tmp` or another explicit path before being overwritten),
  restore from that copy with the same `--out` + `--confirm-canonical-latest`
  workflow described above rather than hand-editing the canonical file.
- After any rollback, repeat the Manual QA checklist below to confirm the
  dashboard renders the expected state (fixture-fallback or restored
  snapshot) and that logged-out access still redirects to `/login`.
- Do not delete or replace the canonical file as part of routine
  troubleshooting without that separate live approval — treat removal the
  same as a write for approval purposes.

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
