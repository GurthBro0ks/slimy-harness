# Clawd — Agent Operating Manual

You are an autonomous coding agent working in the Clawd personal assistant / code aggregator repo.

## Startup Sequence (do this EVERY session)

1. `pwd` — confirm you're in the repo root (`/home/slimy/clawd`)
2. `cat CHANGELOG.md | head -50` — see recent changes
3. `git log --oneline -10` — see recent commits
4. Read `AGENTS.md` (in-repo) for clawd-specific context
5. Pick the highest-priority task
6. Only THEN begin coding

## Repo Structure

- `agents/` — Agent definitions and configurations
- `apps/` — Application sub-projects (web app, etc.)
- `canvas/` — Canvas/visualization code
- `config/` — Configuration files (`agents.yaml`)
- `docs/` — Documentation
- `logs/` — Runtime logs (gitignored)
- `memory/` — Agent memory/state
- `ops/` — Operational scripts
- `proof/` — Proof-of-work artifacts
- `scripts/` — Utility scripts (cleanup, git helpers, executors)
- `skills/` — Agent skill definitions
- `memory/`, `ops/` — State and operational data

## Truth Gate

A feature is only "done" when:
1. No Python syntax errors: `python3 -m py_compile <changed_file>`
2. Shell scripts pass: `bash -n <changed_script>`
3. Changes are coherent with existing agent configuration

## Forbidden Zones (DO NOT TOUCH)

- `.env*` files
- `logs/` — runtime generated, never edit
- `memory/` — agent state, read-only unless explicitly asked to modify
- `proof/` — generated artifacts
- Any wallet/key/seed/mnemonic material

## Work Rules

- ONE task per session. Complete it or document where you stopped.
- Clawd is a personal assistant system — be careful with agent configs and skills.
- Changes to `agents.yaml` or skill definitions require extra scrutiny.
- Small, surgical commits (`feat:`, `fix:`, `refactor:`).

## End-of-Session Checklist

1. Changed files compile/lint clean
2. `git add -A && git commit -m "<type>: <description>"`
3. Update `/home/slimy/claude-progress.md` with session summary

## Tech Stack Quick Reference

- Language: Python, Markdown, YAML
- Agent framework: Custom (agents/, skills/)
- Web: apps/web (if present)
- Config: agents.yaml
- Remote: `git@github.com:GurthBro0ks/clawd.git`
- Branch: `main` (NUC2 is primary, NUC1 is mirror)
