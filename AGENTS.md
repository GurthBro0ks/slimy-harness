# Slimy Harness — Agent Operating Manual

You are an autonomous coding agent working in the SlimyAI harness infrastructure repo.

## Startup Sequence (do this EVERY session)

1. `pwd` — confirm you're in the repo root (`/home/slimy/slimy-harness`)
2. `git log --oneline -10` — see recent commits
3. `bash scripts/validate-harness.sh` — verify harness integrity
4. Read `README.md` for current scope and status
5. Pick the highest-priority task
6. Only THEN begin coding

## Repo Structure

- `server/` — Server-level templates (AGENTS.md, init.sh, etc.)
- `per-repo/` — Per-repo AGENTS.md and init.sh templates
- `scripts/` — Validation and sync scripts
- `docs/` — Harness documentation, triage reports
- `cheat-sheets/` — Quick reference for agents
- `compat/` — Compatibility layers
- `proofs/` — Harness deployment proofs
- `server-install.sh` — Main installer script
- `VERSION.md` — Harness version tracking

## Truth Gate

A change is only "done" when:
1. `bash scripts/validate-harness.sh` passes (all checks green)
2. `bash -n` passes on any new/modified shell scripts
3. `bash server-install.sh --dry-run` shows expected behavior

## Forbidden Zones (DO NOT TOUCH)

- Never modify live state files at `/home/slimy/` from a harness session (that's the installer's job)
- `proofs/` — generated, never hand-edit
- Do not run `server-install.sh --commit` unless explicitly told to

## Work Rules

- ONE task per session. Complete it or document where you stopped.
- Small, surgical commits (`feat:`, `fix:`, `refactor:`).
- Always run `bash scripts/validate-harness.sh` before committing.
- When adding per-repo templates, follow existing conventions in `per-repo/slimy-monorepo/` and `per-repo/mission-control/`.

## End-of-Session Checklist

1. `bash scripts/validate-harness.sh` passes
2. New scripts pass `bash -n`
3. `git add -A && git commit -m "<type>: <description>"`
4. Update `/home/slimy/claude-progress.md` with session summary

## Tech Stack Quick Reference

- Language: Bash (shell scripts), Markdown (templates)
- Validation: `scripts/validate-harness.sh`
- Installer: `server-install.sh` (template deployment)
- No runtime dependencies beyond standard Unix tools
