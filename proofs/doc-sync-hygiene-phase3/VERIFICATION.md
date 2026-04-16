# Doc-Sync Hygiene Phase 3 — Verification

## Date
2026-04-16

## Summary
Phase 3 makes doc auto-sync session-scoped by default. The finish automation only touches the active repo unless broad scan is explicitly requested via `--scan-all`.

## Files Changed

### `/home/slimy/kb/tools/slimy-agent-finish.sh`
- Added `--scan-all` flag for explicit broad multi-repo detection
- Changed default behavior: when no `--repo` and no `--scan-all`, no repos are touched (session-scoped default)
- Fixed empty-array iteration bug (`"${REPOS[@]:-}"` → length guard + `"${REPOS[@]}"`)
- Added `Scan-all:` to startup log line

### `/home/slimy/kb/tools/slimy-session-finish.sh`
- Added Phase 3 documentation in header comment
- Added log messages for empty ACTIVE_REPO cases in `run_quiet_finish` and `run_bounded_finish`
- No structural changes needed — already correctly bounded

### `/home/slimy/slimy-harness/cheat-sheets/CHEAT_SHEET_FINAL.md`
- Updated Doc-Sync Hygiene section from "Phase 1 + Phase 2" to "Phase 1 + Phase 2 + Phase 3"
- Added Phase 3 guards documentation
- Added behavior summary table

### `/home/slimy/slimy-harness/docs/HARNESS_ARCHITECTURE.md`
- Added Phase 3 items to Done list

## Before/After Behavior

| Scenario | Before Phase 3 | After Phase 3 |
|---|---|---|
| `slimy-agent-finish.sh` (no flags) | Scans /home/slimy + /opt/slimy for all repos with commits in last 24h | **No repos touched** — session-scoped default |
| `slimy-agent-finish.sh --repo X` | Only repo X | Only repo X (unchanged) |
| `slimy-agent-finish.sh --scan-all` | N/A (flag didn't exist) | Scans /home/slimy + /opt/slimy (explicit opt-in) |
| Stop hook SUCCESS | Active repo only (via session-finish) | Active repo only (unchanged) |
| Stop hook ERROR | Active repo only if set; broad scan if empty | Active repo only if set; **no scan** if empty |
| Stop hook Ctrl+C | No sync (interrupt path) | No sync (unchanged) |

## Verification Results

All 11 tests PASS:

1. **Syntax checks**: both scripts pass `bash -n`
2. **Default path**: no repos touched, "session-scoped default: skipping broad detection" logged
3. **--scan-all**: 4 repos detected and synced (mission-control, slimy-harness, ned-autonomous, clawd)
4. **--repo /home/slimy/clawd**: only clawd synced (1 repo)
5. **session-finish --active-repo clawd**: active repo synced via quiet finish
6. **session-finish (no active repo)**: "No active repo specified — skipping doc sync"
7. **Phase 1 regression — allowlist**: stoat-source correctly skipped
8. **Phase 1 regression — dirty-tree**: slimy-harness correctly skipped
9. **Phase 1 regression — non-pushable**: mailbox_outbox correctly skipped
10. **NUC1 hook wiring**: CLAUDE_PROJECT_DIR passed to session-finish as --active-repo
11. **Broad scan not automatic**: --scan-all NOT present in stop hook command

## Phase 2 Regression
- Conditional VERSION.md: still only rewritten if content differs
- Push-or-revert: still reverts auto-sync commits if push fails

## Hook Wiring (NUC1)
`~/.claude/settings.json` Stop hook:
```json
"command": "bash /home/slimy/kb/tools/slimy-session-finish.sh --active-repo \"${CLAUDE_PROJECT_DIR:-}\" 2>&1"
```

Flow: Stop event → `slimy-session-finish.sh --active-repo $CLAUDE_PROJECT_DIR` → if SUCCESS: `kb-project-doc-sync.sh $ACTIVE_REPO` directly; if ERROR: `slimy-agent-finish.sh --repo $ACTIVE_REPO`. Neither path triggers broad scan.

## Verification Log
See `verification-output.log` in this directory for full output of all test runs.
