# Doc-Sync Hygiene Phase 2 — Verification Report

**Date:** 2026-04-16
**Host:** slimy-nuc1
**Scope:** kb-project-doc-sync.sh (conditional VERSION.md) + slimy-agent-finish.sh (push-or-revert)

## Files Changed

| File | Change |
|------|--------|
| `kb/tools/kb-project-doc-sync.sh` | VERSION.md now compares content hash (excluding Generated timestamp) before writing |
| `kb/tools/slimy-agent-finish.sh` | Commit/push loop now records pre-commit HEAD, reverts via `git reset --soft` on push failure |
| `slimy-harness/cheat-sheets/CHEAT_SHEET_FINAL.md` | Updated doc-sync section with Phase 2 guards |
| `slimy-harness/docs/HARNESS_ARCHITECTURE.md` | Added Phase 2 items to Done list |

## Phase 2 Guards

### 1. Conditional VERSION.md (ENFORCED)
- New content is built into a variable, then md5-hashed (excluding `> Generated:` timestamp line)
- Compared against existing file's hash (same exclusion)
- If hashes match: skip, log `VERSION.md unchanged — skipped (no content difference)`
- If hashes differ: write new content, update mtime
- Prevents spurious git dirt from timestamp-only changes

### 2. Push-or-Revert (ENFORCED)
- Before auto-sync commit: record `PRE_COMMIT_HASH=$(git rev-parse HEAD)`
- After commit: attempt push
- Push success: log `Pushed $repo`, commit stays
- Push failure: `git reset --soft $PRE_COMMIT_HASH`, log `WARNING: push failed — reverting auto-sync commit`
- HTTPS remote: same revert path (no push possible without credentials)
- Soft reset keeps staged files for retry, removes the commit from history

## Verification Results

| Test | Scenario | Expected | Actual |
|------|----------|----------|--------|
| VERSION unchanged skip | Run twice, same state | VERSION.md not rewritten, mtime preserved | PASS: `same=YES` |
| VERSION changed update | New commit changes hash | VERSION.md rewritten with new HEAD | PASS: `Updated VERSION.md` |
| Push failure revert | Nonexistent remote | Commit reverted, HEAD restored | PASS: HEAD=09d45a5 restored |
| Push success keep | Local bare remote | Commit kept, clean tree | PASS: 7ed4396 in log |
| Phase 1: allowlist | stoat-source | SKIP: not in allowlist | PASS |
| Phase 1: no-remote | /tmp/test-no-remote | SKIP: no remote origin | PASS |
| Phase 1: dirty-tree | slimy-harness | SKIP: non-doc dirty files | PASS |
| Phase 1: allowlisted pass | mission-control | Processed normally | PASS |

## Syntax Check
- `bash -n kb-project-doc-sync.sh` — OK
- `bash -n slimy-agent-finish.sh` — OK

## NOT Implemented (Phase 3+)
- Session-scoped default
- Daily dedupe
