# Harness v3 — Prompt P Trial Report

## Trial Metadata

- **Trial Mode:** Prompt P (plan-first work mode)
- **Date:** 2026-04-10
- **Agent Role:** Harness V3 Trial Operator
- **Task:** Add per-repo harness template for mission-control

---

## Step 1 — Risk Classification

**Risk Level: LOW**

**Why this level:**
- Adds only NEW files to a harness git repo
- Installer never overwrites existing files (only copies if destination missing)
- No production systems, services, or data touched
- No installer architecture changes — just new template directory

**What could go wrong:**
- Malformed AGENTS.md could confuse future agents working in mission-control
- Broken init.sh could prevent agent initialization in that repo
- Neither of these affects production — only agent guidance

**What must remain invariant:**
- `validate-harness.sh` continues to pass (52 checks)
- `server-install.sh --dry-run` continues to have zero-write side effects
- QA authority documentation remains intact
- No live-cutover behavior reintroduced

---

## Step 2 — Plan Used

**Files inspected:**
- `per-repo/pm_updown_bot_bundle/AGENTS.md` — reference template (Python bot)
- `per-repo/slimy-monorepo/AGENTS.md` — reference template (Node.js monorepo)
- `per-repo/pm_updown_bot_bundle/init.sh` — reference init
- `per-repo/slimy-monorepo/init.sh` — reference init
- `server-install.sh` — installer behavior (how per-repo templates are matched)
- `docs/HARNESS_ARCHITECTURE.md` — harness architecture docs
- `scripts/validate-harness.sh` — validation checks
- `mission-control/package.json` — tech stack evidence (Next.js 16, TypeScript, Tailwind, PM2)
- `mission-control/ecosystem.mission-control.config.js` — PM2 config evidence

**Files created:**
1. `per-repo/mission-control/AGENTS.md` — project-specific agent operating manual
2. `per-repo/mission-control/init.sh` — environment init + truth gate

**Files NOT changed:**
- All existing per-repo templates untouched
- `server-install.sh` unchanged
- `validate-harness.sh` unchanged
- No architecture changes

**Verification steps run:**
1. `bash -n per-repo/mission-control/init.sh` → PASS
2. `bash -n` on all shell files → all PASS
3. `bash scripts/validate-harness.sh` → 52 passed, 1 warning (expected: new files mtime > git index)
4. `bash server-install.sh --dry-run` → correctly shows `Installing harness for: mission-control → /home/slimy/mission-control`

**Rollback approach:** `git checkout -- .` would revert all changes if needed.

---

## Step 3 — Implementation Notes

### Template Design Decisions

**AGENTS.md:**
- Based on pm_updown_bot_bundle and slimy-monorepo patterns
- Included: startup sequence, repo structure, tech stack, truth gate, forbidden zones, work rules, end-of-session checklist
- Omitted: feature_list.json and claude-progress.md (not present in pm_updown_bot_bundle either)
- Tech stack details derived from package.json (Next.js 16, React 19, Tailwind v4, better-sqlite3, PM2 on port 3838)

**init.sh:**
- Checks for `package.json` with `"name": "mission-control"` (specific to this project)
- Checks Node.js availability
- Installs dependencies via pnpm (or npm fallback)
- Runs `pnpm lint` as quick truth gate
- Provides command reference for dev/build/start/lint

**Consistency choices:**
- Followed the minimal-but-useful principle (no over-engineering)
- Did not add feature_list.json or claude-progress.md templates (not present in reference templates)
- Did not invent special powers for mission-control beyond what the evidence supports
- init.sh uses `set -euo pipefail` matching all reference templates

---

## Step 4 — Verification Evidence

### Shell Syntax Check
```
bash -n per-repo/mission-control/init.sh → PASS
bash -n server-install.sh → PASS
bash -n server/init.sh → PASS
bash -n scripts/validate-harness.sh → PASS
```

### Validation Script
```
bash scripts/validate-harness.sh
Results: 52 passed | 1 warnings | 0 failures
VALIDATION PASSED WITH WARNINGS

Warning: "files newer than git index after dry-run"
  — Expected: per-repo/mission-control/init.sh and AGENTS.md
  — Not a failure; these files were just created in this session
```

### Dry-Run Output (mission-control section)
```
  Installing harness for: mission-control → /home/slimy/mission-control
  ~ WOULD COPY: per-repo/mission-control/AGENTS.md → /home/slimy/mission-control/AGENTS.md
  ~ WOULD COPY: per-repo/mission-control/init.sh → /home/slimy/mission-control/init.sh
  ⚠  not found in repo: per-repo/mission-control/feature_list.json
  ⚠  not found in repo: per-repo/mission-control/claude-progress.md
```
→ Correct behavior: template recognized, AGENTS.md and init.sh would be copied

---

## Step 5 — What Felt Coherent About v3 Flow

1. **Risk classification before editing** — Forced explicit thinking about blast radius before touching anything. Useful discipline.

2. **Plan-first** — Bounded plan with concrete substeps prevented scope creep. Knew exactly what files to create and what would NOT change.

3. **Inspection requirement** — Inspecting actual reference templates (not guessing) ensured consistency with established conventions.

4. **Verification gate before stopping** — Running `validate-harness.sh` and dry-run before calling it done was the right order.

5. **Trial report as artifact** — Writing up what worked and what was confusing creates a useful record for future Prompt P trials.

---

## Step 6 — Rough Edges and Confusing Parts

1. **Per-repo template minimality is unclear** — It's not documented what the minimum viable per-repo template is. pm_updown_bot_bundle has no feature_list.json or claude-progress.md, but slimy-monorepo also lacks them. The docs say "at minimum AGENTS.md and init.sh" implicitly by showing only those in the template list. A explicit minimum-template spec would help.

2. **HARNESS_ARCHITECTURE.md lists repos without templates** — The doc says "Repos without harness templates: mission-control, clawd, kb..." — this was already out of date before the trial even started. The doc needs either auto-generation or a clear "manually updated" note.

3. **validate-harness.sh warning on new files is noisy** — Check 2 flags files newer than git index after dry-run. This is expected when creating new template files, but the warning makes it seem like a problem. Could be scoped to only warn about existing files.

4. **No explicit guidance on feature_list.json / claude-progress.md in templates** — The existing two templates don't include them. But the architecture doc says they're part of the per-repo scope. Inconsistent. I chose to match the actual existing templates (minimal) rather than the documented spec.

---

## Step 7 — Recommendation

**READY_FOR_BROADER_USE: YES**

Prompt P worked well for this bounded, low-risk task. The discipline of classifying risk, writing a plan, and verifying before stopping added structure without significant overhead.

For higher-risk tasks (modifying server-install.sh, touching production services, changing validation logic), the same Prompt P flow would apply but would warrant more scrutiny in the risk classification step.

---

## Files Changed Summary

| File | Action | Note |
|------|--------|------|
| `per-repo/mission-control/AGENTS.md` | created | New template |
| `per-repo/mission-control/init.sh` | created | New template |
| `docs/V3_TRIAL_REPORT.md` | created | This report |

**Total: 3 new files, 0 modified existing files**
