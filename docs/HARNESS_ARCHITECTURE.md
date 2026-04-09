# Harness Architecture — SlimyAI

## Current Design (v2 / v3 planning stage)

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

### Current feature_list.json Lifecycle

1. Agent reads `/home/slimy/feature_list.json` at startup
2. Agent sorts by priority (critical > high > medium > low)
3. Agent picks first incomplete feature
4. Agent works on it, runs truth gate
5. Agent marks passes:true only after verified
6. End of session: agent updates live feature_list.json

Note: feature_list.json is a **live operational state file**, NOT a template.
It is NOT tracked in this git repo. Each NUC maintains its own.

### Prompt Library

- `auto-prompts.sh` — shell-executable prompt templates (AUTO-WORK, DIRECTED, FIX MODE, etc.)
- `auto-prompts.md` — markdown version of same prompts
- `PROMPT_TEMPLATES.md` — other prompt templates
- `HARNESS_GUIDE.md` — human-facing getting-started guide

### Build/Eval Separation

- **Build**: agent writes code, runs tests, updates feature_list.json
- **Eval**: separate QA run verifies passes:true claims before accepting
- QUALITY_CRITERIA.md defines the eval rubric

### How server-install.sh Currently Deploys

1. Copies server-level files from `harness-kit/server/` to `/home/slimy/`
2. Runs dynamic repo discovery to find repos
3. Copies per-repo harness files from `harness-kit/<repo>/` to each found repo
4. Rewrites `server-state.md` with discovered repo paths
5. Runs `init.sh` to verify

**Current limitation**: server-install.sh deploys from `harness-kit/` directory on disk,
not from a git repo. Changes to harness require manual copy into harness-kit.

---

## Planned Harness v3 Changes

### What Will Change

1. **Repo-based deployment**: server-install.sh will deploy FROM this git repo
   (`GurthBro0ks/slimy-harness`) instead of from local harness-kit/ directory

2. **Prompt P / C2 / PROJECT_NARRATIVE integration**:
   - PROJECT_NARRATIVE.md (when it exists) will be prepended at startup
   - C2-style contextual suggestions will be injected via auto-prompts
   - This is **planned, not yet implemented**

3. **Per-repo AGENTS.md discoverable**: Agent will find and read per-repo AGENTS.md
   automatically when `cd`-ing into a project (already happens via CLAUDE.md rules)

4. **Live state files excluded from git**:
   - feature_list.json, claude-progress.md, server-state.md stay on live system
   - Only templates are in git; actual values generated at install time

5. **Validation/dry-run mode**: server-install.sh will support `--dry-run` to preview
   what it would change without modifying live system

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
