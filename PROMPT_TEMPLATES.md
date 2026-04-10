# Agent Prompt Templates

Copy-paste these when starting agent sessions. Pick the right one for the repo.

---

## CODEX — slimy-monorepo

```
STARTUP (mandatory, do all 5 before any code):
1. cat claude-progress.md
2. cat feature_list.json | python3 -c "import json,sys; d=json.load(sys.stdin); incomplete=[f for f in d['features'] if not f['passes']]; [print(f'{f[\"id\"]}: {f[\"description\"]} [{f[\"priority\"]}]') for f in incomplete]"
3. git log --oneline -10
4. source init.sh
5. Pick the first incomplete CRITICAL feature. If all critical pass, pick highest-priority.

RULES:
- Work on ONE feature only.
- Run `pnpm lint` after every file change.
- Run `pnpm test:all` before marking anything as passing.
- Small commits: `git add -A && git commit -m "feat: <what you did>"`

SHUTDOWN (mandatory, do all 3 before ending):
1. Update feature_list.json — set "passes": true ONLY for features you verified.
2. Append a new entry to the TOP of claude-progress.md with: what you did, what broke, what's next.
3. git add -A && git commit -m "chore: session progress update"
```

---

## CODEX — pm_updown_bot_bundle

```
STARTUP (mandatory, do all 5 before any code):
1. cat claude-progress.md
2. cat feature_list.json | python3 -c "import json,sys; d=json.load(sys.stdin); incomplete=[f for f in d['features'] if not f['passes']]; [print(f'{f[\"id\"]}: {f[\"description\"]} [{f[\"priority\"]}]') for f in incomplete]"
3. git log --oneline -10
4. source init.sh
5. Pick the first incomplete CRITICAL feature.

RULES:
- Work on ONE feature only.
- Keep diffs small and surgical.
- NEVER touch .env*, secrets/, wallet/key/seed material.
- Run ./scripts/run_tests.sh before marking anything as passing.
- Do NOT auto-commit. Leave changes staged.

SHUTDOWN (mandatory, do all 3 before ending):
1. Update feature_list.json — set "passes": true ONLY for features verified by truth gate.
2. Append a new entry to the TOP of claude-progress.md.
3. Write a buglog entry under docs/buglog/ if you fixed a bug.
```

---

## CLAUDE CODE — Universal (works with any repo that has the harness files)

```
Read AGENTS.md first. Follow the startup sequence exactly.
Work on ONE incomplete feature from feature_list.json at a time.
Before ending this session:
- Update feature_list.json with pass/fail status
- Update claude-progress.md with what you did and what's next
- Commit with a descriptive message
```

---

## OPENCLAW / MINIMAX — Universal

```
You are working in a repo with structured agent harness files.

FIRST: Read these files in order:
1. AGENTS.md — your operating manual
2. claude-progress.md — what happened last session
3. feature_list.json — what needs to be done

THEN: Follow the startup sequence in AGENTS.md.
THEN: Work on the highest-priority incomplete feature.

BEFORE STOPPING: Update claude-progress.md and feature_list.json.
```

---

## PROMPT P — Plan-First Work (v3)

```
PROMPT P: PLAN-FIRST WORK MODE (v3)

STEP 0 — Read all harness context before writing any code:
1. cat /home/slimy/AGENTS.md
2. cat /home/slimy/claude-progress.md
3. cat /home/slimy/feature_list.json
4. cat /home/slimy/PROJECT_NARRATIVE.md
5. cat /home/slimy/server-state.md
6. source /home/slimy/init.sh

STEP 1 — Select the feature:
- Pick highest-priority incomplete feature from feature_list.json
- Note its risk level (low/medium/high)

STEP 2 — Classify risk:
- LOW: Small, well-understood → bounded plan, verify with truth gate
- MEDIUM: Moderate, some uncertainty → write sprint-contract.md before coding
- HIGH: Large, security-sensitive, or critical services → write sprint-contract.md with rollback plan

STEP 3 — Write the plan (create /home/slimy/sprint-contract.md):
- WHAT: feature id and description
- RISK: low/medium/high and why
- PLAN: numbered substeps, each with a verification command
- REGRESSION: what must still work after this change
- ROLLBACK: how to undo if it goes wrong

STEP 4 — Verify the plan is sound.

STEP 5 — Execute ONE substep at a time, verifying each.

STEP 6 — Final truth gate + regression check.

STEP 7 — Shutdown: update claude-progress.md, feature_list.json (passes=true ONLY after QA), git commit.
Document what was verified and what remains unverified.

Do NOT skip to coding. A 5-minute plan saves a 2-hour rollback.
```

**When to use:** Any new feature or complex task. Especially HIGH risk ones.
**Key rule:** Write the plan BEFORE editing. Verify each step. Document unverified parts.

---

## PROMPT C2 — Systematic Fix / Debug (v3)

```
PROMPT C2: SYSTEMATIC FIX / DEBUG MODE (v3)

PHASE 1 — OBSERVE (no changes):
- Run truth gate. Record exact failure.
- Check git log for recent changes.
- Note: WHAT fails, HOW, WHEN.

PHASE 2 — HYPOTHESIZE:
- Write ONE specific, falsifiable root cause hypothesis.
- Try to PROVE IT WRONG before accepting it.

PHASE 3 — TEST THE HYPOTHESIS:
- Design minimal test that would disprove it.
- If test disproves → reject hypothesis, back to Phase 2.
- If test confirms → proceed to Phase 4.

PHASE 4 — FIX (smallest diff for confirmed root cause):
- Do NOT make unrelated changes.

PHASE 5 — PROVE THE FIX:
- Truth gate MUST pass.
- Same Phase 3 test MUST now pass.
- Original failure scenario MUST work now.
- Any fail → STOP, revert, return to Phase 1.

PHASE 6 — ESCALATE after 3 failed attempts:
- Suspect architecture issue.
- Document what you tried in claude-progress.md as UNRESOLVED.
- Do NOT leave codebase broken.

FAIL-CLOSED: Cannot find root cause → document what you tried, do NOT random-patch, do NOT mark passes:true.
```

**When to use:** Anything that is broken and needs root-cause debugging.
**Key rule:** Prove the fix works. Random patching is forbidden.
