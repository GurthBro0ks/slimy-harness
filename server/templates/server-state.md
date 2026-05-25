# Server State — slimy-nuc1
> Last updated: 2026-05-25T22:38:00.000Z

## Machine
- **Hostname:** slimy-nuc1
- **OS:** Ubuntu 24.04.3 LTS
- **Disk:** ~125G/233G (~57% used)

## Canonical Repo Paths
> NOTE: `/home/slimy/.qoder-server/slimy-monorepo` is STALE — real path is `/opt/slimy/slimy-monorepo`
> `/home/slimy/slimy-monorepo` is a symlink → `/opt/slimy/slimy-monorepo`

| Repo | Canonical Path | Remote |
|------|---------------|--------|
| slimy-monorepo | /opt/slimy/slimy-monorepo | git@github.com:GurthBro0ks/slimy-monorepo.git |
| slimy-chat | /home/slimy/slimy-chat | git@github.com:GurthBro0ks/slime.chat.git |
| pm_updown_bot_bundle | /opt/slimy/pm_updown_bot_bundle | git@github.com:GurthBro0ks/pm_updown_bot_bundle.git |
| mission-control | /home/slimy/mission-control | git@github.com:GurthBro0ks/mission-control.git |
| clawd | /home/slimy/clawd | git@github.com:GurthBro0ks/clawd.git |
| ned-clawd | /home/slimy/ned-clawd | git@github.com:GurthBro0ks/ned-clawd.git |
| ned-autonomous | /home/slimy/ned-autonomous | git@github.com:GurthBro0ks/ned-autonomous.git |
| actionbook | /home/slimy/ned-clawd/actionbook | https://github.com/actionbook/actionbook |
| DynaTech | /home/slimy/src/plugins/DynaTech | https://github.com/ProfElements/DynaTech.git |
| PrivateStorage | /home/slimy/src/plugins/PrivateStorage | https://github.com/Slimefun-Addon-Community/PrivateStorage.git |
| Slimefun4 | /home/slimy/src/plugins/Slimefun4 | https://github.com/Slimefun/Slimefun4.git |
| stoat-source | /home/slimy/stoat-source | https://github.com/stoatchat/stoatchat |

## Active Services / Ports
| Service | Port | Status | Notes |
|---------|------|--------|-------|
| MySQL (Docker) | 3306 | ✅ Up | slimy-mysql container |
| Caddy (TLS) | 443 | ✅ Up | serves slimyai.xyz, chat, etc |
| slimy-chat (Revolt) | 8080 | ✅ Up | isolated Docker stack |
| slimy-web (Next.js) | 3000 | ⚠️ WAS ORPHANED | Orphaned mission-control duplicate (PID 4024832, killed 2026-03-23). Was serving mission-control. Primary instance on 3838. Port now FREE. |
| mission-control | 3838 | ✅ Up | systemd system service (`/etc/systemd/system/mission-control.service`) |
| slimy-bot-v2 (PM2) | — | ✅ Up | Discord bot (monorepo TypeScript), connected to 3 servers. Live: pid 803185, 0s uptime (restarted 2026-05-02 for ecosystem validation), 0 restarts since. Codebase: `/opt/slimy/slimy-monorepo/apps/bot/`, entry `dist/index.js`. PM2 config: `ecosystem.config.cjs`. Old bot archived at `/opt/slimy/app-archive-20260408.tar.gz`. |
| agent-loop (PM2) | — | ✅ Up | ned-autonomous orchestrator |
| admin-ui (systemd) | 3081 | ❌ DEAD | Systemd service `/etc/systemd/system/admin-ui.service`. Disabled and stopped 2026-03-23 via sudo. Port 3081 is free. |
| openclaw-gateway | 18789-18792 | ✅ Up | localhost only |
| gh-tracker | 5055 | ✅ Up | systemd user service (`gh-tracker.service`), public via Caddy basic auth at habitat.slimyai.xyz. Aggregate: 3 machines (laptop, nuc1, nuc2), 32 locations, 19 unique repos. GitHub remote health sync: 14/14 GurthBro0ks repos synced read-only. Phase 5A pushed (f3bd3e9). Phase 5B pushed (043d761) with timer active/enabled. Phase 5C pushed (31d9ca4): canonical repo default view with expandable per-machine/per-location details, mixed dirty state, GitHub health once per repo. App version 0.5.2-phase5c. |
| sbuild-editor (ad-hoc) | 3137 | ✅ Built | sBuild editor on commit 19c318b. Started manually per session. Not PM2/systemd. |

## Next.js Process Inventory
| PID | Port | Service | Supervision | Start Date | Status |
|-----|------|---------|-------------|------------|--------|
| 4017813 | 3838 | mission-control | systemd (system-level) | 2026-03-04 | ✅ Active |
| — | 3000 | (was orphaned mission-control duplicate) | NONE | — | ❌ Killed 2026-03-23 (port free) |
| — | 3081 | admin-ui | NONE | — | ❌ Dead (disabled 2026-03-23) |

## Known Issues

### admin-ui systemd service (port 3081) — FIXED ✅
**Status:** Systemd service at `/etc/systemd/system/admin-ui.service`. Disabled and stopped via sudo on 2026-03-23. Port 3081 is free. AGENTS.md says DEAD since 2026-03-19 (Discord OAuth removed, replaced by /owner/*).

### mission-control (port 3838) — SYSTEMD SUPERVISED ✅
Managed by systemd system service at `/etc/systemd/system/mission-control.service`. Has `Restart=always`. No action needed.

### mission-control orphaned duplicate (port 3000) — FIXED ✅
The "orphaned slimy-web" on port 3000 was actually a second mission-control instance (PID 4024832, orphaned, PPID=1, no supervisor). Corrected in session 2026-03-23: process killed, port 3000 freed. The primary mission-control instance on port 3838 handles all routed traffic via Caddy. PM2 dump files also cleared.

### slimy-monorepo SYNCED ✅
As of 2026-04-09, monorepo is on `main` branch (`38ba3bb`). Symlink `/home/slimy/slimy-monorepo` → `/opt/slimy/slimy-monorepo` confirmed live. Bot code at `apps/bot/` running as `slimy-bot-v2` PM2 process.

### slimy-bot-v2 CUTOVER ✅ (2026-04-03)
Old slimy-bot (JS at /opt/slimy/app, PM2 id 2) replaced by slimy-bot-v2 (TypeScript monorepo at `/opt/slimy/slimy-monorepo/apps/bot/`). Old bot PM2 process deleted. Old bot code removed and archived to `/opt/slimy/app-archive-20260408.tar.gz`. Rollback script at `/home/slimy/rollback-bot.sh`. Cutover verified live 2026-04-09.

## Ops Databases (ned-clawd)
- `/home/slimy/ned-clawd/ops/ops.db` — ✅ Initialized 2026-03-23
- `/home/slimy/ned-clawd/ops/decisions.db` — ✅ Initialized 2026-03-23
- `/home/slimy/ned-clawd/ops/triggers.db` — ✅ Fixed 2026-03-23
- `/home/slimy/ned-clawd/tasks/taskboard.json` — ✅ Created 2026-03-23

## PM2 Infrastructure
- **Ecosystem config:** `/opt/slimy/slimy-monorepo/ecosystem.config.cjs` — formalized 2026-05-02, captures `slimy-bot-v2` only
- **Logrotate:** No PM2 logrotate config exists (`/etc/logrotate.d/pm2*` missing) — bot logs to `/home/slimy/logs/bot-*.log`
- **Startup:** `pm2-slimy` systemd service is enabled

## Intentionally Dead (DO NOT RESURRECT)
| Service | Port | Kill Date | Reason |
|---------|------|-----------|--------|
| admin-api | 3080 | 2026-03-19 | Discord OAuth removed, replaced by slimy-auth |
| admin-ui | 3081 | 2026-03-19 | Was Discord admin panel, replaced by /owner/* |
| mission-control (orphan) | 3000 | 2026-03-23 | Orphaned duplicate of port 3838 instance; no Caddy route; killed to remove unsupervised process |

## 2026-05-02 Update
- **@slimy/db package**: New shared MySQL pool package at `packages/db/` in slimy-monorepo
  - Exports: `getPool(prefix?)`, `destroyPool()`, `query<T>()`, `createDbPool()`
  - Supports `DB_*` (bot) and `CLUB_MYSQL_*` (web app) env var prefixes
  - Bot refactored to consume `@slimy/db` — pool init confirmed in live logs
  - Web app wiring pending

## 2026-05-07 Update
- **Live trading PAUSED**: crontab entry for cron_micro_live.sh commented out with PAUSED_2026-05-07_UNSAFE_TO_RESUME
- **Trading brakes patch deployed**: Commit 0f4bb28 on feat/ibkr-forecast-integration
  - TRADING_PAUSED flag implemented
  - Category allowlist blocks sports/esports by default
  - Expiry filter inf-bypass fixed
  - Minimum price floor (5c) enforced
  - Daily loss guard ($1.00) enforced
  - Max orders per run (2) and max notional ($1.00) enforced
  - Balance parse improvements
  - Resting order review script created
- **Tests**: 429/429 pass
- **Resting orders**: 15 stale orders identified, awaiting manual review
- **Status**: Do NOT unpause live trading until resting orders reviewed and shadow mode monitored
