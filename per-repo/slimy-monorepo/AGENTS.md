# Slimy Monorepo — Agent Operating Manual

You are an autonomous coding agent working in the SlimyAI monorepo.

## Startup Sequence (do this EVERY session)

1. `pwd` — confirm you're in the repo root
2. `cat claude-progress.md` — understand what happened last session
3. `cat feature_list.json | head -200` — see current feature status
4. `git log --oneline -10` — see recent commits
5. `source init.sh` — start the dev environment
6. Pick the highest-priority incomplete feature from feature_list.json
7. Only THEN begin coding

## Repo Structure

- `apps/web/` — Main Next.js web app (port 3000)
- `apps/admin-api/` — Express admin API (port 3080)
- `apps/admin-ui/` — Admin dashboard (port 3081)
- `apps/bot/` — Bot application (placeholder)
- `packages/` — Shared libraries (config, db, auth, utils)
- `lib/` — Internal libraries
- `infra/docker/` — Docker/deployment configs
- `docs/` — Architecture docs, workflows, design notes
- `scripts/` — Build and utility scripts
- `tests/` — Integration/e2e tests

## Deeper Docs (read when relevant, not upfront)

- `docs/DEV_WORKFLOW.md` — Full dev setup and workflows
- `docs/INFRA_OVERVIEW.md` — System architecture and data flows
- `docs/SERVICES_MATRIX.md` — Ports, commands, dependencies
- `docs/CI.md` — CI pipeline details
- `ARCHITECTURAL_AUDIT.md` — Known architectural issues
- `CONTRIBUTING.md` — Contribution standards

## Truth Gate

A feature is only "done" when:
1. `pnpm lint` passes
2. `pnpm test:all` passes (or the relevant app test)
3. The feature works end-to-end (not just unit tests)

## Forbidden Zones (DO NOT TOUCH)

- `.env*` files (never read/write secrets)
- Any wallet/key/seed/mnemonic material
- `pnpm-lock.yaml` (only modify via `pnpm install`)

## Work Rules

- ONE feature per session. Complete it or document where you stopped.
- Small, surgical commits with descriptive messages (`feat:`, `fix:`, `refactor:`)
- Run `pnpm lint` after every edit. Fix linting errors before moving on.
- If you break something, `git stash` or `git checkout` before compounding the problem.
- Never mark a feature as passing in feature_list.json without running the truth gate.

## End-of-Session Checklist

1. All code lints clean
2. Tests pass
3. `feature_list.json` updated (passes: true for completed features)
4. `claude-progress.md` updated with what you did, what's next
5. `git add -A && git commit -m "<type>: <description>"`
6. Leave the environment in a state where init.sh will work for the next session

## Tech Stack Quick Reference

- Runtime: Node.js + TypeScript
- Package manager: pnpm (workspaces)
- Web framework: Next.js (apps/web)
- API: Express (apps/admin-api)
- Database: Prisma ORM (run `pnpm prisma:generate` if schema changes)
- Linting: ESLint (`eslint.config.mjs`)
- Docker: `docker-compose.yml` for containerized deployment
