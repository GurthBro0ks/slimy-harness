# SlimyAI Quality Criteria
# Read this before building. QA agent grades against it.

## Criteria (weighted)

### 1. Correctness (weight: 3x)
- Does the feature do what the spec/feature_list says?
- Are there runtime errors, unhandled exceptions, or silent failures?
- Do existing features still work after your changes? (regression check)
- Hard fail: any feature that was working before is now broken.

### 2. Completeness (weight: 2x)
- Is the feature fully implemented or did you stub/skip parts?
- Are edge cases handled (empty inputs, missing data, network failures)?
- Hard fail: any TODO/FIXME/stub left in code that was supposed to be done.

### 3. Integration (weight: 2x)
- Does this feature work with the rest of the system?
- Are APIs wired end-to-end (frontend → API → DB → response → UI)?
- Does the data flow make sense or are there broken handoffs?
- Hard fail: feature works in isolation but breaks when used with other features.

### 4. Code Quality (weight: 1x)
- Readable, reasonable structure, no copy-paste walls.
- No hardcoded secrets, no debug prints left in.
- Tests exist for non-trivial logic.
- Soft fail: won't block a feature but gets noted.

### 5. UX / Surface Quality (weight: 1x)
- Can a user figure out how to use it without reading code?
- Error states show useful messages, not stack traces.
- UI isn't broken on reasonable screen sizes.
- Soft fail: noted for polish pass.

## Scoring
- Each criterion: 0 (broken), 1 (partial), 2 (solid), 3 (excellent)
- Weighted score = sum of (score × weight) / max possible
- **Pass threshold: 70%** — below this, the feature goes back to the builder.
- **Any hard fail = automatic rejection** regardless of score.

## QA Agent Instructions
When grading, you MUST:
1. Actually run the code / hit the endpoints / click the UI
2. Test the happy path AND at least 2 edge cases per feature
3. Check that previously-passing features still pass (regression)
4. Write specific findings, not vague praise — cite file:line when possible
5. If you catch yourself thinking "this is probably fine" — test it anyway

---

## Verification Gate — v3 (Prove-It)

The harness now requires **explicit verification evidence** before a feature
can be marked as passes:true. This applies to both builder self-check and QA evaluation.

### What Must Be Verified

For every feature marked passes:true, the record must include:

1. **Evidence of what was verified** — specific commands run, tests executed, URLs hit
2. **Commands/tests/runbook checks used** — exact commands that confirmed the feature works
3. **Result summary** — what happened when you ran those commands
4. **What remains unverified** — any part of the feature that was NOT tested

### Verification Evidence Format

When updating feature_list.json with passes:true, include in claude-progress.md:

```
Feature: [feature id]
Verified by: [agent name / QA agent]
Date: YYYY-MM-DD

Evidence:
- [exact command 1] → [result]
- [exact command 2] → [result]
- [manual test / screenshot / curl output] → [result]

What was tested:
- Happy path: [what worked]
- Edge cases: [what was tried]

What remains unverified:
- [anything that was NOT tested and why]
```

### Verification Levels

| Level | When | What It Requires |
|-------|------|-----------------|
| BUILD (builder) | Feature work complete | Truth gate passes, manual smoke test |
| QA (evaluator) | passes:true claimed | Independent test of happy path + 2 edge cases, regression confirmed |

### Fail-Closed Rules

- **Builder may NOT set passes:true** without running the truth gate and documenting evidence.
- **QA may NOT accept passes:true** without independently verifying the feature.
- If verification was incomplete (e.g., "could not test edge case X due to missing credentials"), that MUST be documented as "remains unverified".
- Never mark passes:true for features that were only visually inspected but not actually tested.

### Builder vs QA Separation

- **Builder**: writes code, runs truth gate, updates feature_list.json with `passes: false` initially, documents verification evidence in claude-progress.md
- **QA**: independently verifies the feature, confirms or rejects the passes:true claim, updates feature_list.json
- passes:true is only set by QA after actual verification, not by the builder

---

## Risk Classification (v3)

Risk level affects how much planning and verification is required:

| Risk | Description | Plan Required | Verification |
|------|-------------|--------------|--------------|
| low | Small, localized change, well-understood code | Minimal (1-3 steps) | Truth gate + quick smoke test |
| medium | Moderate scope, some uncertainty | Sprint contract with substeps | Truth gate + edge cases |
| high | Large refactor, security-sensitive, or critical services | Full sprint contract + rollback plan | Truth gate + regression + manual test + QA review |

Risk is set in feature_list.json at feature creation time and guides how Prompt P is applied.
