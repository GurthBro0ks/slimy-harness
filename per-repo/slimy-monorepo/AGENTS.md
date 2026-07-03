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
- `apps/bot/` — Discord bot (TypeScript, Vitest tests in `apps/bot/tests/`)
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

### Bot test recipes (copy exactly — do not improvise)

- Focused bot tests: `cd apps/bot && npx vitest run tests/lib/<name>.test.ts`
  (Vitest args are filters — a typo'd path is silently ignored when another
  matches; verify the reported test-file count matches what you asked for).
- Script tests live in `scripts/__tests__/` (never `scripts/tests/`):
  `npx vitest run --config scripts/vitest.config.mjs scripts/__tests__/<name>.test.mjs`
- `pnpm test:bot` / `pnpm --filter @slimy/bot test` run the FULL bot suite —
  don't use them for a focused check. `--runInBand` is Jest-only and fails
  under Vitest.
- Capture exit codes honestly: run the command, then save `$?` (or
  `rc=0; cmd || rc=$?` under `set -e`).
  Never mask them: `cmd || true; echo $?` is BROKEN (always prints 0).
- Full-suite runs currently have one known unrelated WARN
  (version-manifest.test.ts, web 0.4.0 vs manifest 0.4.3) — report it as
  KNOWN-WARN by name, never as a clean PASS.
- Full recipes: `docs/BOT_VALIDATION_RECIPES.md` in the slimy-harness repo.

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
