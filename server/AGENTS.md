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

> This section is populated at install time by server-install.sh or by
> the agent via init.sh dynamic discovery. Do not edit here — edit the
> live file at /home/slimy/AGENTS.md on each NUC.
>
> Expected structure:
> | Project | Path | Branch | Remote |
> |---------|------|--------|--------|
> | (name) | (path) | (branch) | (remote) |

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

---

## Host-Specific Sections (fill in per NUC)

> The sections below contain host-specific operational truths. They are
> templates here — each NUC fills them in at install time or maintains
> them manually in the live /home/slimy/AGENTS.md.

### Intentionally Dead (DO NOT RESURRECT)

> List services that were deliberately killed and should not be restarted.
> Format: | Service | Killed Date | Reason | Replacement |

| Service | Killed Date | Reason | Replacement |
|---------|------------|--------|-------------|
| (service) | YYYY-MM-DD | (reason) | (replacement) |

### Auth System

> Document the current auth system stack and login flow.

- **Stack:** (e.g., lib/slimy-auth/ → argon2 + MySQL sessions + httpOnly cookies)
- **Login:** (e.g., slimyai.xyz/login → email/password → /dashboard)
- **Owner gate:** (e.g., /owner/* protected via requireAuth())
- **Database:** (e.g., MySQL via Prisma (SlimyUser, SlimySession, ...))

### Infrastructure Truth Table

> Per-NUC service inventory. Format: | Service | NUC | Status | Port | Touch? |

| Service | NUC | Status | Port | Touch? |
|---------|-----|--------|------|--------|
| (service) | NUC1/NUC2 | running/dead | (port) | OK/DO NOT START |

### Repo Locations

> Per-NUC specific repo path notes (e.g., symlinks, non-standard paths).

- (e.g., "Live code: /opt/<org>/<monorepo>/")
- (e.g., "DO NOT fresh-clone into symlink paths — use actual repo location")

---

*For host-specific reference (NUC1 or NUC2), see docs/REFERENCE_AGENTS_HOST_SPECIFIC.md in this repo.*
*Do NOT copy host-specific operational details onto other hosts.*
