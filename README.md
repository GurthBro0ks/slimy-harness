# SlimyAI Harness Source

**Repo:** https://github.com/GurthBro0ks/slimy-harness
**Status:** STAGING — harness source tracked in git, not yet live installer

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
├── server-install.sh      # Main installer (repo-based, supports --dry-run)
├── install.sh             # Legacy per-repo installer (from harness-kit)
├── HARNESS_GUIDE.md       # Human-facing getting-started guide
├── PROMPT_TEMPLATES.md    # Prompt library
├── auto-prompts.sh        # Shell-executable startup prompts
├── cheat-sheets/          # Quick reference docs
│   ├── CHEAT_SHEET_FINAL.md
│   └── SERVER_CHEAT_SHEET.md
├── server/                # Server-level harness files
│   ├── AGENTS.md          # Operating manual template
│   ├── init.sh            # Repo discovery script
│   ├── QUALITY_CRITERIA.md
│   ├── auto-prompts.md
│   └── templates/        # BLANK templates for live state files
│       ├── claude-progress.md
│       ├── feature_list.json
│       ├── PROJECT_NARRATIVE.md
│       └── server-state.md
├── per-repo/             # Per-project harness templates
│   ├── pm_updown_bot_bundle/
│   └── slimy-monorepo/
├── docs/
│   ├── HARNESS_ARCHITECTURE.md   # Current design + v3 plan
│   ├── CURRENT_LAYOUT_FINDINGS.md # What existed and where
│   └── CUTOVER_NOTES.md         # Cutover log (after each run)
└── compat/
    └── harness-kit-server-install-wrapper.sh  # Future cutover helper
```

---

## Deployment

### Current State (v2 / staging)

Live harness still lives at `/home/slimy/harness-kit/` on NUC1.
This repo is the **staging version** — tested via `--dry-run`, not active.

### How to Deploy (after cutover)

```bash
# Clone this repo (if not already)
git clone https://github.com/GurthBro0ks/slimy-harness.git /home/slimy/slimy-harness

# Preview what would be installed (no writes)
bash /home/slimy/slimy-harness/server-install.sh --dry-run

# Actually install (only writes to non-existent paths)
bash /home/slimy/slimy-harness/server-install.sh
```

### What Gets Installed

| File | Installed To | Notes |
|------|-------------|-------|
| AGENTS.md, init.sh, QUALITY_CRITERIA.md | `/home/slimy/` | Only if missing |
| claude-progress.md, feature_list.json, server-state.md | `/home/slimy/` | From **blank templates** — never overwrites live |
| PROJECT_NARRATIVE.md | `/home/slimy/` | Only if missing |
| Per-repo AGENTS.md, init.sh | each repo root | Only if missing |

**Live state files are NEVER overwritten.** If a file already exists at the
destination, the installer skips it. This is intentional — you keep your
live operational data.

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

The live files contain operational data specific to each NUC. They must NOT
be copied into this repo or overwritten during install.

---

## Harness v3 Roadmap

See [docs/HARNESS_ARCHITECTURE.md](docs/HARNESS_ARCHITECTURE.md) for the full
plan. Key changes coming:

- [ ] `server-install.sh` deploys from this git repo instead of local harness-kit/
- [ ] Prompt P / C2 / PROJECT_NARRATIVE startup integration
- [ ] `--dry-run` mode (done ✅)
- [ ] Per-repo harness discovery for all slimyai repos (not just 3 hardcoded)
- [ ] Live cutover via `compat/harness-kit-server-install-wrapper.sh`

---

## Relationship to Other Repos

This repo does NOT contain project source code. It only contains the harness
that agents use to work on projects.

- **slimy-monorepo**: Next.js web app, admin API, admin UI, slimy-auth
- **pm_updown_bot_bundle**: Polymarket trading bot
- **mission-control**: Task tracking
- **clawd**: OpenCLAW integration
- **kb/**: Knowledge base (wiki + raw docs)

Each of those repos has its own git history and is NOT affected by changes
to this harness repo.

---

## NO LIVE CUTOVER IN THIS SESSION

As of 2026-04-09: this repo has been scaffolded and dry-run validated, but
the live harness at `/home/slimy/harness-kit/` has NOT been replaced.

Run `bash server-install.sh --dry-run` to see what would happen.

To perform live cutover (requires explicit authorization):
```bash
# Backup existing harness
cp -r /home/slimy/harness-kit /home/slimy/harness-kit.bak

# Swap in the new installer
cp /home/slimy/slimy-harness/compat/harness-kit-server-install-wrapper.sh \
   /home/slimy/harness-kit/server-install.sh
```
