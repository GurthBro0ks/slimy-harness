# Doc-Sync Hygiene Phase 1 — Verification Report

**Date:** 2026-04-16
**Host:** slimy-nuc1
**Scope:** kb-project-doc-sync.sh + slimy-agent-finish.sh

## Files Changed

| File | Change |
|------|--------|
| `kb/config/doc-sync-allowlist.txt` | NEW — explicit repo allowlist |
| `kb/tools/kb-project-doc-sync.sh` | Added allowlist check, dirty-tree skip, no-remote skip |
| `kb/tools/slimy-agent-finish.sh` | Added allowlist filter in discovery + commit loops, dirty-tree/non-pushable guards |
| `slimy-harness/cheat-sheets/CHEAT_SHEET_FINAL.md` | Doc-sync hygiene section added |
| `slimy-harness/docs/HARNESS_ARCHITECTURE.md` | Phase 1 items added to Done list |

## Guards Implemented

### 1. Allowlist (ENFORCED)
- File: `kb/config/doc-sync-allowlist.txt`
- 6 repos allowed: slimy-harness, mission-control, kb, slimy-monorepo, clawd, ned-autonomous
- Non-allowlisted repos skipped with log: `SKIP: <path> not in allowlist`
- Override: `DOC_SYNC_ALLOWLIST=/path/to/custom.txt`
- Missing allowlist file = allow all (safe fallback)

### 2. Dirty-Tree Skip (ENFORCED)
- Doc-managed files: README.md, CHANGELOG.md, VERSION.md
- If dirty files outside that set exist, repo skipped: `SKIP: <path> has non-doc dirty files`
- Only-doc-dirty repos pass through normally

### 3. Non-Pushable Skip (ENFORCED)
- No `origin` remote = local-only, skipped: `SKIP: <path> has no remote origin (local-only)`
- Applied in both doc-sync and commit/push loops

## Verification Results

| Test | Repo | Expected | Actual |
|------|------|----------|--------|
| Allowlisted pass | mission-control | processed | PASS |
| Allowlisted pass | clawd | processed | PASS |
| Allowlisted pass | ned-autonomous | processed | PASS |
| Non-allowlisted skip | stoat-source | skipped | SKIP: not in allowlist |
| Non-allowlisted skip | ned-clawd | skipped | SKIP: not in allowlist |
| Non-allowlisted skip | slimy-chat | skipped | SKIP: not in allowlist |
| Dirty-tree skip | slimy-harness (dirty) | skipped | SKIP: non-doc dirty files |
| No-remote skip | /tmp/test-no-remote-repo | skipped | SKIP: no remote origin |
| Dirty-doc-only pass | test repo (VERSION.md dirty) | processed | PASS |
| Dirty-code skip | test repo (main.py dirty) | skipped | SKIP: non-doc dirty files |
| Env override pass | DOC_SYNC_ALLOWLIST=/dev/null | all allowed | PASS |
| Missing allowlist | nonexistent file | all allowed | PASS |
| Full pipeline | finish dry-run | 4 allowlisted, 0 excluded | PASS |

## Syntax Check
- `bash -n kb-project-doc-sync.sh` — OK
- `bash -n slimy-agent-finish.sh` — OK

## Excluded Repos (13 discovered → 6 allowed → 7 skipped)
- /home/slimy/ned-clawd (not in allowlist)
- /home/slimy/ned-clawd/actionbook (not in allowlist)
- /home/slimy/nuc-comms/mailbox_outbox (not in allowlist)
- /home/slimy/slimy-chat (not in allowlist)
- /home/slimy/src/plugins/DynaTech (not in allowlist)
- /home/slimy/src/plugins/PrivateStorage (not in allowlist)
- /home/slimy/src/plugins/Slimefun4 (not in allowlist)
- /home/slimy/stoat-source (not in allowlist)

## NOT Implemented (Phase 2+)
- VERSION.md conditional write
- Push-or-revert policy
- Session-scoped default
- Daily dedupe
