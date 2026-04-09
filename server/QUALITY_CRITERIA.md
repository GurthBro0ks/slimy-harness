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
