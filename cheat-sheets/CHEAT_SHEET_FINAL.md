# Cheat Sheet — Final

## Essential Commands

### Agent Startup (v3)
```bash
# Full v3 startup sequence
cat /home/slimy/AGENTS.md
cat /home/slimy/claude-progress.md
cat /home/slimy/feature_list.json
cat /home/slimy/PROJECT_NARRATIVE.md   # v3: system context
cat /home/slimy/server-state.md
source /home/slimy/init.sh
```

### Repo Discovery
```bash
# See all discovered repos
source /home/slimy/init.sh

# Jump to a repo
cd $REPO_slimy_monorepo
cd $REPO_pm_updown_bot_bundle
```

### Pre-Push Sync Hygiene (slimy-harness)
**Always run before pushing from either NUC:**
```bash
cd /home/slimy/slimy-harness
git fetch origin
git status -sb          # shows: main...origin/main
git log --oneline --decorate -n 5

# Or use the helper:
bash scripts/check-sync-state.sh --fetch
```

**Verdict meanings:**
| Verdict | Meaning | Action |
|---------|---------|--------|
| `[OK]` | in sync | safe to push |
| `[AHEAD]` | local has unpushed commits | safe if ready |
| `[BEHIND]` | origin has new commits | pull or reset first |
| `[DIVERGED]` | split histories | merge/rebase before pushing |

**Why:** slimy-harness is used on two hosts. Pushing from a diverged state can overwrite remote commits and cause artifact loss.

### Truth Gates
```bash
# Monorepo
pnpm --filter @slimy/bot build && pnpm --filter @slimy/bot test

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

## Prompt P — Plan-First Work (v3)

Use when: starting a new feature or complex task.

**Workflow:**
1. Read ALL harness context (AGENTS.md, claude-progress.md, feature_list.json, PROJECT_NARRATIVE.md, server-state.md)
2. Classify risk (LOW / MEDIUM / HIGH)
3. Write sprint-contract.md with plan, verification steps, regression list, rollback
4. Execute ONE substep at a time, verifying each
5. Final truth gate + regression check
6. Shutdown: document what was verified and what remains unverified

**Risk levels:**
- LOW: Small, well-understood → bounded plan + truth gate
- MEDIUM: Moderate uncertainty → sprint-contract.md required
- HIGH: Large/security/critical → sprint-contract + rollback plan + explicit sign-off

---

## Prompt C2 — Systematic Fix / Debug (v3)

Use when: something is broken and needs root-cause debugging.

**Workflow:**
1. OBSERVE: run truth gate, record exact failure, check git log
2. HYPOTHESIZE: write ONE specific, falsifiable root cause
3. TEST THE HYPOTHESIS: try to disprove it
4. FIX: smallest diff for confirmed root cause only
5. PROVE IT: truth gate + same test + manual reproduction — all MUST pass
6. ESCALATE after 3 failed attempts: suspect architecture, document as UNRESOLVED

**Fail-closed:** Cannot find root cause → do NOT random-patch, do NOT mark passes:true

---

## Feature List V3 Schema

```json
{
  "id": "slug",
  "project": "repo-name",
  "description": "what it does",
  "priority": "critical|high|medium|low",
  "passes": false,
  "risk": "low|medium|high",
  "plan": ["step 1", "step 2"],
  "qa_verified": false,
  "added": "YYYY-MM-DD",
  "completed": null
}
```

- **risk**: guides how much planning Prompt P requires
- **plan[]**: concrete substeps for v3 features
- **passes**: builder sets false initially; QA sets true after independent verification

---

## Verification Gate (v3)

Before marking passes:true, must document:
- Exact commands run and their results
- What was tested (happy path + edge cases)
- What remains unverified

**Builder vs QA:** builder runs truth gate; QA independently verifies. Only QA sets passes:true.

---

## Sprint Contract (Prompt P artifact)

Create at `/home/slimy/sprint-contract.md`:
```
WHAT: [feature id + description]
RISK: [low/medium/high] — why
PLAN:
  1. [step] → [verification command]
  2. [step] → [verification command]
REGRESSION: [what must still work]
ROLLBACK: [how to undo]
```

---

## Doc-Sync Hygiene (Phase 1 + Phase 2 + Phase 3)

Auto-sync (`kb-project-doc-sync.sh` / `slimy-agent-finish.sh`) enforces:

**Phase 1 guards:**
1. **Explicit allowlist**: only repos in `kb/config/doc-sync-allowlist.txt` are touched. Others are skipped with a log message.
2. **Dirty-tree skip**: if a repo has non-doc dirty files (anything other than README.md, CHANGELOG.md, VERSION.md), the entire repo is skipped — doc-sync will not bundle work-in-progress into commits.
3. **Non-pushable skip**: repos with no `origin` remote (local-only) are skipped for commit/push.

**Phase 2 guards:**
4. **Conditional VERSION.md**: VERSION.md is only rewritten if the would-be content differs from current. Unchanged files are not touched (preserves mtime, avoids spurious git dirt).
5. **Push-or-revert**: if an auto-sync commit is created but push fails, the commit is immediately reverted (`git reset --soft HEAD~1`). No local-only auto-sync commits accumulate.

**Phase 3 guards:**
6. **Session-scoped default**: `slimy-agent-finish.sh` will NOT scan `/home/slimy` or `/opt/slimy` for repos unless `--scan-all` is explicitly passed. Default behavior: zero repos touched if no `--repo` is specified.
7. **Broad scan is explicit opt-in**: use `--scan-all` flag to enable multi-repo detection. This is never triggered by the stop hook automatically.
8. **Stop hook wiring**: `~/.claude/settings.json` Stop hook passes `${CLAUDE_PROJECT_DIR:-}` as `--active-repo` to `slimy-session-finish.sh`, which passes it as `--repo` to `slimy-agent-finish.sh`. No active repo = no sync.

**Behavior summary:**
| Invocation | Repos touched |
|---|---|
| `slimy-agent-finish.sh --repo /path/to/repo` | Only that repo |
| `slimy-agent-finish.sh` (no flags) | NONE (session-scoped default) |
| `slimy-agent-finish.sh --scan-all` | All recently-changed allowlisted repos |
| Stop hook (SUCCESS) | Active repo only |
| Stop hook (ERROR) | Active repo only |
| Stop hook (Ctrl+C) | NONE (interrupt path) |

**Allowlist file:** `kb/config/doc-sync-allowlist.txt`
**Override env var:** `DOC_SYNC_ALLOWLIST=/path/to/custom-allowlist.txt`

---

## Do NOT Restart (Dead Services)

| Service | Port | Why |
|---------|------|-----|
| admin-api | 3080 | Discord OAuth removed |
| admin-ui | 3081 | Replaced by /owner/* |
| admin.slimyai.xyz | — | No longer needed |

---

## Key Paths
- Harness: `/home/slimy/slimy-harness/` (git-tracked source)
- Live harness: `/home/slimy/{AGENTS.md, init.sh, ...}` (live state)
- Live narrative: `/home/slimy/PROJECT_NARRATIVE.md` (host-specific, NOT in git)
- Monorepo: `/opt/slimy/slimy-monorepo/` (symlink at `/home/slimy/slimy-monorepo`)
- Bot bundle: `/opt/slimy/pm_updown_bot_bundle/`
