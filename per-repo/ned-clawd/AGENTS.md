# Ned Clawd — Agent Operating Manual

You are an autonomous coding agent working in the Ned Clawd autonomous agent repo.

## Startup Sequence (do this EVERY session)

1. `pwd` — confirm you're in the repo root (`/home/slimy/ned-clawd`)
2. `cat CHANGELOG.md | head -50` — see recent changes
3. `git log --oneline -10` — see recent commits
4. Read in-repo `AGENTS.md` for ned-clawd-specific context
5. Pick the highest-priority task
6. Only THEN begin coding

## Repo Structure

- `actionbook/` — Actionbook integration (sub-repo)
- `comms/` — Communication/messaging code
- `content/` — Content management
- `docs/` — Documentation
- `ops/` — Operational databases (ops.db, decisions.db, triggers.db, knowledge.db)
- `proof/`, `proofs/` — Proof-of-work artifacts
- `skills/` — Agent skill definitions
- `tasks/` — Task management (taskboard.json)
- `tools/` — Utility tools (rejected, shared, staging)
- `venv/` — Python virtual environment
- `logs/` — Runtime logs

## Truth Gate

A feature is only "done" when:
1. Python files compile: `python3 -m py_compile <changed_file>`
2. Shell scripts pass: `bash -n <changed_script>`
3. Changes don't break existing ops databases or task state

## Forbidden Zones (DO NOT TOUCH)

- `.env*` files
- `ops/*.db` — operational databases, read-only unless explicitly asked
- `venv/` — Python virtualenv, never modify directly
- `proof/`, `proofs/` — generated artifacts
- `logs/` — runtime generated

## Work Rules

- ONE task per session. Complete it or document where you stopped.
- Ned Clawd is an autonomous agent system — be careful with skill and tool changes.
- Ops databases are critical state — never modify without explicit instruction.
- Small, surgical commits (`feat:`, `fix:`, `refactor:`).

## End-of-Session Checklist

1. Changed files compile/lint clean
2. `git add -A && git commit -m "<type>: <description>"`
3. Update `/home/slimy/claude-progress.md` with session summary

## Tech Stack Quick Reference

- Language: Python, Markdown
- Agent framework: Custom (skills/, tools/)
- State: SQLite databases in ops/
- Task management: tasks/taskboard.json
- Remote: `git@github.com:GurthBro0ks/ned-clawd.git`
- Branch: `master`
