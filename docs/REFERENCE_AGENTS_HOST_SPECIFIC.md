# SlimyAI Server — Agent Operating Manual

You are an autonomous agent operating on a SlimyAI server.
This server hosts multiple projects. This file is your top-level map.

## Startup Sequence (EVERY session)

1. `cat /home/slimy/claude-progress.md` — what happened last session
2. `cat /home/slimy/feature_list.json` — master feature list
3. `cat /home/slimy/server-state.md` — services, ports, health
4. Decide which project to work in based on priorities
5. `cd` into that project and `source init.sh` if it exists
6. Begin work

## Project Map

| Project | Path | Branch | Remote |
|---------|------|--------|--------|
| agents | /home/slimy/.claude/agents | main | https://github.com/wshobson/agents.git |
| clawd | /home/slimy/clawd | main | git@github.com:GurthBro0ks/clawd.git |
| .mcp_agent_mail_git_mailbox_repo | /home/slimy/.mcp_agent_mail_git_mailbox_repo | master | local-only |
| mission-control | /home/slimy/mission-control | main | git@github.com:GurthBro0ks/mission-control.git |
| mailbox_ingest | /home/slimy/nuc-comms/mailbox_ingest | main | /home/slimy/nuc-comms/mailbox.git |
| git-notes-ledger | /home/slimy/.openclaw/memory/git-notes-ledger | master | local-only |
| workspace | /home/slimy/.openclaw/workspace | master | local-only |
| pm_updown_bot_bundle | /home/slimy/pm_updown_bot_bundle | main | git@github.com:GurthBro0ks/pm_updown_bot_bundle.git |
| slimy-monorepo | /home/slimy/slimy-monorepo | main | git@github.com:GurthBro0ks/slimy-monorepo.git |

## Work Rules

- ONE feature per session unless told otherwise
- Always update `/home/slimy/claude-progress.md` at end of session
- Always update `/home/slimy/feature_list.json` with pass/fail
- Commit in whatever project you worked in
- If a project has its own AGENTS.md, read and follow its rules too

## Knowledge Base
A shared knowledge base lives at /home/slimy/kb/ (git repo: GurthBro0ks/slimy-kb).
- wiki/ contains compiled articles (read these for project context)
- raw/ contains source documents (write new learnings here)
- tools/kb-search.sh "query" searches the wiki
- tools/kb-sync.sh pull|push|sync keeps both NUCs in sync
- See /home/slimy/kb/KB_AGENTS.md for full KB rules
- ALWAYS run kb-sync.sh pull before reading, kb-sync.sh push after writing

## End-of-Session Checklist

1. Project truth gate passes (lint/tests)
2. `/home/slimy/feature_list.json` updated
3. `/home/slimy/claude-progress.md` updated
4. Git commit in the project
5. If server state changed, update `/home/slimy/server-state.md`
(Optional) If you discovered a reusable pattern, debugging fix, or architecture decision:
  echo "content" | bash /home/slimy/kb/tools/kb-write.sh raw/agent-learnings/$(date +%Y-%m-%d)-nuc1-[slug].md

## Intentionally Dead (DO NOT RESURRECT)

These services were deliberately killed. If you find them "broken," that is correct.
Do NOT fix, restart, re-enable, or recreate any of these.

| Service | Killed Date | Reason | Replacement |
|---------|------------|--------|-------------|
| admin-api (port 3080) | 2026-03-19 | Discord OAuth removed | slimy-auth (lib/slimy-auth/) |
| Discord OAuth | 2026-03-19 | Replaced entirely | Email/password login via slimy-auth |
| admin.slimyai.xyz | 2026-03-19 | No longer needed | slimyai.xyz serves everything |
| admin-ui (port 3081) | 2026-03-19 | Was Discord admin panel | Owner panel at /owner/* |
| /api/* → 3080 rewrite | 2026-03-21 | Stale proxy to dead service | Next.js API routes handle all /api/* |

### Auth System (Current — DO NOT CHANGE without explicit instruction)
- **Stack:** `lib/slimy-auth/` → argon2 + MySQL sessions (Prisma) + httpOnly cookies
- **Login:** `slimyai.xyz/login` → email/password → `/dashboard`
- **Owner gate:** `/owner/*` protected via `requireAuth()` in layout
- **Database:** MySQL via Prisma (`SlimyUser`, `SlimySession`, `SlimyInvite`, `SlimyLoginAttempt`)
- **Discord:** ZERO integration with login. Discord adapters exist only for code aggregation (Super Snail codes).

### Infrastructure Truth Table
| Service | NUC | Status | Port | Touch? |
|---------|-----|--------|------|--------|
| MySQL (Docker) | NUC1 | ✅ Running | 3306 | OK — Snail bot needs it |
| Caddy (TLS) | NUC1 | ✅ Running | 443 | OK — serves slimyai.xyz, chat, etc |
| slimy-chat (Revolt) | NUC1 | ✅ Running | 8080 | OK — isolated, no auth bridge |
| agent-loop | NUC1 | ✅ Running | — | OK |
| admin-api | NUC1 | ❌ DEAD | 3080 | DO NOT START |
| admin-ui | NUC1 | ❌ DEAD | 3081 | DO NOT START |
| slimyai-web (Next.js) | NUC2 | ✅ Running | 3000 | OK — slimy-auth login |
| mission-control | NUC2 | ✅ Running | 3838 | OK |
| PostgreSQL | NUC2 | ✅ Running | 5432 | OK (legacy, not used by slimy-auth) |

### Repo Locations (Both NUCs)
- **Live code:** `/opt/slimy/slimy-monorepo/` (branch: `feature/merge-chat-app`)
- **Symlink:** `/home/slimy/slimy-monorepo` → `/opt/slimy/slimy-monorepo`
- **PM2 cwd:** `/opt/slimy/slimy-monorepo/apps/web`
- **DO NOT** fresh-clone into `/home/slimy/slimy-monorepo/` — it's a symlink, not a directory
