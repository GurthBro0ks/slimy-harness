# Doc-Sync Hygiene Phase 4 — Verification

## Date
2026-04-16

## Summary
Phase 4 adds daily dedupe so doc auto-sync does not create multiple same-day auto-sync commits on the same repo when nothing materially new needs to be recorded.

## Files Changed

### `/home/slimy/kb/tools/kb-project-doc-sync.sh`
- Added Phase 4 dedupe check after Phase 1/2 guards: if HEAD commit subject matches `docs: auto-sync project docs from <host> YYYY-MM-DD`, check for dirty doc files.
- If no dirty doc files: skip entirely with `SKIP: already auto-synced today (daily dedupe)`.
- If dirty doc files exist: proceed with `NOTE: has today's auto-sync but N new doc change(s) — re-syncing`.

### `/home/slimy/kb/tools/slimy-agent-finish.sh`
- Added `has_auto_sync_today()` function: checks if HEAD commit subject matches today's auto-sync pattern.
- Commit loop: after Phase 1 dirty-tree check, before committing, calls `has_auto_sync_today()`. If true, skips commit with `SKIP commit: already auto-synced today (dedupe)`.

### `/home/slimy/slimy-harness/cheat-sheets/CHEAT_SHEET_FINAL.md`
- Updated Doc-Sync Hygiene section to Phase 1+2+3+4.
- Added Phase 4 guards (daily dedupe + smart dedupe).
- Updated behavior summary table with dedupe rows.

### `/home/slimy/slimy-harness/docs/HARNESS_ARCHITECTURE.md`
- Added Phase 4 daily dedupe to Done list.

## Before/After Behavior

| Scenario | Before Phase 4 | After Phase 4 |
|---|---|---|
| First auto-sync of the day | Creates commit | Creates commit (unchanged) |
| Second auto-sync, no changes | Creates duplicate commit | **Skipped** (daily dedupe) |
| Second auto-sync, new doc changes | Creates duplicate commit | **Re-syncs** with NOTE log |
| Yesterday's auto-sync on HEAD | Normal processing | Normal processing (not blocked) |

## Dedupe Logic (Decision Tree)

```
1. HEAD subject == "docs: auto-sync project docs from <host> <today>"?
   NO → normal processing
   YES → check dirty doc files:
      dirty_count == 0 → SKIP (daily dedupe)
      dirty_count > 0 → proceed with NOTE log (smart dedupe)
```

## Verification Results

All 10 tests PASS:

1. **Syntax checks**: both scripts pass `bash -n`
2. **First doc-sync**: processes normally (creates CHANGELOG.md + VERSION.md)
3. **Auto-sync commit created**: HEAD matches pattern
4. **Second doc-sync (no changes)**: `SKIP: already auto-synced today (daily dedupe)` — PASS
5. **Dirty doc + auto-sync HEAD**: `NOTE: has today's auto-sync but 1 new doc change(s) — re-syncing` — PASS
6. **Yesterday's auto-sync**: not blocked, normal processing — PASS
7. **Phase 1 regression — allowlist**: stoat-source skipped — PASS
8. **Phase 1 regression — dirty-tree**: slimy-harness skipped — PASS
9. **Phase 3 regression — session-scoped**: no broad scan without flags — PASS
10. **Phase 3 regression — --scan-all**: 4 repos detected — PASS

## When a Second Same-Day Auto-Sync Is Allowed

A second same-day auto-sync can occur when:
- A manual or agent change modifies README.md, CHANGELOG.md, or VERSION.md after the first auto-sync
- The doc-sync script detects dirty doc files despite HEAD being today's auto-sync

This is logged with a clear NOTE message for auditability.

## Verification Log
See `verification-output.log` in this directory for full output of all test runs.
