# PROJECT_NARRATIVE.md — SlimyAI Server Template

> This file describes the WHY behind the system: why projects exist, how they relate,
> where the risk zones are, and what institutional knowledge is critical to preserve.
>
> **Template — lives in git at `slimy-harness/server/templates/PROJECT_NARRATIVE.md`**
> **Installer copies this to `/home/slimy/PROJECT_NARRATIVE.md` when missing.**
> **Do NOT put secrets or live operational state here.**

## Architecture Overview

### System Topology
- **NUC1** (this server): [fill in per NUC]
- **NUC2**: [fill in per NUC]
- **Connection**: Tailscale (nuc1-ts / nuc2-ts)

### Project Relationships
```
[TODO — describe how projects depend on each other]
Example:
slimy-monorepo (API/auth/DB) → mission-control (admin UI)
slimy-chat (Revolt) → mailboxes handled independently
```

### Data Flows
- [TODO — how does data flow between projects?]

## Risk Zones

### Services that are Dead and Should NOT be Restarted
- [TODO — fill from AGENTS.md "Intentionally Dead" section]
- Format: | Service | Killed Date | Reason | Replacement |

### Services that are Critical and Fragile
- [TODO — which services if killed would break the system?]

### Secrets / Forbidden Paths
- [TODO — list forbidden zones per project]

## Institutional Knowledge

### Known Failure Modes
- [TODO — document known past failures and their fixes]

### Critical Procedures
- [TODO — how to safely restart services, how to recover from common failures]

## Current State

> As of YYYY-MM-DD, verified by [agent/session]:

| Project | Path | Live? | Last Verified |
|---------|------|-------|---------------|
| (repo) | (path) | yes/no | YYYY-MM-DD |

## Project Map

| Project | Path | Language | What It Is |
|---------|------|----------|------------|
| (name) | (path) | (lang) | (description) |

## Verification / Truth Sources

> What to check to verify the system is healthy.

| Check | Command / Source |
|-------|------------------|
| Repo discovery | `source /home/slimy/init.sh` |
| Docker services | `docker ps` |
| PM2 services | `pm2 list` |
| Monorepo truth gate | `pnpm lint && pnpm test:all` in slimy-monorepo |
| Bot bundle truth gate | `./scripts/run_tests.sh` in pm_updown_bot_bundle |
| Service ports | `ss -tlnp \| grep LISTEN` |
| Live state | `/home/slimy/server-state.md` |

## Known Fragile Areas

- [TODO — list things that are brittle or poorly tested]

## Open Questions

- [TODO — things that need investigation or decision]

---

*This file is sourced by Prompt P / C2 / PROJECT_NARRATIVE startup integration in Harness v3.*
*Template version — actual content filled in per host at install time or by agent.*
