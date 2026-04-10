# Mission Control — Agent Operating Manual

You are an autonomous coding agent working in the Mission Control dashboard repo.

## Startup Sequence (do this EVERY session)

1. `pwd` — confirm you're in the repo root
2. `cat claude-progress.md` — understand what happened last session
3. `cat feature_list.json | head -200` — see current feature status
4. `git log --oneline -10` — see recent commits
5. `source init.sh` — validate the environment
6. Pick the highest-priority incomplete feature from feature_list.json
7. Only THEN begin coding

## Repo Structure

- `app/` — Next.js app pages and layouts
- `components/` — React components
- `hooks/` — Custom React hooks
- `lib/` — Shared library code
- `api/` — API route handlers
- `ops/` — Operational scripts and utilities
- `tasks/` — Task-related code
- `comms/` — Communication/messaging code
- `public/` — Static assets

## Tech Stack

- Framework: Next.js 16 (Node.js)
- Language: TypeScript
- UI: Tailwind CSS v4
- Database: better-sqlite3 (local SQLite)
- Process manager: PM2 (ecosystem.mission-control.config.js)
- Port: 3838 (production)
- Linting: ESLint 9

## Truth Gate

A feature is only "done" when:
1. `pnpm lint` passes
2. `pnpm build` passes (or the relevant subset)
3. The feature works end-to-end

## Forbidden Zones (DO NOT TOUCH)

- `.env*` files (never read/write secrets)
- Any wallet/key/seed/mnemonic material
- `node_modules/` (never modify directly)
- `package-lock.json` (only modify via `pnpm install`)

## Work Rules

- ONE feature per session. Complete it or document where you stopped.
- Small, surgical commits with descriptive messages (`feat:`, `fix:`, `refactor:`)
- Run `pnpm lint` after every edit. Fix linting errors before moving on.
- If you break something, `git stash` or `git checkout` before compounding the problem.

## End-of-Session Checklist

1. All code lints clean
2. `feature_list.json` updated (passes: true for completed features)
3. `claude-progress.md` updated with what you did, what's next
4. `git add -A && git commit -m "<type>: <description>"`
5. Leave the environment in a state where init.sh will work for the next session
