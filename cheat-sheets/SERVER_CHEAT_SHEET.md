# Server Cheat Sheet — NUC1

> Quick reference for SlimyAI NUC1 operations.

## Host Info
- **Hostname:** slimy-nuc1
- **OS:** Ubuntu (Linux 6.8.0)
- **User:** slimy
- **Home:** /home/slimy

## Key Paths
- Harness source (git): `/home/slimy/slimy-harness/`
- Live harness: `/home/slimy/` (AGENTS.md, init.sh, etc.)
- Live PROJECT_NARRATIVE: `/home/slimy/PROJECT_NARRATIVE.md` (host-specific, NOT in git)
- Live monorepo: `/home/slimy/slimy-monorepo` (symlink) → `/opt/slimy/slimy-monorepo`
- Bot bundle: `/home/slimy/pm_updown_bot_bundle` → `/opt/slimy/pm_updown_bot_bundle`
- Mission control: `/home/slimy/mission-control`
- Knowledge base: `/home/slimy/kb/`

## Quick Status
```bash
# System health
df -h /

# Docker
docker ps

# PM2
pm2 list

# Git status of all repos
find /home/slimy -maxdepth 4 -name ".git" -type d | while read d; do
  repo=$(dirname "$d")
  echo "=== $(basename $repo) ==="
  git -C "$repo" status --short 2>/dev/null | head -5
done
```

## Service Ports
- slimyai.xyz / Caddy: 443
- slimy-chat (Revolt): 8080
- MySQL (Docker): 3306
- mission-control (NUC2): 3838

## Harness Files
| File | Purpose |
|------|---------|
| AGENTS.md | Operating manual (v3: 9-step startup) |
| init.sh | Repo discovery |
| feature_list.json | What to build (v3: risk + plan[] fields) |
| claude-progress.md | Session history |
| server-state.md | Live services |
| PROJECT_NARRATIVE.md | Architecture, risk zones, institutional knowledge (v3) |
| QUALITY_CRITERIA.md | QA grading rubric (v3: verification gate) |

## V3 Prompt Modes
| Prompt | Use When | Key Rule |
|--------|----------|----------|
| AUTO-WORK | Pick feature + go | One feature at a time |
| PROMPT P | New feature / complex task | Plan first, then code |
| PROMPT C2 | Something is broken | Root cause first, then fix |
| FIX MODE | Breakage across projects | Smallest diffs, test each |

## Do NOT Restart
| Service | Why |
|---------|-----|
| admin-api (3080) | DEAD — Discord OAuth removed |
| admin-ui (3081) | DEAD — replaced by owner panel |
| admin.slimyai.xyz | DEAD — no longer needed |
| mission-control orphan (port 3000) | DEAD — orphaned duplicate, killed 2026-03-23 |

## Critical Services
| Service | How to Check | How to Restart |
|---------|--------------|---------------|
| slimy-bot-v2 | `pm2 list` | `pm2 restart slimy-bot-v2` |
| MySQL (Docker) | `docker ps` | `docker restart slimy-mysql` |
| slimy-chat | `docker ps` | `cd /home/slimy/slimy-chat && docker compose up -d` |
| mission-control (NUC2) | `ssh nuc2-ts sudo systemctl status mission-control` | `ssh nuc2-ts sudo systemctl restart mission-control` |

---

*Fill in from live server-state.md and PROJECT_NARRATIVE.md*
