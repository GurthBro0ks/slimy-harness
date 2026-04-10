# Stop Hook Fix — Flow Diagram

## BEFORE (Problem State)

```
[Session Ends: Ctrl+C / SIGINT / Error / Success]
              |
              v
[settings.json Stop hook]
"echo 'SESSION ENDING...'"     <-- only for SUCCESS, not triggered properly
OR
slimy-agent-finish.sh called   <-- if someone set up old hook
              |
              v (if called)
[slimy-agent-finish.sh --agent claude]
  - No --repo args
  - Auto-detects ALL repos under /home/slimy + /opt/slimy with recent commits
  - Runs kb-project-doc-sync.sh on EACH detected repo
  - git commit + push on EACH detected repo
  - If ANY push fails → ALERT_MSG accumulates
  - Posts ALERT to Discord for ANY push failure
  - Runs kb-compile-if-needed (which can spawn child LLM compile run)
  - Child compile run ALSO has a Stop hook → potential recursion
              |
              v
[Discord: ALERT spam across many unrelated repos]
```

**Problems with BEFORE:**
1. No distinction between INTERRUPT, SUCCESS, ERROR
2. Multi-repo scan + push sweep on every finish
3. Discord ALERT on any push failure (including non-critical)
4. No bounded scope — touches ALL repos with 24h commits

---

## AFTER (Fixed State)

```
[Session Ends: Ctrl+C / SIGINT / Error / Success]
              |
              v
[settings.json Stop hook]
bash /home/slimy/kb/tools/slimy-session-finish.sh --active-repo "${CLAUDE_PROJECT_DIR:-}"
              |
              v
[slimy-session-finish.sh]
  - Sets INTERRUPTED=0, captures EXIT_CODE on exit
  - INT trap: INTERRUPTED=1 (if SIGINT received)
  - EXIT trap: calls handle_exit()
              |
    ___________|____________________________________
    |                     |                       |
    v                     v                       v
[INTERRUPTED=1 or     [EXIT_CODE=0]           [EXIT_CODE != 0]
 EXIT_CODE=130]                                    |
    |                     |                       |
    v                     v                       v
"INTERRUPTED —         run_quiet_finish()    run_bounded_finish()
 skipping finish"                                 |
    |                     |                       |
    v                     v                       v
[No Discord alert,    - kb-compile-if-needed  - slimy-agent-finish.sh
 No multi-repo        - Only ACTIVE_REPO         --agent claude
 sweep, quiet exit]     sync if specified        --repo ACTIVE_REPO
                                                 --skip-compile
                                                     |
                                                     v
                                              If finish fails → ALERT
                                              If --quiet passed → skip ALERT

[Discord: bounded ALERT only on real failure]
[Repos: only actively-worked repo touched]
```

**Key distinctions in AFTER:**
1. **INTERRUPTED (Ctrl+C/SIGINT):** quiet exit, NO finish automation, NO Discord ALERT
2. **SUCCESS (exit 0):** bounded quiet finish, kb-compile-if-needed, NO Discord ALERT
3. **ERROR (exit !=0):** bounded finish with alerts, only on real failure

---

## Call Chain: Ctrl+C Path

```
User presses Ctrl+C
    → Claude Code receives SIGINT, stops current operation
    → Claude Code's Stop hook fires
    → bash slimy-session-finish.sh --active-repo "..."
        → Script starts, INTERRUPTED=0
        → User pressed Ctrl+C AFTER script started
            → Script receives SIGINT (INT trap fires)
            → INTERRUPTED=1
            → Script exits (implicit on SIGINT, or explicit exit 130)
        → EXIT trap fires with EXIT_CODE=130 (or INTERRUPTED=1)
        → handle_exit() sees INTERRUPTED=1 or EXIT_CODE=130
        → "INTERRUPTED — skipping finish automation"
        → NO Discord ALERT
        → NO multi-repo sweep
```

---

## Files Changed

| File | Change |
|------|--------|
| `~/.claude/settings.json` | Stop hook now calls slimy-session-finish.sh instead of echo |
| `kb/tools/slimy-session-finish.sh` | NEW: interrupt-aware wrapper with bounded finish logic |
| `kb/tools/slimy-agent-finish.sh` | Added `--quiet` flag and quiet-mode logic for ALERT suppression |

---

## Test Scenarios

| Scenario | Before | After |
|----------|--------|-------|
| Ctrl+C during session | ALERT spam + multi-repo push | Quiet exit, no alert, no push |
| Normal successful finish | ALERT spam if any push fails | Quiet cleanup, kb-compile, no ALERT |
| Error/exit non-zero | ALERT spam + multi-repo push | Bounded ALERT (active repo only) |
| compile-if-needed failure | ALERT posted | Quiet (non-critical) |
| Push failure (non-critical) | ALERT to Discord | Quiet (--quiet mode) |
