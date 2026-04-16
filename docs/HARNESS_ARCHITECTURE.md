# Harness Architecture — SlimyAI

## Current Design (v3 staging)

### The TOP/BOTTOM Wrapper Pattern

The harness operates in two layers:

```
┌─────────────────────────────────────────────────┐
│  TOP LAYER — Agent Startup Prompts              │
│  auto-prompts.sh / auto-prompts.md             │
│  Describes what to read and do before coding  │
└─────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────┐
│  MIDDLE LAYER — Server-Level Harness Files     │
│  /home/slimy/AGENTS.md  (operating manual)      │
│  /home/slimy/init.sh    (repo discovery)        │
│  /home/slimy/QUALITY_CRITERIA.md               │
│  /home/slimy/feature_list.json (live state)     │
│  /home/slimy/claude-progress.md (live state)    │
│  /home/slimy/server-state.md (live state)       │
└─────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────┐
│  BOTTOM LAYER — Per-Repo Harness Files         │
│  [repo]/AGENTS.md  (project-specific rules)    │
│  [repo]/init.sh    (env setup + truth gate)    │
│  [repo]/feature_list.json                      │
│  [repo]/claude-progress.md                     │
└─────────────────────────────────────────────────┘
```

### Server-Level vs Repo-Level Files

**Server-level** (`/home/slimy/`):
- AGENTS.md — project map, startup sequence, end-of-session rules
- init.sh — dynamic repo discovery (finds all `.git` dirs under `/home/slimy`)
- QUALITY_CRITERIA.md — how QA grading works
- feature_list.json — master feature list (live operational data)
- claude-progress.md — session history (live operational data)
- server-state.md — services, ports, repo paths (live operational data)

**Repo-level** (inside each repo):
- AGENTS.md — project-specific rules (truth gate, forbidden zones)
- init.sh — language-specific env setup + truth gate invocation
- feature_list.json — project-specific feature tracking
- claude-progress.md — per-project session history

### Dynamic Repo Discovery

`init.sh` does NOT hardcode repo paths. Instead it runs:
```bash
find /home/slimy -maxdepth 4 -name ".git" -type d 2>/dev/null
```
This finds all git repos dynamically and exports them as `REPO_<name>` env vars.
The agent picks which repo to work in based on feature_list.json priority.

### server-install.sh Installer Behavior

**Usage:**
```bash
bash slimy-harness/server-install.sh [--dry-run] [--commit]
```

**What it does:**
1. Discovers all git repos under `$HOME_DIR` dynamically
2. For each discovered repo that has a matching template under `per-repo/<name>/`, installs harness files — but ONLY for files that don't already exist in the target
3. Installs server-level harness files (AGENTS.md, init.sh, QUALITY_CRITERIA.md) — but ONLY if missing
4. Creates live-state templates (claude-progress.md, feature_list.json, server-state.md, PROJECT_NARRATIVE.md) — but ONLY if missing
5. Creates server-state.md with discovered repo paths — but ONLY if missing
6. Optionally runs `init.sh` to verify (in non-dry-run mode)

**Key safety properties:**
- **Never overwrites existing files**: every file installation is skipped if the destination already exists
- **Zero side effects in dry-run**: no chmod, no cp, no git operations during `--dry-run`
- **No auto-commit by default**: `--commit` flag required to git commit in target repos

**What it does NOT do:**
- Does NOT deploy from a local harness-kit/ directory
- Does NOT hardcode a fixed list of repos
- Does NOT auto-commit without explicit `--commit`
- Does NOT copy live operational state files into git

### Per-Repo Harness Scope

The installer dynamically discovers repos but only installs harness for repos
that have a matching template under `per-repo/` in this git repo.

**Repos with harness templates:**
- `per-repo/slimy-monorepo/`
- `per-repo/pm_updown_bot_bundle/`

**Repos without harness templates (installer skips gracefully):**
- mission-control, clawd, kb, ned-clawd, etc.
- Add new templates under `per-repo/<name>/` to extend coverage.

### Prompt Library

- `auto-prompts.sh` — shell-executable prompt templates (AUTO-WORK, DIRECTED, FIX MODE, etc.)
- `auto-prompts.md` — markdown version of same prompts
- `PROMPT_TEMPLATES.md` — other prompt templates
- `HARNESS_GUIDE.md` — human-facing getting-started guide

### Build/Eval Separation

- **Build**: agent writes code, runs tests, updates feature_list.json
- **Eval**: separate QA run verifies passes:true claims before accepting
- QUALITY_CRITERIA.md defines the eval rubric

### Host-Neutrality

The `server/AGENTS.md` is a **host-neutral template**. It contains:
- Universal startup sequence, work rules, end-of-session checklist
- Placeholder tables for host-specific content (project map, dead services, infrastructure)

NUC1-specific operational details are isolated in `docs/REFERENCE_AGENTS_HOST_SPECIFIC.md`.
Do NOT copy host-specific content from that file onto other NUCs.

---

## Planned / In-Progress

### Done (v3 staging)
- ✅ Repo-based deployment from `GurthBro0ks/slimy-harness` git repo
- ✅ `--dry-run` mode: zero-write preview
- ✅ `--commit` flag: explicit opt-in for git auto-commit
- ✅ Never-overwrite-live-state: all installs skip existing files
- ✅ Dynamic per-repo discovery: scans `per-repo/` directory for templates
- ✅ Host-neutral `server/AGENTS.md`: no hardcoded NUC1 paths
- ✅ Validation script: `scripts/validate-harness.sh`
- ✅ PROJECT_NARRATIVE workflow: template + live host narrative
- ✅ feature_list.json v3 schema: risk + plan[] fields
- ✅ Prompt P (plan-first work mode): risk classification + bounded plan before coding
- ✅ Prompt C2 (systematic fix/debug mode): phased root-cause debugging, fail-closed
- ✅ Formal verification gate: prove-it shutdown behavior, evidence required
- ✅ Startup/shutdown guidance: explicit v3 source files listed
- ✅ Doc-sync allowlist (`kb/config/doc-sync-allowlist.txt`): only listed repos get auto-sync
- ✅ Dirty-tree skip: repos with non-doc dirty files are skipped by doc-sync
- ✅ Non-pushable skip: repos with no remote origin are skipped for commit/push

### What Stays the Same
- TOP/BOTTOM wrapper pattern (auto-prompts → server-level → repo-level)
- init.sh dynamic discovery mechanism
- Truth gate per project
- One feature per session rule
- Knowledge base integration (kb/)

### What is NOT in This Repo

- No actual project source code (monorepo, bot, etc.)
- No secrets, tokens, API keys, .env files
- No live operational data (progress, features, state)
- No build artifacts or logs
