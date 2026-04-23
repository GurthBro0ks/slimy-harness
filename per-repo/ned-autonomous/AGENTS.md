# Ned Autonomous — Agent Operating Manual

You are an autonomous coding agent working in the Ned Autonomous agent orchestrator repo.

## Startup Sequence (do this EVERY session)

1. `pwd` — confirm you're in the repo root (`/home/slimy/ned-autonomous`)
2. `cat CHANGELOG.md | head -50` — see recent changes
3. `git log --oneline -10` — see recent commits
4. Pick the highest-priority task
5. Only THEN begin coding

## Repo Structure

- `scripts/` — Core orchestrator scripts
  - `agent-loop.py` — Main 30-second heartbeat loop
  - `task-router.py` — Skill-based task routing
  - `task-prioritizer.py` — PageRank-based prioritization
  - `agent-health.py` — Health monitoring
  - `anomaly-detector.py` — Anomaly detection
  - `federation-router.py` — NUC1 ↔ NUC2 federation
  - `trading-gate.py` — Trading safety gate
  - `tool-creator.py`, `tool-review.py` — Tool management
- `config/` — Configuration files (agents.yaml, federation.json, loop-policy.json)
- `docs/` — Documentation

## Truth Gate

A feature is only "done" when:
1. Python files compile: `python3 -m py_compile <changed_file>`
2. Shell scripts pass: `bash -n <changed_script>`
3. No regressions in existing orchestration scripts

## Forbidden Zones (DO NOT TOUCH)

- `.env*` files
- `config/` — read-only unless explicitly asked to modify
- Any running agent processes (PM2 managed)

## Work Rules

- ONE task per session. Complete it or document where you stopped.
- Ned Autonomous is STALE (last commit Apr 7, no active services). Changes are for future use.
- Be cautious with orchestration scripts — they affect system-wide agent behavior.
- Small, surgical commits (`feat:`, `fix:`, `refactor:`).

## End-of-Session Checklist

1. Changed files compile/lint clean
2. `git add -A && git commit -m "<type>: <description>"`
3. Update `/home/slimy/claude-progress.md` with session summary

## Tech Stack Quick Reference

- Language: Python 3.x, Bash
- Orchestration: Custom scripts (30s heartbeat loop)
- Task routing: Skill-based scoring + PageRank
- Federation: NUC1 ↔ NUC2 via federation-router.py
- Config: agents.yaml, federation.json, loop-policy.json
- Process manager: PM2 (agent-loop)
- Remote: `git@github.com:GurthBro0ks/ned-autonomous.git`
- Branch: `main`
- Status: STALE (last active Apr 7, no running services)
