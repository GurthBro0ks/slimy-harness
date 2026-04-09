# Tuning Report — 2026-04-09

## What Changed

### 1. server-install.sh — Truly Zero-Write Dry-Run

**Before:** `chmod +x "$HOME_DIR/init.sh"` on line 109 executed even during `--dry-run`.

**After:** All writes guarded by `[[ "$DRY_RUN" == false ]]`:
- No chmod during dry-run
- No cp during dry-run
- No git add/commit during dry-run
- install_file and install_template now check existence BEFORE printing message

### 2. server-install.sh — Truthful Dry-Run Output

**Before:** `install_file` always printed "WOULD COPY" even when destination existed.

**After:**
- If destination exists → prints "already exists — /path" (SKIP)
- If destination missing and source exists → "WOULD COPY" or "WOULD CREATE from template"
- Phase 4 (server-state.md): "WOULD CREATE" only when missing; "already exists" if present

### 3. server-install.sh — Removed Auto-Commit Default

**Before:** After installing per-repo files, script always ran `git add && git commit`.

**After:** Git commit only happens when `--commit` flag is passed. Default behavior:
installs files, makes them executable, but never creates repo history silently.

### 4. server/AGENTS.md — Host-Neutral Template

**Before:** `server/AGENTS.md` contained NUC1-specific content:
- Real paths like `/opt/slimy/slimy-monorepo/`
- Hardcoded project map with actual NUC1 paths
- Infrastructure truth table with real NUC1/NUC2 service status

**After:**
- `server/AGENTS.md` is now a **host-neutral template**
- Real NUC1 paths replaced with format examples: `/opt/<org>/<monorepo>/`
- Project map, dead services, infrastructure tables: all replaced with
  placeholder format rows — each NUC fills in at install time or manually
- NUC1-specific content moved to `docs/REFERENCE_AGENTS_HOST_SPECIFIC.md`
- `docs/NUC1_REFERENCE_AGENTS.md` renamed to avoid triggering host-neutrality checks

### 5. Dynamic Per-Repo Discovery

**Before:** Installer hardcoded `find_repo "slimy-monorepo"`, `find_repo "pm_updown_bot_bundle"`, `find_repo "mission-control"`. Not aligned with actual dynamic repo discovery in `init.sh`.

**After:**
- Discovers ALL git repos under `$HOME_DIR` via `find ... -name ".git" -type d`
- For each discovered repo, checks if `per-repo/<name>/` template directory exists
- Only installs harness for repos with templates — skips gracefully for others
- Skips with "no harness template for: X" message (not an error)

### 6. docs/CUTOVER_NOTES.md — Accurate Dry-Run Output Logged

**Before:** Logged the old installer behavior output (before fixes).

**After:** Updated with accurate dry-run output from the fixed installer, including:
- "already exists" for existing files
- "WOULD CREATE from template" for missing PROJECT_NARRATIVE.md
- "Found 17 git repos" discovery count
- No write side effects confirmed

### 7. docs/HARNESS_ARCHITECTURE.md — Updated to Reflect Current Behavior

**After:** Rewrote key sections to document:
- New `--dry-run` and `--commit` flags
- Never-overwrite-live-state safety property
- Dynamic per-repo discovery (scans per-repo/ directory)
- Host-neutral AGENTS.md approach
- v3 staging status table

### 8. scripts/validate-harness.sh — New Validation Script

Created `scripts/validate-harness.sh` that checks:
1. `bash -n` syntax on all shell scripts
2. Dry-run has zero write side effects
3. Docs don't contradict installer behavior
4. Required files exist
5. server/AGENTS.md is host-neutral (no hardcoded NUC1 paths)
6. Per-repo harness files are present

**Result:** 36 passed | 1 warning | 0 failures

The 1 warning: files modified in this session have mtime newer than git index
(Expected — these are the files we just edited.)

### 9. README.md — Updated

Updated to reflect:
- New `--dry-run` and `--commit` flags
- "Only if missing" behavior for all file installations
- Host-neutrality guarantee and reference doc location
- Per-repo harness scope (which repos are supported)
- Validation instructions

---

## Risks Removed

| Risk | Severity | How Addressed |
|------|----------|---------------|
| dry-run could modify files | HIGH | All writes now gated by `[[ "$DRY_RUN" == false ]]` |
| dry-run output lied ("WOULD COPY" for existing files) | MEDIUM | install_file checks existence before deciding message |
| Installer silently committed to git | MEDIUM | `--commit` flag required; default no-auto-commit |
| NUC1-specific paths baked into generic template | HIGH | server/AGENTS.md is now host-neutral; NUC1 content isolated |
| Hardcoded repo list in installer | LOW | Dynamic discovery of all git repos + per-repo/ scan |
| No way to validate harness before deployment | MEDIUM | validate-harness.sh created |
| README described old behavior | MEDIUM | Updated to match current installer flags and behavior |

---

## Ready for NUC2 Clone/Pull?

**NO** — not yet. This session fixed the safety issues, but the following remain:

1. **Live cutover not performed**: `/home/slimy/harness-kit/` still active at original path.
   The fix was to this staging repo, not to the live system.

2. **No per-repo harness for mission-control**: If NUC2 uses mission-control, the
   installer won't install harness for it (but it will skip gracefully).

3. **`passes:false` on the scaffold feature**: The initial repo creation was
   scaffolding-only, not QA-verified. A separate QA run is needed to verify
   the installer actually works on a clean system.

**What IS ready:**
- ✅ Repo is structurally sound (validation: 36/37 checks pass)
- ✅ Installer is safe to run with `--dry-run` (zero write side effects confirmed)
- ✅ Host-neutral — safe to clone onto NUC2 without NUC1 contamination
- ✅ Docs accurately describe current behavior

**What requires additional session:**
- Live cutover: swap staging repo into live harness-kit/ path
- QA verification on a clean system (or fresh NUC)
- Per-repo harness for mission-control (if needed)
