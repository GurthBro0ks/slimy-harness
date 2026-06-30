# AGNT Clean-Room First Slice

This document records the Slimy-owned first slice inspired by the AGNT static review. It is implemented from Slimy requirements and proof artifacts only.

## Clean-Room Rule

Do not copy AGNT source, schemas, prompts, UI assets, CSS, auth code, Docker image internals, or plugin files. Do not run AGNT for this slice. The implementation reads Slimy proof reports and local Slimy proof directories only.

## Implemented

- `sequencer/trace-store.py` indexes safe local proof directories such as `/tmp/proof_*`, parses `RESULT.md` key/value fields when present, redacts secret-like patterns, and emits deterministic JSON when `--now` is supplied.
- `sequencer/goal-registry.py` appends explicit-reason JSONL goal state events and exports a compact read-only summary.
- Harness tests cover PASS/WARN/FAIL proof parsing, missing `RESULT.md`, redaction, deterministic output, required goal transition reasons, valid states, and rejection of `passes`.

## Intentionally Skipped

- No AGNT runtime test.
- No Docker usage.
- No public route.
- No write-capable control-plane API.
- No Discord notification.
- No auth, Caddy, DNS, cron, systemd, timer, tmux, SSH, firewall, nginx, or Cloudflare changes.
- No automatic `accepted` or `passes=true` claim.

## Run The Indexer

Write to an explicit proof/output path during validation:

```bash
python3 /home/slimy/slimy-harness/sequencer/trace-store.py \
  --root /tmp \
  --output /tmp/proof-index.json
```

The default output path is `/home/slimy/harness-logs/state/proof-index.json`.

## Record Goal State

Every state transition requires a reason:

```bash
python3 /home/slimy/slimy-harness/sequencer/goal-registry.py append \
  --goal-id agnt-cleanroom-first-slice \
  --state running \
  --reason "implementation started" \
  --proof-dir /tmp/proof_agnt_cleanroom_first_slice_example
```

Export a read-only summary:

```bash
python3 /home/slimy/slimy-harness/sequencer/goal-registry.py export \
  --output /tmp/goal-record-summary.json
```

## Validate Habitat Panel

The Habitat `/harness` page remains owner-gated by existing `getSession()` and `requireOwner()` logic in `gh-tracker`. It reads the generated proof index and goal record summary as metadata. It must not add mutation buttons or API routes.

Validation:

```bash
cd /opt/slimy/gh-tracker
pnpm test
pnpm run typecheck
pnpm run build
```

Manual QA remains pending until the owner opens the gated Habitat route and confirms the panel is read-only and secret-free.

## Avoid License Contamination

Use the prior proof reports as requirements input. If a future task needs AGNT runtime or source inspection, keep that work in a separate proof/evaluation phase and do not copy implementation details into Slimy repos.
