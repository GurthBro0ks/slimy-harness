# Cheat Sheet — Final

> TODO: Collect final state of SlimyAI NUC1 cheat sheet here.

## Essential Commands

### Agent Startup
```bash
cd /home/slimy
source init.sh
```

### Repo Discovery
```bash
# See all discovered repos
source /home/slimy/init.sh

# Jump to a repo
cd $REPO_slimy_monorepo
cd $REPO_pm_updown_bot_bundle
```

### Truth Gates
```bash
# Monorepo
pnpm lint && pnpm test:all

# Bot bundle
./scripts/run_tests.sh

# Mission control
bash mission-control.sh
```

### Knowledge Base
```bash
cd /home/slimy/kb
bash tools/kb-sync.sh pull   # ALWAYS pull before reading
bash tools/kb-sync.sh push    # ALWAYS push after writing
bash tools/kb-search.sh "query"
```

### Services
```bash
docker ps
pm2 list
ss -tlnp | grep LISTEN
```

---

*This is a placeholder — compile from session learnings*
