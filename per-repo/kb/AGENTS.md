# Slimy KB — Agent Operating Manual

You are an autonomous coding agent working in the SlimyAI Knowledge Base repo.

## Startup Sequence (do this EVERY session)

1. `pwd` — confirm you're in the repo root (`/home/slimy/kb`)
2. `git log --oneline -10` — see recent commits
3. `bash tools/kb-sync.sh pull` — sync latest from remote
4. `bash tools/kb-lint.sh` — verify KB integrity
5. Read `KB_AGENTS.md` for KB-specific rules
6. Pick the highest-priority task
7. Only THEN begin work

## Repo Structure

- `wiki/` — Compiled knowledge articles (agent-owned via compile pipeline)
- `raw/` — Source documents (write new learnings here)
- `tools/` — KB management scripts (kb-sync.sh, kb-search.sh, kb-write.sh, etc.)
- `docs/` — KB documentation
- `output/` — Generated outputs
- `config/` — KB configuration
- `VERSION.md` — KB version tracking
- `CHANGELOG.md` — Change log

## Truth Gate

A change is only "done" when:
1. `bash tools/kb-lint.sh` passes
2. No broken links in wiki index
3. `bash tools/kb-sync.sh push` succeeds without conflicts

## Forbidden Zones (DO NOT TOUCH)

- `wiki/` — never edit directly (agent-owned via compile pipeline)
- `.env*` files
- Write to `raw/` ONLY via `tools/kb-write.sh` or direct file creation
- Never force-push to the KB remote

## Work Rules

- ALWAYS run `tools/kb-sync.sh pull` before reading wiki content.
- ALWAYS run `tools/kb-sync.sh push` after writing.
- New learnings go into `raw/` (e.g., `raw/agent-learnings/YYYY-MM-DD-slug.md`).
- ONE task per session. Complete it or document where you stopped.

## End-of-Session Checklist

1. `bash tools/kb-lint.sh` passes
2. `bash tools/kb-sync.sh push` completed
3. `git add -A && git commit -m "<type>: <description>"`
4. Update `/home/slimy/claude-progress.md` with session summary

## Tech Stack Quick Reference

- Language: Markdown (content), Bash (tools)
- Sync: `tools/kb-sync.sh` (git-based, cross-NUC)
- Search: `tools/kb-search.sh "query"`
- Write: `tools/kb-write.sh <path>`
- Lint: `tools/kb-lint.sh`
- Remote: `git@github.com:GurthBro0ks/slimy-kb.git`
