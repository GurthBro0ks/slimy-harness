# V3 Implementation Plan — SlimyAI Harness

## Overview
Implement the pending Harness v3 feature set on top of the already-live repo-based harness,
without redoing rollout work and without weakening current guardrails.

---

## Step 1 — Audit Summary (COMPLETED)

**Files inspected:**
- `README.md` — staging repo docs, v3 status table
- `server-install.sh` — zero-write dry-run, --commit flag, skip-regex
- `server/AGENTS.md` — host-neutral template
- `server/init.sh` — repo discovery, skip regex
- `server/QUALITY_CRITERIA.md` — 5-criteria weighted QA rubric
- `server/templates/feature_list.json` — minimal schema (features[], _meta)
- `server/templates/PROJECT_NARRATIVE.md` — TODO placeholder
- `auto-prompts.sh` / `auto-prompts.md` — AUTO-WORK, DIRECTED, FIX MODE, HEALTH CHECK, CROSS-PROJECT, OPENCLAW/MINIMAX
- `scripts/validate-harness.sh` — 8 checks + 7b, bash -n, dry-run verification
- `docs/HARNESS_ARCHITECTURE.md` — TOP/BOTTOM pattern, v3 staging status
- `REPORT.md` — tuning history, rollout verdict

**Status:** Repo is clean, v2/v3 boundary clear. All rollout hardening already done.

---

## Step 2 — PROJECT_NARRATIVE Workflow

### 2a. Upgrade `server/templates/PROJECT_NARRATIVE.md` (template in git)
- Add structured sections: Architecture Overview, Risk Zones, Institutional Knowledge,
  Current State, Project Map, Verification/Truth Sources, Known Fragile Areas, Open Questions
- This is the **blank template** that the installer copies to `/home/slimy/PROJECT_NARRATIVE.md`
- Document that live filled narrative lives outside git at `/home/slimy/PROJECT_NARRATIVE.md`

### 2b. Populate live `/home/slimy/PROJECT_NARRATIVE.md` (on host, NOT in git)
- Use real current system knowledge from AGENTS.md, server-state.md, init.sh output
- No secrets, no noisy transient state
- This is for future agent startup context

### 2c. Update README.md
- Document template lives in repo at `server/templates/PROJECT_NARRATIVE.md`
- Document live filled narrative lives at `/home/slimy/PROJECT_NARRATIVE.md` (outside git)

---

## Step 3 — Feature List Schema V3

### 3a. Update `server/templates/feature_list.json`
New schema with backward-compatible extension:
```json
{
  "_meta": {
    "scope": "server-wide",
    "last_updated": "YYYY-MM-DD",
    "rules": "NEVER remove or edit existing features. Only update 'passes' after independent QA verification. Add new features at the end. Each feature has a 'project' field indicating which repo it belongs to."
  },
  "features": [
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
  ]
}
```

### 3b. Update README.md and docs
- Document the new `risk` and `plan[]` fields
- Document `qa_verified` field
- Migration: existing features without `risk`/`plan` treated as `risk: medium, plan: []`

### 3c. No validation logic changes needed
- JSON schema is backward-compatible; existing consumers won't break

---

## Step 4 — Prompt P (Plan-First Work)

### 4a. Create `server/auto-prompts.md` Prompt P section
Add a new section "PROMPT P: PLAN-FIRST WORK MODE" that:
- Reads harness context (AGENTS.md, claude-progress.md, feature_list.json, PROJECT_NARRATIVE.md)
- Classifies risk (low/medium/high)
- Creates a bounded plan before edits
- Includes verification steps before execution
- Records the plan in a durable artifact (sprint-contract.md or feature note)
- Proceeds into execution only after the plan is stated

### 4b. Create `server/auto-prompts.md` Prompt C2 section
Add "PROMPT C2: SYSTEMATIC FIX / DEBUG MODE" that:
- Does structured root-cause debugging (observe, hypothesize, test, conclude)
- Avoids random patching
- Uses a phased approach
- Includes a "prove the fix" step before marking done
- Escalates to architecture suspicion after repeated failure
- Stays fail-closed (if can't find root cause, escalate)

### 4c. Update `PROMPT_TEMPLATES.md`
- Add new prompt P and C2 sections
- Keep existing prompts intact

### 4d. Update `auto-prompts.sh`
- Add shell-executable versions of Prompt P and Prompt C2

---

## Step 5 — Formal Verification Gate

### 5a. Update `server/QUALITY_CRITERIA.md`
- Add explicit verification evidence section
- Require: commands/tests/runbook used, result summary, what remains unverified
- Make clear that passes:true requires QA verification, not just builder self-assessment

### 5b. Update `server/AGENTS.md` startup sequence
- Add PROJECT_NARRATIVE.md to the startup sequence (Step 0 or alongside init.sh)
- Add feature_list.json risk/plan awareness

### 5c. Update startup/shutdown guidance in README
- Add explicit startup section listing all v3 sources: AGENTS.md, claude-progress.md,
  init.sh, PROJECT_NARRATIVE.md, feature_list.json, current v3 prompt mode
- Add explicit shutdown section: progress update, what was verified, whether
  repo/docs/templates changed, whether commit happened, whether QA still required

---

## Step 6 — Docs / Cheat Sheets Sync

### 6a. Update `README.md`
- Add v3 status table with all new features (PROJECT_NARRATIVE, Prompt P, Prompt C2, etc.)
- Update Harness v3 Status table

### 6b. Update `docs/HARNESS_ARCHITECTURE.md`
- Document Prompt P and Prompt C2
- Document risk-aware planning
- Update the "Planned / In-Progress" section

### 6c. Update `cheat-sheets/CHEAT_SHEET_FINAL.md`
- Add Prompt P and Prompt C2 descriptions
- Add risk/plan field explanations
- Add PROJECT_NARRATIVE description

### 6d. Update `cheat-sheets/SERVER_CHEAT_SHEET.md`
- Keep NUC1-specific content separate
- Add v3 prompt mode reference

---

## Step 7 — Validation

- `bash -n` on all shell scripts
- `bash scripts/validate-harness.sh`
- `bash ./server-install.sh --dry-run`
- Sanity-check docs for internal contradictions
- Confirm no live cutover behavior was reintroduced
- Confirm feature_list template/docs align
- Confirm QA authority still documented correctly

---

## Step 8 — Output / Report

Create `docs/V3_BUILD_REPORT.md` with:
- What v3 changes were implemented
- Which files changed
- What was validated
- What is still pending
- Whether the repo is ready for first v3 trial run
- Recommended follow-up before broad use

---

## File Map (v3 deliverable → files to change)

| Deliverable | Files |
|-------------|-------|
| PROJECT_NARRATIVE template upgrade | `server/templates/PROJECT_NARRATIVE.md` |
| Live PROJECT_NARRATIVE (host) | `/home/slimy/PROJECT_NARRATIVE.md` |
| README docs update | `README.md` |
| feature_list.json V3 schema | `server/templates/feature_list.json` |
| Prompt P (plan-first) | `server/auto-prompts.md`, `auto-prompts.sh`, `PROMPT_TEMPLATES.md` |
| Prompt C2 (systematic fix) | `server/auto-prompts.md`, `auto-prompts.sh`, `PROMPT_TEMPLATES.md` |
| QUALITY_CRITERIA verification gate | `server/QUALITY_CRITERIA.md` |
| AGENTS.md startup/shutdown update | `server/AGENTS.md` |
| HARNESS_ARCHITECTURE v3 update | `docs/HARNESS_ARCHITECTURE.md` |
| CHEAT_SHEET_FINAL v3 update | `cheat-sheets/CHEAT_SHEET_FINAL.md` |
| Validation | `scripts/validate-harness.sh` |
| V3 Build Report | `docs/V3_BUILD_REPORT.md` |
