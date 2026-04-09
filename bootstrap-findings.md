# Bootstrap Findings — Slimy Harness v3 Source Repo

**Generated:** 2026-04-09
**Host:** slimy-nuc1

---

## What Exists Where

### Live Harness (currently active at `/home/slimy/`)

| File | Path | Copy to Repo? |
|------|------|---------------|
| AGENTS.md | /home/slimy/AGENTS.md | YES (source of truth, recently updated) |
| init.sh | /home/slimy/init.sh | YES (dynamic repo discovery, updated) |
| QUALITY_CRITERIA.md | /home/slimy/QUALITY_CRITERIA.md | YES |
| claude-progress.md | /home/slimy/claude-progress.md | NO — live operational state, DO NOT copy |
| feature_list.json | /home/slimy/feature_list.json | NO — live operational state, DO NOT copy |
| server-state.md | /home/slimy/server-state.md | NO — live operational state, DO NOT copy |
| PROJECT_NARRATIVE.md | /home/slimy/PROJECT_NARRATIVE.md | DOES NOT EXIST anywhere |
| sprint-contract.md | /home/slimy/sprint-contract.md | NO — ad-hoc session file |

### Harness Kit (source templates at `/home/slimy/harness-kit/`)

| Path | Type | Action |
|------|------|--------|
| /home/slimy/harness-kit/server-install.sh | file | YES — copy as-is to repo root |
| /home/slimy/harness-kit/install.sh | file | YES — copy as-is |
| /home/slimy/harness-kit/HARNESS_GUIDE.md | file | YES — copy as-is |
| /home/slimy/harness-kit/PROMPT_TEMPLATES.md | file | YES — copy as-is |
| /home/slimy/harness-kit/auto-prompts.sh | file | YES — copy as-is |
| /home/slimy/harness-kit/server/AGENTS.md | file | YES — but prefer live /home/slimy/AGENTS.md |
| /home/slimy/harness-kit/server/init.sh | file | YES — but prefer live /home/slimy/init.sh |
| /home/slimy/harness-kit/server/QUALITY_CRITERIA.md | file | YES — but prefer live /home/slimy/QUALITY_CRITERIA.md |
| /home/slimy/harness-kit/server/claude-progress.md | file | NO — template only (outdated session log) |
| /home/slimy/harness-kit/server/feature_list.json | file | NO — template only (outdated feature list) |
| /home/slimy/harness-kit/server/server-state.md | file | NO — template only |
| /home/slimy/harness-kit/server/auto-prompts.md | file | YES — copy as-is |
| /home/slimy/harness-kit/pm_updown_bot_bundle/ | dir | YES — per-repo harness |
| /home/slimy/harness-kit/slimy-monorepo/ | dir | YES — per-repo harness |
| /home/slimy/harness-kit/{slimy-monorepo,pm_updown_bot_bundle,shared}/ | dir | EMPTY — ignore |

---

## Key Observations

1. **Two AGENTS.md files differ**: Live `/home/slimy/AGENTS.md` has the **expanded project map** (9 projects vs 3 in harness-kit/server/AGENTS.md). Live version is more current. Use live as source.

2. **Two init.sh files differ**: Live `/home/slimy/init.sh` uses **dynamic repo discovery** (`find /home/slimy -maxdepth 4 -name ".git"`) vs harness-kit/server/init.sh which hardcodes 3 repos. Live is more evolved. Use live as source.

3. **Live harness-kit has expanded project map**: slimy-monorepo symlinked at `/home/slimy/slimy-monorepo` → `/opt/slimy/slimy-monorepo`. clawd, mission-control, mailbox_ingest, etc. all present.

4. **PROJECT_NARRATIVE.md does not exist** — this is a planned v3 feature that was never created.

5. **server-install.sh** copies from `harness-kit/server/*` to `/home/slimy/`, not from a git repo. This is the install mechanism to refactor toward.

6. **No per-repo harness for mission-control** in harness-kit — only slimy-monorepo and pm_updown_bot_bundle have per-repo harness files.

7. **Live server-state.md is more complete** than the harness-kit template — the live version already has killer services documented.

---

## Strategy

- Use **live `/home/slimy/` files** as primary source for server-level files (they are more current)
- Use **harness-kit** as source for per-repo templates (those haven't changed)
- **Do not copy live state files** (claude-progress.md, feature_list.json, server-state.md)
- **Create templates** for live state files (blank placeholders with TODO)
- **PROJECT_NARRATIVE.md**: create as blank template only
- **server-install.sh**: refactor to deploy FROM this git repo instead of from harness-kit/
