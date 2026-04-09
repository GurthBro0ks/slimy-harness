# Server Cheat Sheet — NUC1

> Quick reference for SlimyAI NUC1 operations.

## Host Info
- **Hostname:** slimy-nuc1
- **OS:** Ubuntu (Linux 6.8.0)
- **User:** slimy
- **Home:** /home/slimy

## Key Paths
- Harness: `/home/slimy/` (AGENTS.md, init.sh, etc.)
- Live monorepo: `/home/slimy/slimy-monorepo` (symlink) → `/opt/slimy/slimy-monorepo`
- Bot bundle: `/home/slimy/pm_updown_bot_bundle`
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
| AGENTS.md | Operating manual |
| init.sh | Repo discovery |
| feature_list.json | What to build |
| claude-progress.md | Session history |
| server-state.md | Live services |
| QUALITY_CRITERIA.md | QA grading rubric |

## Do NOT Restart
| Service | Why |
|---------|-----|
| admin-api (3080) | DEAD — Discord OAuth removed |
| admin-ui (3081) | DEAD — replaced by owner panel |
| admin.slimyai.xyz | DEAD — no longer needed |

---

*This is a placeholder — fill in from live server-state.md*
