# SlimyAI Harness Source

**Repo:** https://github.com/GurthBro0ks/slimy-harness
**Status:** STAGING — harness source tracked in git, validated, not yet live

---

## What This Is

This repo holds the **source of truth** for the SlimyAI agent harness:
templates, install scripts, prompt libraries, and documentation.

It is the **staging ground for Harness v3** changes. Live operational
harness files remain at `/home/slimy/` and are NOT tracked here.

---

## Repository Structure

```
slimy-harness/
├── server-install.sh      # Main installer (repo-based, supports --dry-run and --commit)
├── install.sh             # Legacy per-repo installer (from harness-kit)
├── HARNESS_GUIDE.md       # Human-facing getting-started guide
├── PROMPT_TEMPLATES.md    # Prompt library
├── auto-prompts.sh        # Shell-executable startup prompts
├── scripts/
│   └── validate-harness.sh  # Pre-deployment validation
├── cheat-sheets/
│   ├── CHEAT_SHEET_FINAL.md
│   └── SERVER_CHEAT_SHEET.md
├── server/                # Server-level harness files (host-neutral)
│   ├── AGENTS.md          # Operating manual template (no hardcoded NUC1 paths)
│   ├── init.sh            # Repo discovery script
│   ├── QUALITY_CRITERIA.md
│   ├── auto-prompts.md
│   └── templates/        # BLANK templates for live state files
│       ├── claude-progress.md
│       ├── feature_list.json
│       ├── PROJECT_NARRATIVE.md
│       └── server-state.md
├── per-repo/             # Per-project harness (only for repos with templates)
│   ├── pm_updown_bot_bundle/
│   └── slimy-monorepo/
├── docs/
│   ├── HARNESS_ARCHITECTURE.md       # Current design + v3 plan
│   ├── REFERENCE_AGENTS_HOST_SPECIFIC.md  # NUC1-specific content (DO NOT COPY)
│   ├── CURRENT_LAYOUT_FINDINGS.md    # What existed and where
│   └── CUTOVER_NOTES.md             # Cutover log
└── compat/
    └── harness-kit-server-install-wrapper.sh  # Future cutover helper
```

---

## Deployment

### Current State (staging)

Live harness still lives at `/home/slimy/harness-kit/` on NUC1.
This repo is the **staging version** — validated via `--dry-run`, not active.

### How to Deploy (after cutover)

```bash
# Clone this repo (if not already)
git clone https://github.com/GurthBro0ks/slimy-harness.git /home/slimy/slimy-harness

# Preview what would be installed (zero writes — always safe)
bash /home/slimy/slimy-harness/server-install.sh --dry-run

# Actually install (only creates missing files, never overwrites)
bash /home/slimy/slimy-harness/server-install.sh

# Optional: also git commit in each target repo after installing
bash /home/slimy/slimy-harness/server-install.sh --commit
# Note: --commit has NO EFFECT during --dry-run (it is ignored when --dry-run is active)
```

### Flags

| Flag | Effect |
|------|--------|
| `--dry-run` | Preview only, no writes, no side effects |
| `--commit` | After installing, git commit in each target repo |

### What Gets Installed

| File | Installed To | Condition |
|------|-------------|-----------|
| AGENTS.md, init.sh, QUALITY_CRITERIA.md | `/home/slimy/` | Only if missing |
| claude-progress.md, feature_list.json, server-state.md | `/home/slimy/` | Only if missing (from templates) |
| PROJECT_NARRATIVE.md | `/home/slimy/` | Only if missing |
| Per-repo harness | each repo with matching template | Only if missing |

**Live state files are NEVER overwritten.** If a file already exists,
the installer skips it and reports "already exists". This is intentional.

### Validation

```bash
bash scripts/validate-harness.sh
```

Checks: shell syntax, dry-run zero-write, docs vs installer consistency,
required files exist, AGENTS.md host-neutrality.

---

## Host-Neutrality

`server/AGENTS.md` is a **host-neutral template**. It does not contain:
- Hardcoded hostnames (e.g., slimy-nuc1)
- Real NUC-specific paths (e.g., /opt/slimy/slimy-monorepo)

NUC-specific operational details are isolated in:
`docs/REFERENCE_AGENTS_HOST_SPECIFIC.md`

**DO NOT** copy content from that reference file onto other NUCs.

---

## Per-Repo Harness Scope

The installer dynamically discovers all git repos under `$HOME_DIR`, but
only installs harness for repos that have a matching template under `per-repo/`.

**Supported:** slimy-monorepo, pm_updown_bot_bundle
**Not yet supported:** mission-control, clawd, kb, ned-clawd, and others
(adding support: create `per-repo/<name>/` with AGENTS.md and init.sh)

---

## Templates vs Live State

| File | Live at `/home/slimy/` | Tracked in Git |
|------|------------------------|----------------|
| AGENTS.md | ✅ YES | ✅ (template) |
| init.sh | ✅ YES | ✅ (template) |
| QUALITY_CRITERIA.md | ✅ YES | ✅ (template) |
| claude-progress.md | ✅ LIVE DATA | ❌ NO — use template |
| feature_list.json | ✅ LIVE DATA | ❌ NO — use template |
| server-state.md | ✅ LIVE DATA | ❌ NO — use template |
| PROJECT_NARRATIVE.md | ❌ (planned) | ✅ (placeholder) |

---

## Harness v3 Status

| Feature | Status |
|---------|--------|
| Repo-based deployment | ✅ Done |
| --dry-run zero-write | ✅ Done |
| --commit flag | ✅ Done |
| Never-overwrite-live-state | ✅ Done |
| Dynamic per-repo discovery | ✅ Done |
| Host-neutral AGENTS.md | ✅ Done |
| Validation script | ✅ Done |
| Prompt P / PROJECT_NARRATIVE | ⏳ Planned |
| mission-control harness template | ⏳ Not yet |
