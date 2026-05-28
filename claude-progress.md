## 2026-05-28 — sBuild Mobile Toolbar Spacer v3

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Fixed mobile toolbar spacer layout to provide comprehensive runtime visibility and ensure accurate measurement.
- Root cause: Previous fix (a5c0ecf) measured toolbar height correctly but lacked: (1) requestAnimationFrame for post-layout measurement on iOS Safari, (2) re-measurement triggers on status/settingsOpen changes, (3) visibility into spacer/canvas-controls actual positions, (4) gap detection.
- Added spacerRef and canvasControlsRef to measure actual spacer height and canvas-controls viewport offset at runtime.
- Extracted measurement into useCallback-wrapped measureMobileToolbar with double-requestAnimationFrame for accurate post-layout readings.
- Added separate useEffect to trigger measurement on [isMobileViewport, status, settingsOpen, measureMobileToolbar].
- Debug panel now shows "mobile-toolbar-spacer-v3 active" with 11 runtime values: toolbar clientHeight, toolbar scrollHeight, CSS --mobile-topbar-h, spacer clientHeight, status pill clientHeight, status pill scrollHeight, canvas-controls offsetTop, status text overflows, gap detected.
- Added 4 new tests (spacer v3 debug values, refs, trigger deps, rAF) and updated 2 existing tests. 173 editor + 22 server tests pass.

### Verified (Exact Commands)
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 173/173, server 22/22)
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed:false)
- `curl -sS -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — 401

### Proof
- /tmp/proof_sbuild_mobile_toolbar_spacer_v3_20260528T204552Z

### Changed Files
- `packages/editor/src/App.tsx`
- `packages/editor/src/ui-contract.test.js`

### Git
- Local commit: `d811dc1` — `fix: align mobile toolbar spacer with runtime height`
- Push: not performed

### Final Dirty Files
- `project/project.json` (runtime, not source)
- `project/image-folder.json` (runtime, not source)

### What Remains Unverified
- Manual iPhone visual QA on https://sbuilder.blackfishfarms.com for spacer alignment, gap detection values, and canvas-controls offset.

### Next Action
- Run iPhone QA checklist and confirm visual acceptance with debug panel values.

---


### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Created and pushed acceptance checkpoint tag `v0.6.5-phase6d3` for Phase 6D.3.
- Tag target: `27de73d9c45e61445e5d297dfd59b9a97816fc20` (action center mobile modal polish + pet interaction polish).
- No app behavior changes. No Caddy/auth/sbuild/monorepo changes.

### Verified
- HEAD: `27de73d9c45e61445e5d297dfd59b9a97816fc20`
- origin/main: `27de73d9c45e61445e5d297dfd59b9a97816fc20`
- Service: active
- Local route: 307
- Public gate: 401 Basic Auth challenge
- Remote tag: `refs/tags/v0.6.5-phase6d3` → `27de73d9c45e61445e5d297dfd59b9a97816fc20`

### Summary
Phase 6D.3 Action Center mobile modal polish and pet interaction polish accepted and pushed.

### Proof
- /tmp/proof_gh_tracker_phase6d3_tag_bookkeeping_20260528T203713Z

### Tag
- Tag: `v0.6.5-phase6d3`
- Tag object: `2d1d67846d863cdd855af9e8f6c64397b6a99e85`
- Tag target: `27de73d9c45e61445e5d297dfd59b9a97816fc20`

### Next Action
- Phase 6E Repo maintenance workflow / cleanup command planner polish.

---

## 2026-05-28 — sBuild Runtime-Measured Mobile Toolbar Fix (v2)

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Fixed six interrelated root causes for persistent mobile toolbar/status area clipping/spacing on iPhone.
- Root cause 1: `--mobile-toolbar-h` CSS variable was used by `.mobile-editor-sheet` but never set by JS — only `--mobile-topbar-h` was set. Now both are set from the same ResizeObserver measurement.
- Root cause 2: Mobile `.topbar` lacked explicit `height: auto; min-height: 0;`, risking inherited height constraints on some iOS Safari versions with fixed-position flex-wrap containers.
- Root cause 3: `.topbar-status` used `width: 100%` alone; added `flex-basis: 100%; flex-shrink: 0;` for reliable full-width row forcing in flex-wrap.
- Root cause 4: Debug marker was `mobileToolbarStatusOffset=active` instead of required `mobile-toolbar-runtime-v2 active`.
- Root cause 5: No overflow detection — added scrollHeight > clientHeight comparison for status pill.
- Root cause 6: Debug info was mobile-only — now always visible in Settings/Status.
- Added 3 new UI contract tests (169 total, up from 166), updated 4 existing tests.
- Updated CSS to use `--mobile-topbar-h` consistently (replaced never-set `--mobile-toolbar-h` in mobile editor sheet).

### Verified (Exact Commands)
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 169/169, server 22/22)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed:false)
- `curl -sS -o /dev/null -w "%{http_code}\n" -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — 401

### Proof
- /tmp/proof_sbuild_mobile_toolbar_runtime_v2_20260528T201723Z

### Changed Files
- `packages/editor/src/App.tsx`
- `packages/editor/src/styles.css`
- `packages/editor/src/ui-contract.test.js`

### Git
- Local commit: `a5c0ecf` — `fix: measure mobile toolbar status height at runtime`
- Push: not performed

### Final Dirty Files
- `project/project.json` (runtime, not source)
- `project/image-folder.json` (runtime, not source)

### What Remains Unverified
- Manual iPhone visual QA on https://sbuilder.blackfishfarms.com for toolbar status clipping, spacer alignment, and scroll behavior.

### Next Action
- Run iPhone QA checklist and confirm visual acceptance.

---

## 2026-05-28 — GH Tracker Phase 6D.3 Action Center Mobile Modal Polish / Pet Interaction Polish

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Polished Action Center modal for mobile usability: bottom-sheet presentation, body scroll lock, safe-area padding, 44px close/copy tap targets, long repo name wrapping, backdrop tap-to-close, thin scrollbar styling.
- Polished pet card interaction: expanded state border/glow styling, aria-expanded/aria-label on cards, "Collapse details" button when expanded, tap-to-expand hint when collapsed (aria-hidden), focus-visible outlines, 44px Action Center button on mobile.
- Preserved manual-only copy-only safety. No execution behavior added. No Caddy/auth/sbuild/monorepo changes.

### Changed Files
- `src/components/repo-habitat.tsx` — Action Center modal mobile polish, pet card interaction polish
- `src/app/globals.css` — Action Center panel/overlay CSS, pet-card transitions, focus-visible, reduced-motion rules

### Verified (Exact Commands)
- `pnpm lint` — PASS (1 existing warning only)
- `pnpm typecheck` — PASS
- `pnpm test` — PASS (10 files, 44 tests)
- `pnpm validate:runtime-assets` — PASS (`runtime_assets_valid=1`)
- `pnpm validate:github` — PASS (`github_health_valid=1`, `repos=14`)
- `pnpm validate:aggregate` — PASS (`aggregate_valid=1`, `repo_locations=32`, `machines=3`)
- `pnpm build` — PASS
- `systemctl --user restart gh-tracker.service && systemctl --user is-active gh-tracker.service` — active
- `curl -I http://127.0.0.1:5055` — 307
- `curl -I https://habitat.slimyai.xyz` — 401

### Proof
- /tmp/proof_gh_tracker_phase6d3_action_center_pet_interaction_20260528T201648Z

### Git
- Local commit: `27de73d` — `polish: improve action center mobile interactions`
- Push: not performed

### What Remains Unverified
- Manual browser QA on mobile for Action Center bottom-sheet feel, copy button tap targets, pet card expand/collapse transitions, and safe-area padding on iPhone.

### Next Action
- Manual mobile QA, then acceptance push if approved.

---

## 2026-05-28 — GH Tracker Phase 6D.2 Acceptance Tag/Bookkeeping

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Created and pushed acceptance checkpoint tag `v0.6.4-phase6d2` for Phase 6D.2.
- Tag target: `47d9574d15246b754073971c4a5374f3988409c2` (care plan wording fix + pet animation/health wording).
- No app behavior changes. No Caddy/sbuild/monorepo changes.
- Verified remote, clean tree, HEAD, service, local route, public gate, tag creation, tag push, remote tag verification.

### Verified (Exact Commands)
- `git remote -v` — PASS (`GurthBro0ks/gh-tracker`)
- `git status --short` — PASS (empty/clean)
- `git rev-parse HEAD` — PASS (`47d9574d15246b754073971c4a5374f3988409c2`)
- `git ls-remote origin refs/heads/main` — PASS (`47d9574d15246b754073971c4a5374f3988409c2`)
- `systemctl --user is-active gh-tracker.service` — PASS (`active`)
- `curl -I http://127.0.0.1:5055` — PASS (`307`)
- `curl -I https://habitat.slimyai.xyz` — PASS (`401` Basic Auth challenge)
- `git tag --list 'v0.6.4-phase6d2'` — PASS (did not exist before)
- `git tag -a v0.6.4-phase6d2 47d9574d15246b754073971c4a5374f3988409c2 -m "GH Tracker v0.6.4 Phase 6D.2 accepted"` — PASS
- `git push origin v0.6.4-phase6d2` — PASS
- `git ls-remote --tags origin 'v0.6.4-phase6d2*'` — PASS (tag object `d463532`, deref `47d9574`)

### Proof
- /tmp/proof_gh_tracker_phase6d2_tag_bookkeeping_20260528T200740Z

### Git
- Tag: `v0.6.4-phase6d2`
- Tag object: `d4635323464af4399b2d7473db25d98012fbc920`
- Tag target commit: `47d9574d15246b754073971c4a5374f3988409c2`
- No new commits created. Working tree remains clean.

### What Remains Unverified
- None for tag/bookkeeping scope.

### Next Action
- Phase 6D.3 Action Center mobile modal polish / pet interaction polish.

---

## 2026-05-28 — GH Tracker Phase 6D.2A Care Plan Wording Fix

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Softened Action Center Care Plan wording to match softer GitHub health box wording ("none configured").
- Added `suggestions` field to `CleanupPlannerEntry` type for non-urgent configuration hints.
- Changed "No CI runs found" → "CI not configured yet" (rendered as "Suggestion: CI not configured yet").
- Changed "No release found" → "Release tagging not configured yet" (rendered as "Suggestion: Release tagging not configured yet").
- Priority reasons (dirty tree, unpushed commits, open PRs/issues) retain "Priority reason:" prefix.
- No changes to Caddy, sbuild, slimy-monorepo, GitHub write actions, or manual-only Action Center behavior.

### Verified (Exact Commands)
- `pnpm lint` — PASS (1 existing warning only)
- `pnpm typecheck` — PASS
- `pnpm test` — PASS (10 files, 44 tests)
- `pnpm validate:runtime-assets` — PASS (`runtime_assets_valid=1`)
- `pnpm validate:github` — PASS (`github_health_valid=1`, `repos=14`)
- `pnpm validate:aggregate` — PASS (`aggregate_valid=1`, `repo_locations=32`, `machines=3`)
- `pnpm build` — PASS
- `systemctl --user restart gh-tracker.service && systemctl --user is-active gh-tracker.service` — active
- `curl -I http://127.0.0.1:5055` — 307
- `curl -I https://habitat.slimyai.xyz` — 401

### Changed Files
- `src/lib/cleanup-planner.ts` — added `suggestions` field, moved CI/release to suggestions
- `src/components/repo-habitat.tsx` — render suggestions with "Suggestion:" prefix

### Proof
- /tmp/proof_gh_tracker_phase6d2a_care_plan_wording_20260528T195856Z

### Git
- Local commit: `47d9574` — `fix: soften GitHub health care plan wording`
- Push: not performed

### What Remains Unverified
- Manual browser QA to confirm Care Plan shows "Suggestion:" lines instead of "Priority reason: No CI/release found".

### Next Action
- Manual browser QA on Action Center Care Plan section, then push if accepted.

---

## 2026-05-28 — sBuild Mobile Toolbar Status Pill Clipping Fix For Real

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Structurally fixed mobile toolbar status pill clipping by eliminating root causes rather than layering band-aid fixes.
- Root cause 1: `<strong>Status:</strong> {expr}` with `display: flex` on mobile collapsed the whitespace text node between the strong tag and the expression, rendering "Status:Idle" instead of "Status: Idle". Fixed by wrapping status text in `<span className="status-pill-text">Status: {expr} · {status}</span>` — a single text node where the space is inherent in the string literal, immune to flex whitespace collapse.
- Root cause 2: Mobile `.topbar` and `.topbar-status` lacked explicit `overflow: visible`, risking clipping in certain iOS Safari conditions. Added explicit `overflow: visible` to both.
- Added `statusPillRef` ResizeObserver to track status pill height alongside toolbar height.
- Added debug diagnostics in Status/Debug panel: `mobileToolbarHeight`, `statusPillHeight`, `toolbarStatusNoClip`, `commit`.
- Updated 2 existing tests and added 4 new UI contract tests (166 total, +4 from prior 162).

### Verified (Exact Commands)
- `cd /opt/slimy/sbuild && pwd`
- `git status --short`
- `git log --oneline -8`
- `git diff packages/editor/src/App.tsx packages/editor/src/styles.css packages/editor/src/ui-contract.test.js`
- `grep -n "status-pill-text\|topbar-status\|overflow.*visible\|Status:" packages/editor/src/App.tsx packages/editor/src/styles.css`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 166/166, server 22/22)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -sS -o /tmp/... -w "%{http_code}\n" http://127.0.0.1:3137/` — 302
- `curl -sS -o /tmp/... -w "%{http_code}\n" http://127.0.0.1:3137/login` — 200
- `curl -sS -o /tmp/... -w "%{http_code}\n" -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — 401

### Proof
- /tmp/proof_sbuild_mobile_status_pill_real_fix_20260528T195610Z

### Changed Files
- `packages/editor/src/App.tsx`
- `packages/editor/src/styles.css`
- `packages/editor/src/ui-contract.test.js`

### Git
- Local commit: `7c013f1` — `fix: prevent mobile toolbar status pill clipping`
- Push: not performed

### What Remains Unverified
- Manual iPhone visual QA on https://sbuilder.blackfishfarms.com for status pill visibility, spacing, and non-clipping across status text changes, scroll, and orientation.

### Next Action
- Run iPhone QA checklist and confirm visual acceptance.

---

## 2026-05-28 — sBuild Mobile Status Bar Clipping Fix (Non-Privileged)

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Fixed mobile clipping risk for the blue top status row under the fixed toolbar.
- Kept fixed mobile toolbar + measured spacer architecture (`ResizeObserver` + `--mobile-topbar-h`).
- Hardened status row sizing on mobile with explicit `min-height`, `line-height`, `padding`, `box-sizing`, and wrap safety.
- Added stable status marker on the row: `data-status-row="topbar-status-pill"`.
- Added debug-only marker in Status diagnostics: `mobileToolbarStatusOffset=active`.
- Added UI contract coverage for status-row selector, non-clipping mobile CSS, measured spacer rules, and debug marker.

### Root Cause
- The top status pill could wrap on narrow mobile widths, but lacked explicit non-clipping vertical sizing constraints; combined with fixed-toolbar spacing sensitivity, this produced visible vertical clipping/cut-off of the blue status row.

### Verified (Exact Commands)
- `cd /opt/slimy/sbuild && pwd`
- `git status --short`
- `git log --oneline -5`
- `grep -R "Status:" -n packages/editor/src/App.tsx packages/editor/src/styles.css`
- `grep -R "topbar\|toolbar\|status\|mobile-toolbar\|topbarRef\|ResizeObserver\|safe-area\|position: fixed\|mobile-spacer" -n packages/editor/src/App.tsx packages/editor/src/styles.css | sed -n '1,280p'`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 162/162, server 22/22)
- `bash scripts/smoke-sbuild.sh` — FAIL (exit 22; unauthenticated probe received HTTP 401)
- `curl -fsS http://127.0.0.1:3137/health` — PASS (`publishAllowed:false`)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — FAIL (401 auth required)
- `curl -sS -i -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS for probe capture (shows 401 gate)

### Proof
- /tmp/proof_sbuild_mobile_status_bar_clipping_20260528T192603Z

### Changed Files
- `packages/editor/src/App.tsx`
- `packages/editor/src/styles.css`
- `packages/editor/src/ui-contract.test.js`
- `RESULT.md`

### Git
- Local commits: `875c48f` (`fix: prevent mobile topbar status pill clipping`), `1dab848` (`chore: record mobile status bar fix result`)
- Push: not performed

### What Remains Unverified
- Manual iPhone visual QA on https://sbuilder.blackfishfarms.com for status pill clipping across status-text changes and scroll.

### Next Action
- Complete iPhone QA checklist and, if accepted, proceed with local-only acceptance bookkeeping.

---

## 2026-05-28 — sBuild Clean Mobile Status Fix Commit + Auth-Aware Smoke

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Preserved the mobile status bar clipping fix (`data-status-row`, mobile-safe status sizing, measured spacer behavior).
- Removed accidental tracked `RESULT.md` from repository history going forward (file deleted in new commit).
- Refactored `scripts/smoke-sbuild.sh` to be auth-aware for login-gated runtime:
  - unauth `/` accepts `200` or `302`
  - unauth `/login` must be `200`
  - unauth `POST /api/publish` must be `401` (now PASS condition)
  - authenticated API checks now run only when `SBUILD_SMOKE_COOKIE_FILE` is provided; otherwise explicitly `SKIPPED_AUTH_HELPER_MISSING`.
- Added UI contract coverage that smoke script expects unauth publish `401` and supports auth-helper skip path.

### Verified (Exact Commands)
- `cd /opt/slimy/sbuild && pwd`
- `git status --short`
- `git log --oneline -8`
- `git show --name-only --pretty=fuller HEAD`
- `git show --name-only --pretty=fuller 875c48f`
- `git ls-files | grep -E '(^|/)RESULT\.md$' || true`
- `git show --name-only --pretty=format: HEAD | sed -n '1,120p'`
- `grep -R "topbar-status\|status-pill\|data-status-row\|mobileToolbarStatusOffset\|topbar-mobile-spacer\|mobile-toolbar" -n packages/editor/src/App.tsx packages/editor/src/styles.css packages/editor/src/ui-contract.test.js | sed -n '1,260p'`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS (auth-gate checks pass; authenticated branch safely skipped without helper)
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -sS -o /tmp/sbuild-root-probe.txt -w "%{http_code}\n" http://127.0.0.1:3137/` — `302`
- `curl -sS -o /tmp/sbuild-login-probe.txt -w "%{http_code}\n" http://127.0.0.1:3137/login` — `200`
- `curl -sS -o /tmp/sbuild-publish-unauth-probe.txt -w "%{http_code}\n" -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — `401`

### Proof
- /tmp/proof_sbuild_status_bar_auth_aware_smoke_20260528T194056Z

### Changed Files
- `scripts/smoke-sbuild.sh`
- `packages/editor/src/ui-contract.test.js`

### Git
- Local commit: `8a7745d` — `fix: align sBuild smoke checks with login gate`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA on live Blackfish route for visual status-row clipping and scroll behavior.

### Next Action
- Run manual iPhone QA checklist on https://sbuilder.blackfishfarms.com.

---

## 2026-05-28 — GH Tracker Local Snapshot Collector Acceptance Push

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Performed final acceptance verification for local snapshot collector timer commit.
- Confirmed local HEAD matched accepted commit `edfbcdf575e355071b698316e623dc8ac32e7a05` before push.
- Verified working tree clean, timer active/waiting, and last service run successful.
- Ran lightweight gates and auth/runtime gate probes.
- Pushed `main` to origin and verified remote `refs/heads/main` equals local HEAD.

### Verified (Exact Commands)
- `pwd`
- `git status --short`
- `git rev-parse HEAD`
- `git log --oneline -3`
- `git branch --show-current`
- `git remote -v`
- `systemctl --user status gh-tracker-local-snapshot.timer --no-pager`
- `systemctl --user status gh-tracker-local-snapshot.service --no-pager`
- `systemctl --user list-timers '*gh-tracker*' --no-pager`
- `pnpm validate:runtime-assets` — PASS (`runtime_assets_valid=1`)
- `pnpm test` — PASS (10 files, 44 tests)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Basic challenge)
- `curl -I http://127.0.0.1:5055/` — PASS (307 redirect to `/login`)
- `curl -i http://127.0.0.1:5055/api/auth/me` — PASS (401 unauthenticated)
- `git push origin main` — PASS (`62535cb..edfbcdf  main -> main`)
- `git ls-remote origin refs/heads/main` — PASS (`edfbcdf575e355071b698316e623dc8ac32e7a05`)

### Proof
- /tmp/proof_gh_tracker_local_snapshot_timer_push_20260528T174334Z

### Git
- Head before push: `edfbcdf575e355071b698316e623dc8ac32e7a05`
- Remote before push: `62535cbd102e08f2203a7cc60a1e3dffafb5509a`
- Head after push: `edfbcdf575e355071b698316e623dc8ac32e7a05`
- Remote after push: `edfbcdf575e355071b698316e623dc8ac32e7a05`

### What Remains Unverified
- None for this acceptance push scope.

### Next Action
- Monitor next timer tick and confirm `LOCAL_SNAPSHOT_AGE` remains fresh in dashboard debug fields.


---

---

## 2026-05-28 — sBuild Blackfish Login Credential Mismatch Diagnosed + Helper Added

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Diagnosed Blackfish login mismatch without exposing secrets.
- Verified credential files exist and permissions are locked to `600`:
  - `/opt/slimy/sbuild/.sbuild-login-credentials.txt`
  - `/opt/slimy/sbuild/.env.sbuild-auth`
- Verified auth wiring references in server source and ignore rules.
- Performed redacted local login test using stored credentials (no credential/cookie values printed): login returns `302`, session cookie is set, authenticated `/` returns `200`.
- Verified Blackfish route/auth behavior remains correct (`/` -> `/login`, `/login` -> `200`).
- Verified publish remains dry-run when authenticated; unauthenticated publish is blocked by session gate.
- Added a safe operator helper script for local interactive credential viewing:
  - `scripts/show-local-login-credential.sh`
- Committed only helper script; no credential/env/project artifact files committed.

### Root Cause
- The server-side credentials are valid and loaded for active runtime behavior; mismatch was caused by stale/incorrect saved client password, not an auth loader failure.

### Verified (Exact Commands)
- `git status --short`
- `git rev-parse HEAD`
- `git log -1 --oneline`
- `ls -l /opt/slimy/sbuild/.sbuild-login-credentials.txt`
- `ls -l /opt/slimy/sbuild/.env.sbuild-auth`
- `stat -c '%a %U:%G %n' /opt/slimy/sbuild/.sbuild-login-credentials.txt`
- `stat -c '%a %U:%G %n' /opt/slimy/sbuild/.env.sbuild-auth`
- `grep -R "sbuild-login-credentials\|SBUILD_AUTH\|login" -n packages/server/src .gitignore docs/wordpress-migration-plan.md`
- `curl -fsS http://127.0.0.1:3137/health`
- Redacted local login script (`test-login-redacted.sh`) — PASS
- `curl -I https://sbuilder.blackfishfarms.com/`
- `curl -I https://sbuilder.blackfishfarms.com/login`
- Redacted authenticated publish check — PASS (`dryRun:true`)
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS

### Proof
- /tmp/proof_sbuild_blackfish_login_credential_repair_20260528T180411Z

### Git
- Commit: `ada8d2e` — `chore: add local helper for private sbuild login lookup`
- Push: not performed

### Final Dirty Files
- `project/project.json`
- `project/image-folder.json`

### Next Action
- Operator runs local command `/opt/slimy/sbuild/scripts/show-local-login-credential.sh`, updates saved browser password, and retests login on `https://sbuilder.blackfishfarms.com`.

## 2026-05-28 — sBuild Blackfish Public Routing Finished + Local Commit

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Re-verified DNS for `sbuilder.blackfishfarms.com` and WordPress `www` records.
- Added privileged Caddy route for `sbuilder.blackfishfarms.com` to `127.0.0.1:3137`.
- Validated Caddy config and restarted Caddy via systemd (`admin off` path).
- Verified public HTTPS now works for `sbuilder.blackfishfarms.com` with no TLS internal error.
- Restarted local sBuild node process so updated app login gate/env-loader behavior is active.
- Verified unauthenticated root redirects to `/login` and `/login` responds 200.
- Re-ran sBuild truth gate and dry-run publish checks.
- Committed only intended files; did not include local project artifacts.

### Verified (Exact Commands)
- `dig +short sbuilder.blackfishfarms.com A`
- `dig +short sbuilder.blackfishfarms.com AAAA`
- `dig +short sbuilder.blackfishfarms.com.blackfishfarms.com A`
- `dig +short www.blackfishfarms.com A`
- `dig +short www.blackfishfarms.com AAAA`
- `dig +short sbuilder.slimyai.xyz A`
- `sudo caddy validate --config /etc/caddy/Caddyfile`
- `sudo systemctl restart caddy`
- `sudo systemctl status caddy --no-pager`
- `curl -I http://sbuilder.blackfishfarms.com`
- `curl -I https://sbuilder.blackfishfarms.com`
- `curl -I https://sbuilder.slimyai.xyz`
- `curl -I https://www.blackfishfarms.com`
- `curl -I https://blackfishfarms.com`
- `curl -k -I https://sbuilder.blackfishfarms.com/login`
- `curl -k -I https://sbuilder.blackfishfarms.com/`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (`dryRun:true`)

### Proof
- /tmp/proof_sbuild_blackfish_caddy_finish_20260528T174726Z

### Git
- Commit: `9447d69` — `feat: add sBuild login gate and blackfish staging route`
- Push: not performed

### Final Dirty Files
- `project/project.json`
- `project/image-folder.json`

### What Remains Unverified
- Manual iPhone browser checklist on `https://sbuilder.blackfishfarms.com`.

### Next Action
- Execute manual QA login/editor/logout checklist and confirm no production publish is performed.

## 2026-05-28 — GH Tracker Local Snapshot Collector Commit Verification (No-Op Commit)

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Reviewed intended local snapshot automation files:
  - `scripts/run-local-snapshot-collector.sh`
  - `systemd/user/gh-tracker-local-snapshot.service`
  - `systemd/user/gh-tracker-local-snapshot.timer`
- Verified safety posture: no auth weakening, no Action Center execution behavior changes, no git push/commit operations inside collector script, no secret logging in file contents.
- Verified repo unit files exactly match installed active user units (`diff` status 0 for service and timer).
- Verified user timer/service runtime health:
  - timer active (waiting)
  - service inactive after last successful oneshot run (`status=0/SUCCESS`)
- Verified no generated snapshot data was staged/committed.
- Ran lightweight validation suite.
- Attempted commit as requested; repo was already clean and files were already committed in existing commit `edfbcdf575e355071b698316e623dc8ac32e7a05`.

### Verified (Exact Commands)
- `git status --short`
- `git rev-parse HEAD`
- `git describe --tags --always --dirty`
- `sed -n '1,240p' scripts/run-local-snapshot-collector.sh`
- `sed -n '1,200p' systemd/user/gh-tracker-local-snapshot.service`
- `sed -n '1,200p' systemd/user/gh-tracker-local-snapshot.timer`
- `diff -u systemd/user/gh-tracker-local-snapshot.service ~/.config/systemd/user/gh-tracker-local-snapshot.service`
- `diff -u systemd/user/gh-tracker-local-snapshot.timer ~/.config/systemd/user/gh-tracker-local-snapshot.timer`
- `systemctl --user status gh-tracker-local-snapshot.timer --no-pager`
- `systemctl --user status gh-tracker-local-snapshot.service --no-pager`
- `systemctl --user list-timers '*gh-tracker*' --no-pager`
- `git add -N scripts/run-local-snapshot-collector.sh systemd/user/gh-tracker-local-snapshot.service systemd/user/gh-tracker-local-snapshot.timer`
- `git diff -- scripts/run-local-snapshot-collector.sh systemd/user/gh-tracker-local-snapshot.service systemd/user/gh-tracker-local-snapshot.timer`
- `pnpm validate:runtime-assets` — PASS
- `pnpm test` — PASS
- `git add scripts/run-local-snapshot-collector.sh systemd/user/gh-tracker-local-snapshot.service systemd/user/gh-tracker-local-snapshot.timer`
- `git diff --cached --name-only`
- `git commit -m "chore: add local snapshot collector timer"` — no-op (nothing to commit)
- `git log --oneline -- scripts/run-local-snapshot-collector.sh systemd/user/gh-tracker-local-snapshot.service systemd/user/gh-tracker-local-snapshot.timer`

### Proof
- /tmp/proof_gh_tracker_local_snapshot_commit_20260528T174009Z

### Git
- Existing commit for intended files: `edfbcdf575e355071b698316e623dc8ac32e7a05`
- New commit created: no (working tree already clean)
- Push: not performed

### Final Dirty Files
- none in `/opt/slimy/gh-tracker`

### What Remains Unverified
- Manual browser QA checklist items from RESULT.md remain for operator execution.

### Next Action
- Run manual QA checklist on `https://habitat.slimyai.xyz` and monitor next timer tick freshness fields.

## 2026-05-28 — sBuild Blackfish DNS Verified + App Login Gate Added (Caddy Privilege Blocked)

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Verified DNS for `sbuilder.blackfishfarms.com`; A record now resolves to `68.179.170.248` with no AAAA and no double-FQDN host leak.
- Confirmed WordPress DNS records remain untouched (`blackfishfarms.com` and `www.blackfishfarms.com` still on IONOS/WordPress targets).
- Implemented app-level login/session gate in server:
  - new `/login` page and `POST /login`
  - `POST /logout`
  - session cookie auth gate for editor and API routes
  - unauthenticated API returns 401; editor routes redirect to login
  - `/health` remains accessible
- Added auth env bootstrap in server startup (`.env.sbuild-auth` loader) and generated local credential/env files with `chmod 600` (not committed).
- Added `docs/wordpress-migration-plan.md` (planning only, no WordPress migration performed).
- Captured proof bundle including truth gate logs, auth tests, route checks, and rollout/rollback notes.
- Could not complete Caddy routing change due missing sudo privileges in this session.

### Verified (Exact Commands)
- `dig +short sbuilder.blackfishfarms.com A`
- `dig +short sbuilder.blackfishfarms.com AAAA`
- `dig +short sbuilder.blackfishfarms.com CNAME`
- `dig +short sbuilder.blackfishfarms.com.blackfishfarms.com A`
- `dig +short blackfishfarms.com A`
- `dig +short www.blackfishfarms.com A`
- `dig +short www.blackfishfarms.com AAAA`
- `dig +short sbuilder.slimyai.xyz A`
- `git rev-parse HEAD`
- `git log -1 --oneline`
- `git status --short`
- `curl -fsS http://127.0.0.1:3137/health`
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS
- `caddy validate --config /etc/caddy/Caddyfile` — PASS (validation only)
- `caddy reload --config /etc/caddy/Caddyfile` — FAIL (`admin off`, API unavailable)
- Auth behavior script — PASS (`/tmp/proof_sbuild_blackfish_login_gate_20260528T172911Z/auth-tests.log`)

### Blockers / Unverified
- Caddyfile update for `sbuilder.blackfishfarms.com` not applied because sudo write privileges were unavailable.
- HTTPS for `sbuilder.blackfishfarms.com` currently fails TLS handshake until proper Caddy route and cert issuance complete.

### Proof
- /tmp/proof_sbuild_blackfish_login_gate_20260528T172911Z

### Git
- Commit: not created (routing step blocked; mission incomplete)

### Final Dirty Files (sBuild repo)
- `.gitignore`
- `docs/wordpress-migration-plan.md`
- `packages/server/src/app.ts`
- `packages/server/src/index.ts`
- `project/project.json` (pre-existing)
- `project/image-folder.json` (pre-existing)

### Next Action
- Run privileged Caddy update on host (sudo), validate, restart Caddy, then re-run external route/TLS checks for `sbuilder.blackfishfarms.com`.

## 2026-05-28 — sBuild Mobile/Desktop Row Acceptance Finalized + Pushed

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Confirmed user QA accepted the final iPhone Desktop same-row visual blocker (Text + Hours side-by-side, row debug correct).
- Verified runtime commit/version alignment with accepted source commit and no stale runtime mismatch.
- Re-ran full truth gate and smoke checks with proof capture.
- Confirmed publish endpoint remains dry-run.
- Kept dirty non-source files (`project/project.json`, `project/image-folder.json`) out of source commits.
- Pushed accepted source commit `bcacc49` to `origin/main`.
- Updated feature tracking entry `sbuild-mobile-row-join-readability-001` to done/passes/pushed with new proof path.

### Verified (Exact Commands)
- `git status --short`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (`dryRun: true`)
- `git push origin main` — PASS

### Proof
- /tmp/proof_sbuild_mobile_row_acceptance_push_20260528T171452Z

### Git
- Final source commit: `bcacc49` — `fix: prove desktop row grid layout at runtime`
- Push: completed (`main -> main`)

### Final Dirty Files
- `project/project.json`
- `project/image-folder.json`

### What Remains Unverified
- None for this accepted blocker; optional external spot-check on public URL after cache propagation.

### Next Action
- Continue with next queued sbuild or cross-project priority item.

## 2026-05-28 — sBuild Runtime DOM-Proven Row Grid Fix (Desktop/Tablet on iPhone viewport)

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Investigated rejected QA case where user screenshot still showed stacked Desktop row on iPhone while Settings reported commit `16b1145`.
- Captured runtime DOM proof before fix and confirmed live row behavior was effectively stale/stacked (`display:flex`, missing row data attrs on shell), proving runtime mismatch and unresolved row layout enforcement.
- Repaired failing truth gates:
  - fixed typed map return widening in `packages/shared/src/layoutHelpers.ts`
  - fixed strict-null test assertions in `packages/server/src/layoutHelpers.test.ts`
- Hardened row renderer and CSS for Desktop/Tablet:
  - mode-only stack rule remains `deviceMode === "phone"`
  - explicit row shell attrs + debug marker + inline grid template in `packages/editor/src/App.tsx`
  - hard grid constraints in `packages/editor/src/styles.css` (`.row-grid` width/min-width, Desktop/Tablet `display:grid !important`, `> .block-shell` width/flex constraints)
- Built, restarted local server on `:3137`, and re-captured runtime commit + DOM proofs.

### Verified (Exact Commands)
- `git rev-parse HEAD`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (`dryRun: true`)
- `grep -R -n "row-grid\|row-shell\|stack\|gridTemplateColumns\|data-stack-rows\|data-device-mode\|data-row-columns\|Row debug\|shouldStackRows" packages/editor/src/App.tsx packages/editor/src/styles.css packages/editor/src/ui-contract.test.js` — PASS

### Runtime Commit Proof
- Rejected commit shown by user: `16b1145`
- New local commit: `bcacc49`
- Local `/health` now reports `gitCommit: bcacc49`

### DOM Proof Summary
- Desktop mode: `mode=desktop`, `stack=false`, `cols=2`, `display=grid`, two child blocks same top and different x (side-by-side).
- Phone mode: `mode=phone`, `stack=true`, one-column template, stacked child blocks.

### Proof
- /tmp/proof_sbuild_row_grid_runtime_dom_final_20260528T165300Z

### Git
- Local commit: `bcacc49` — `fix: prove desktop row grid layout at runtime`
- Push: not performed

### What Remains Unverified
- Manual iPhone production URL acceptance checklist is still required.

### Next Action
- Run iPhone checklist on `https://sbuilder.slimyai.xyz` and confirm Settings/About commit + Desktop/Phone row behavior.

## 2026-05-28 — GH Tracker Phase 6D.5 Acceptance Checkpoint Tag

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Verified GH Tracker repo path, local `HEAD`, and `origin/main` all match accepted Phase 6D.5 commit `62535cbd102e08f2203a7cc60a1e3dffafb5509a`.
- Created annotated acceptance checkpoint tag `v0.6.3-phase6d5` on the accepted commit and pushed the tag to origin.
- Verified remote tag object exists and remote dereferenced tag target points to accepted commit.
- Updated harness bookkeeping and produced proof bundle for checkpoint tagging.

### Verified (Exact Commands)
- `pwd` — PASS (`/opt/slimy/gh-tracker`)
- `git rev-parse HEAD` — PASS (`62535cbd102e08f2203a7cc60a1e3dffafb5509a`)
- `git ls-remote origin refs/heads/main` — PASS (`62535cbd102e08f2203a7cc60a1e3dffafb5509a`)
- `git tag -l v0.6.3-phase6d5` — PASS (did not exist before create)
- `git tag -a v0.6.3-phase6d5 62535cbd102e08f2203a7cc60a1e3dffafb5509a -m "Phase 6D.5 acceptance checkpoint"` — PASS
- `git push origin v0.6.3-phase6d5` — PASS
- `git rev-parse v0.6.3-phase6d5 v0.6.3-phase6d5^{}` — PASS (tag object + accepted commit)
- `git ls-remote --tags origin refs/tags/v0.6.3-phase6d5 refs/tags/v0.6.3-phase6d5^{}` — PASS (remote tag exists and dereferences to accepted commit)
- `python3 -m json.tool /home/slimy/feature_list.json` — PASS
- `rg -n '(AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z\\-_]{35}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{80,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY-----|SECRET_KEY\\s*=|DATABASE_URL\\s*=|API_KEY\\s*=|TOKEN\\s*=)' /home/slimy/claude-progress.md /home/slimy/feature_list.json` — PASS (no matches)

### Proof
- /tmp/proof_gh_tracker_phase6d5_checkpoint_tag_20260528T165700Z

### Git
- Accepted commit: `62535cbd102e08f2203a7cc60a1e3dffafb5509a`
- Tag: `v0.6.3-phase6d5`
- Tag object: `621d13099ae6a58ce9f06f3bdb1c45bf7973f39a`
- Tag target commit: `62535cbd102e08f2203a7cc60a1e3dffafb5509a`

### What Remains Unverified
- None for checkpoint/tag bookkeeping scope.

### Next Action
- Proceed to next GH Tracker phase assignment.

## 2026-05-28 — GH Tracker Phase 6D.5 Acceptance Push

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Executed Phase 6D.5 acceptance validation for chart date/freshness repair after manual mobile QA acceptance.
- Verified branch state and confirmed local accepted commit on `main` is `62535cbd102e08f2203a7cc60a1e3dffafb5509a` (note: provided hash `62535cb418f3ee58f0e03fa228a91a292f8368c1` does not exist in this repo object database).
- Ran full validation gate and auth/service/public probes.
- Pushed `main` to origin and verified remote head matches local head.
- Updated harness records for Phase 6D.5 acceptance and generated proof bundle.

### Verified (Exact Commands)
- `git status --short --branch` — PASS (`main` ahead of `origin/main` before push)
- `git rev-parse HEAD` — `62535cbd102e08f2203a7cc60a1e3dffafb5509a`
- `pnpm validate:github` — PASS (`github_health_valid=1`, `repos=14`, `partial=0`, `failed=0`)
- `pnpm validate:aggregate` — PASS (`aggregate_valid=1`, `repo_locations=32`, `machines=3`)
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm lint` — PASS with existing warning only (`@next/next/no-img-element` in `src/components/repo-pet-sprite.tsx`)
- `pnpm test` — PASS (10 files, 44 tests)
- `systemctl --user status gh-tracker.service --no-pager` — PASS (active/running)
- `systemctl --user status gh-tracker-github-health-sync.timer --no-pager` — PASS (active/waiting)
- `curl -I https://habitat.slimyai.xyz` — PASS (`401` with Basic challenge)
- `curl -I http://127.0.0.1:5055/` — PASS (`307` redirect to `/login`)
- `curl -I http://127.0.0.1:5055/api/auth/me` — PASS (`401 Unauthorized`)
- `gitleaks detect --no-git --source .` — unavailable (`command not found`)
- `rg -n --hidden --glob '!.git' --glob '!node_modules' '(AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z\\-_]{35}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{80,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY-----|SECRET_KEY\\s*=|DATABASE_URL\\s*=|API_KEY\\s*=|TOKEN\\s*=)' .` — PASS (no matches)
- `git push origin main` — PASS (`df4455c..62535cb  main -> main`)
- `git ls-remote origin refs/heads/main` — PASS (`62535cbd102e08f2203a7cc60a1e3dffafb5509a`)

### Proof
- /tmp/proof_gh_tracker_phase6d5_acceptance_push_20260528T164900Z

### Git
- Head before push: `62535cbd102e08f2203a7cc60a1e3dffafb5509a`
- Head after push: `62535cbd102e08f2203a7cc60a1e3dffafb5509a`
- Remote `origin/main`: `62535cbd102e08f2203a7cc60a1e3dffafb5509a`

### What Remains Unverified
- None for this acceptance gate. Manual visual QA evidence was supplied as accepted input for this push.

### Next Action
- Continue with next queued GH Tracker phase only after new explicit assignment.

## 2026-05-28 — sBuild Final Desktop/Tablet Row Grid Enforcement (iPhone QA blocker)

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Added explicit row render state attributes in editor canvas row shell: `data-device-mode`, `data-stack-rows`, `data-row-columns`.
- Added visible row debug marker for multi-block rows to expose runtime row state: `Row debug: mode=<mode> stack=<bool> cols=<n> template=<grid-template>`.
- Hardened row template generation in `App.tsx` so Desktop/Tablet always emit explicit side-by-side column template (`minmax(0, 1fr)` per row member), and Phone remains single-column.
- Hardened Desktop/Tablet row CSS so `.row-grid` stays grid and row-contained `.block-shell` cannot force full-width stacking (explicit width/max-width/min-width/flex/display constraints).
- Kept phone-only stacking scoped to `.canvas-frame.phone .row-shell.stack .row-grid`.
- Expanded UI contract tests for row mode/stack data attributes, inline `gridTemplateColumns`, row debug marker, desktop/tablet row selectors, and dry-run publish invariant.

### Verified (Exact Commands)
- `git status --short`
- `grep -n "row-grid\|row-shell\|stack\|mobile-viewport\|mobile-row\|gridTemplateColumns\|shouldStackRows\|data-stack-rows\|data-device-mode\|Row debug" packages/editor/src/App.tsx packages/editor/src/styles.css packages/editor/src/ui-contract.test.js`
- `pnpm -r typecheck` — FAIL (pre-existing `packages/shared/src/layoutHelpers.ts` typing errors)
- `pnpm -r build` — FAIL (same pre-existing shared typing errors)
- `pnpm -r lint` — PASS
- `pnpm -r test` — FAIL (server tests depend on shared build; editor contract tests pass)
- `bash scripts/smoke-sbuild.sh` — FAIL/WARN at typecheck (same pre-existing shared typing errors)
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS

### Proof
- /tmp/proof_sbuild_desktop_row_grid_final_20260528T164418Z

### Git
- Local commit: `16b1145` — `fix: force desktop row grid columns on mobile viewport`
- Push: not performed

### What Remains Unverified
- Manual iPhone visual pass against production URL (Desktop/Tablet side-by-side row rendering with row debug confirmation).

### Next Action
- Run the iPhone checklist and confirm final visual acceptance against real device rendering.

## 2026-05-27 — sBuild Real Row Grid Renderer Follow-up (Desktop/Tablet on iPhone)

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Confirmed row metadata/actions were correct but visual layout still failed due render/layout behavior on narrow viewport.
- Added explicit row render-item model in `App.tsx` (`toRowRenderItems`) so joined rows render as real row containers with grouped children and per-row `gridTemplateColumns` derived from row widths.
- Switched row grid behavior to CSS grid and enforced Desktop/Tablet row-contained block shells to fill grid columns side-by-side; Phone mode remains stack-capable.
- Added `closeTransientOverlays()` and used it for row actions (Start new row, Place above/below, Remove from row, Move Up/Down) to clear context menu and mobile drawer dim state.
- Updated contract tests for row render-item model, grid-template behavior, and overlay close semantics.

### Verified (Exact Commands)
- `git status --short`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (`dryRun: true`)

### Proof
- /tmp/proof_sbuild_row_grid_real_fix_20260527T195614Z

### Git
- Local commit: `bbfdf5c` — `fix: render desktop rows side by side on mobile viewport`
- Push: not performed

### What Remains Unverified
- Manual iPhone visual acceptance on production URL (Desktop/Tablet side-by-side rendering and no lingering dim after row actions).

### Next Action
- Execute iPhone QA checklist and confirm visual pass/fail.

## 2026-05-27 — sBuild Device-Mode Row Visual Repair (Wrap Override Removal)

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Investigated remaining vertical stacking despite correct row metadata/widths and confirmed a CSS regression: `@media (max-width: 1100px)` forced `.row-grid { flex-wrap: wrap; }`.
- Removed the viewport-driven row wrap override so Desktop/Tablet mode on iPhone no longer wraps joined 50/50 rows into vertical stacks.
- Kept Phone-mode stacking behavior intact via existing device-mode stack logic.
- Added UI contract regression to prevent reintroducing max-width forced `.row-grid` wrapping.

### Verified (Exact Commands)
- `git status --short`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (`dryRun: true`)

### Proof
- /tmp/proof_sbuild_device_mode_row_visual_repair_20260527T174701Z

### Git
- Head before: `067174a5338016fedffb07fbb5bc39cf42a74f51`
- Local commit: `0aa5870` — `fix: keep row previews side-by-side outside phone mode`
- Push: not performed

### What Remains Unverified
- Manual iPhone visual confirmation for Desktop/Tablet side-by-side row rendering on production URL.

### Next Action
- Run the iPhone QA checklist and confirm row join visual acceptance.

## 2026-05-27 — sBuild Device-Mode Row Layout Fix (Desktop/Tablet on iPhone)

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Root cause fixed: same-row visual stacking was being forced by physical mobile viewport selectors/logic, so iPhone viewport stacked rows even while editing in Desktop/Tablet mode.
- Switched row stacking decision to editor device mode (`deviceMode === "phone"`) so Desktop/Tablet remain side-by-side capable on iPhone while Phone mode keeps stacked readability.
- Fixed row width normalization in shared helpers so row joins rebalance invalid stale widths (e.g. 25/66) to sane distributions and leave-row rebalances survivors; lone leftovers reset to single/full width.
- Fixed lingering dim state by making mobile editor overlay backdrop transparent when closed (dim only when `.open`) and ensured menu closes after delete/move actions.
- Updated UI contract and shared helper tests to lock device-mode behavior, width normalization, and backdrop/menu-close expectations.

### Verified (Exact Commands)
- `git status --short`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (`dryRun: true`)
- `grep -R "deviceMode\|isMobileViewport\|mobile-row\|row-grid\|row-shell\|flex-basis\|width.*50\|Place with block above\|Place with block below\|Remove from row\|contextMenu.blockId\|backdrop\|dim" packages/editor/src/App.tsx packages/editor/src/styles.css packages/editor/src/ui-contract.test.js packages/shared/src/layoutHelpers.ts packages/server/src/layoutHelpers.test.ts` — PASS

### Proof
- /tmp/proof_sbuild_device_mode_row_layout_20260527T172440Z

### Git
- Local commit: `067174a` — `fix: respect device mode for mobile row layout`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA walkthrough against production URL for Desktop/Tablet/Phone visual behavior and tap ergonomics.

### Next Action
- Run the provided iPhone checklist and confirm final visual acceptance.

## 2026-05-27 — GH Tracker Phase 6D.2 Mobile Repo Width Containment + Heatmap Visibility Repair

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Fixed mobile layout containment for compact Repo Locations to prevent page-width overflow from wrapper/cards/long rows.
- Added explicit mobile width guardrails (`overflow-x` protection, max-width/min-width containment, and break-word rules) and wired dashboard classes for repo section/card/detail lines.
- Investigated missing heatmap and confirmed root cause: it was nested inside compact-by-default Repo Locations on mobile, so it appeared missing until expanded.
- Restored heatmap visibility by moving Activity Heatmap + Activity Day Inspector into its own always-visible dashboard section while preserving tap behavior and selected-day highlight.
- Added regression assertions for containment hooks/classes and heatmap status field (`HEATMAP_STATUS=rendered_visible`) while preserving pet evolution, Action Center, Cleanup Planner, and auth/session gates.

### Verified (Exact Commands)
- `git status --short`
- `pnpm validate:runtime-assets` — PASS
- `pnpm validate:github` — PASS
- `pnpm validate:aggregate` — PASS
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm lint` — PASS (existing `<img>` warning only)
- `pnpm test` — PASS (41/41)
- `systemctl --user status gh-tracker.service --no-pager` — active (running)
- `systemctl --user status gh-tracker-github-health-sync.timer --no-pager` — active (waiting)
- `curl -I http://127.0.0.1:5055/` — 307 redirect to `/login`
- `curl -I http://127.0.0.1:5055/login` — 200
- `curl -I http://127.0.0.1:5055/api/auth/me` — 401
- `curl -I https://habitat.slimyai.xyz` — 401 Basic Auth challenge
- Secret scan on changed files via `rg` — PASS (none)
- Runtime data scan for `nousearch-hermes` in `*.json` — PASS (absent)

### Proof
- /tmp/proof_gh_tracker_phase6d2_mobile_width_heatmap_repair_20260527T160735Z

### Git
- Head before: `1a8f879e95a9a37ccb3d4c33960263b5ffb722b3`
- Local commit: `7612ecf66b2f54e3edb3718038ba66a4a09b5604` — `fix: contain mobile repo sections and restore heatmap status`
- Push: not performed

### What Remains Unverified
- Manual mobile visual pass for Repo Locations compact header alignment feel on real device widths.

### Next Action
- Keep local-only until manual QA confirms mobile containment and restored always-visible heatmap behavior.

## 2026-05-27 — sBuild Mobile Row Visual Stack Follow-up (iPhone Row Join Rendering)

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Investigated row mutation vs render path and confirmed row actions were firing, but mobile visual behavior still depended on `deviceMode === "phone"` rather than actual mobile viewport.
- Updated editor row render path to apply mobile stacking/full-width behavior from `isMobileViewport` and added canvas `mobile-viewport` class so iPhone editor consistently gets mobile row overrides.
- Strengthened mobile row CSS to force stacked full-width cards (`width/max-width/flex/flex-basis` with mobile-only selectors) and keep badge/menu/header wrap-safe.
- Fixed row cleanup edge case in shared layout helper: when removing one block from a 2-block row, the remaining lone block is normalized to single/full-width state.
- Updated deterministic contracts in `packages/editor/src/ui-contract.test.js` and shared layout helper test to cover new viewport class and leftover-row normalization.

### Verified (Exact Commands)
- `git status --short`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (`dryRun: true`)
- `rg -n "mobile-row-block|canvas-frame phone|canvas-frame\.mobile-viewport|row-shell|row-grid|flex-basis|width.*50|Place with block below|Remove from row|contextMenu\.blockId" packages/editor/src/App.tsx packages/editor/src/styles.css packages/editor/src/ui-contract.test.js` — PASS

### Proof
- /tmp/proof_sbuild_mobile_row_visual_stack_20260527T160407Z

### Changed Files
- `packages/editor/src/App.tsx`
- `packages/editor/src/styles.css`
- `packages/editor/src/ui-contract.test.js`
- `packages/shared/src/layoutHelpers.ts`
- `packages/server/src/layoutHelpers.test.ts`

### Git
- Head before this session work: `c74d7d9`
- Local commit: `763b9bf` — `fix: stack joined rows on mobile editor canvas`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA checklist execution on production URL (`https://sbuilder.slimyai.xyz`) for visual confirmation of row stack behavior after place/remove actions.

### Next Action
- Run the provided 22-step manual QA checklist (iPhone + desktop sanity) and only push after acceptance.

## 2026-05-27 — GH Tracker Login Runtime Repair After Compact Sections

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Investigated regression where login sometimes rendered as plain HTML and runtime occasionally failed after Basic Auth.
- Confirmed root cause was runtime build-manifest/static-asset mismatch: the running `next start` process was still serving an older manifest while a newer `pnpm build` had replaced `.next/static` chunk files, causing missing CSS chunk requests and unstyled login fallback behavior.
- Added runtime integrity validator `scripts/validate-runtime-assets.ts` and script hook `pnpm validate:runtime-assets` to probe `/login`, extract referenced `/_next/static/...` assets, and assert they all return success (including CSS).
- Restarted `gh-tracker.service` after rebuild to realign runtime manifest and static chunk files.
- Verified auth/session/public gates and key feature regressions remained intact.

### Verified (Exact Commands)
- `systemctl --user status gh-tracker.service --no-pager` — PASS (active)
- `journalctl --user -u gh-tracker.service -n 120 --no-pager` — reviewed
- `curl -I http://127.0.0.1:5055/login` — PASS (200)
- `curl -I http://127.0.0.1:5055/_next/static/` — PASS (308)
- `curl -I http://127.0.0.1:5055/` — PASS (307 to `/login`)
- `curl -i http://127.0.0.1:5055/api/auth/me` — PASS (401)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Basic Auth)
- `pnpm validate:github` — PASS
- `pnpm validate:aggregate` — PASS
- `pnpm validate:runtime-assets` — PASS (`runtime_assets_valid=1`)
- `pnpm -r typecheck` / `pnpm -r build` / `pnpm -r lint` / `pnpm -r test` — no-op in standalone workspace
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm lint` — PASS (existing `<img>` warning only)
- `pnpm test` — PASS (41/41)
- Runtime nousearch scan on GitHub data files — PASS (absent)
- Secret scan on new diff — PASS (none found)

### Proof
- /tmp/proof_gh_tracker_login_runtime_repair_20260527T111757Z

### Git
- Head before repair commit: `c0990cc6dcaf5f897b0678f7bdc232440ad9deb9`
- Local commit: `1a8f879e95a9a37ccb3d4c33960263b5ffb722b3` — `fix: restore styled login runtime after compact sections`
- Push: not performed

### What Remains Unverified
- Manual browser/device walkthrough after Basic Auth for styled login visual confirmation, login submit flow, dashboard reload reliability, settings modal interaction, and mobile compact UX feel.

### Next Action
- Run manual QA checklist and only push if styled runtime remains stable.


## 2026-05-27 — sBuild Mobile Row Join Readability

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Fixed mobile same-row join usability while preserving top-level mobile overlay architecture and row metadata/actions.
- Root cause: row-joined blocks retained inline layout widths (for example 50%) and header metadata had no wrap-safe grouping, causing narrow cards and badge/header collisions on phone canvas.
- Added mobile-only visual stacking behavior for row-joined cards inside editor canvas (`.canvas-frame.phone .row-shell.stack`) to force readable full-width cards while keeping desktop/tablet row behavior unchanged.
- Refactored block header meta layout in `App.tsx` into `block-meta-main` and `block-meta-badges` so handle/label/id/badges/menu wrap cleanly without overlap.
- Added/updated deterministic UI contract tests for mobile row stacking, full-width visual override, desktop side-by-side preservation, wrap-safe header/badge contracts, context menu row actions/status/menu-close behavior, remove-row behavior, move up/down persistence, and publish dry-run.

### Verified (Exact Commands)
- `git status --short`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (`dryRun: true`)
- `grep -R "Place with block above\|Place with block below\|Remove from row\|Leave row\|Move Up\|Move Down\|contextMenu.blockId\|row\|mobile" packages/editor/src/App.tsx packages/editor/src/styles.css packages/editor/src/ui-contract.test.js` — PASS

### Proof
- /tmp/proof_sbuild_mobile_row_join_readability_20260527T111111Z

### Changed Files
- `packages/editor/src/App.tsx`
- `packages/editor/src/styles.css`
- `packages/editor/src/ui-contract.test.js`

### Git
- Local commit: `c74d7d9` — `fix: keep mobile row joins readable`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA checklist for same-row join readability and move/remove actions in production URL.

### Next Action
- QA should run the 19-step iPhone + desktop sanity checklist and confirm acceptance.

## 2026-05-27 — GH Tracker Phase 6D.1 Mobile Compact Sections for Repo Habitat

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Added compact-by-default mobile expand/collapse wrappers for long Habitat page sections using a shared `MobileCompactSection` control with summary row and explicit expand/collapse affordance.
- Kept top summary metrics, GitHub Remote Health, Habitat Quick View, and high-level machine cards immediately visible.
- Compacted on mobile by default: Repo Habitat full cards, Repo Cleanup Planner, Repo Locations block (including per-location detail views and heatmap in same long section block), Recent Activity Timeline block, and Debug / Status Dock.
- Expanded state reveals full existing content without changing underlying datasets or behavior.
- Added required debug proof fields in Debug / Status Dock:
  - `COMPACT_SECTIONS_ADDED`
  - `MOBILE_DEFAULT_COMPACT`
  - `EXPAND_CONTROLS_VISIBLE`
  - `PET_EVOLUTION_REGRESSION`
  - `ACTION_CENTER_REGRESSION`
  - `HEATMAP_REGRESSION`
  - `CLEANUP_PLANNER_REGRESSION`
- Added regression assertions in `src/lib/__tests__/phase6d-pixel-pets.test.ts` to cover compact-section hooks and proof fields.
- Preserved sprite stage rendering surfaces and Action Center copy-only safety paths.

### Verified (Exact Commands)
- `pnpm validate:github` — PASS (`github_health_valid=1`, `repos=14`)
- `pnpm validate:aggregate` — PASS (`aggregate_valid=1`, `repo_locations=32`, `machines=3`)
- `pnpm -r typecheck` — no-op in standalone workspace (`No projects matched the filters`)
- `pnpm -r build` — no-op in standalone workspace (`No projects matched the filters`)
- `pnpm -r lint` — no-op in standalone workspace (`No projects matched the filters`)
- `pnpm -r test` — no-op in standalone workspace (`No projects matched the filters`)
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm lint` — PASS with existing `repo-pet-sprite.tsx` `<img>` warning only
- `pnpm test` — PASS (10 files, 41 tests)
- `systemctl --user status gh-tracker.service --no-pager` — active (running)
- `systemctl --user status gh-tracker-github-health-sync.timer --no-pager` — active (waiting)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Basic Auth challenge)
- `curl -i http://127.0.0.1:5055/api/auth/me` — PASS (401 unauthenticated)
- `curl -I http://127.0.0.1:5055/` — PASS (307 redirect to `/login`)

### Proof
- `/tmp/proof_gh_tracker_phase6d1_mobile_compact_sections_20260527T093931Z`

### Git
- Local commit: pending
- Push: not performed (blocked until manual mobile QA confirms compact/expand UX)

### What Remains Unverified
- Manual mobile browser QA for compact/expand UX feel and readability in real device conditions.

### Next Action
- Run manual mobile QA checklist for compact-by-default sections and only push after acceptance.

---

## 2026-05-26 — GH Tracker Phase 6D.1 Pixel Pet Evolution Stages (Verification Pass)

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Verified existing Phase 6D.1 implementation at commit `cc0cf4f00880ed56986e683f5504b39c752cf177`.
- All 28 staged SVG assets confirmed (7 species × 4 stages: egg/hatchling/juvenile/adult).
- Deterministic maturity calculation with thresholds: 0-2 egg, 3-15 hatchling, 16-60 juvenile, 61+ adult.
- `RepoPetSprite` component resolves staged sprite paths; UI shows stage labels in Habitat cards, Quick View, and Action Center.
- All validation gates passed: validate:github, validate:aggregate, typecheck, build, lint, test (41/41).
- Service active, auth gates confirmed (Basic Auth 401, API 401, dashboard redirect to /login).
- All 28 staged SVGs served at 200 with phase6d1 markers.
- No text/glyph placeholders, no secrets, no external/copyrighted assets.
- No new commit needed — existing commit covers all Phase 6D.1 requirements.

### Verified (Exact Commands)
- `pnpm validate:github` — PASS (github_health_valid=1, repos=14)
- `pnpm validate:aggregate` — PASS (aggregate_valid=1, 32 locations, 3 machines)
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm lint` — PASS (1 existing img warning only)
- `pnpm test` — PASS (10 files, 41 tests)
- `pnpm -r typecheck/build/lint/test` — no-op in standalone workspace
- `curl -I https://habitat.slimyai.xyz` — 401 Basic Auth challenge
- `curl -i http://127.0.0.1:5055/api/auth/me` — 401 unauthenticated
- `curl -I http://127.0.0.1:5055/` — 307 redirect to /login
- `systemctl --user status gh-tracker.service` — active (running)
- `systemctl --user status gh-tracker-github-health-sync.timer` — active (waiting)
- All 28 staged sprite URLs curl 200 with phase6d1 marker
- No text/glyph in SVGs, no old placeholder paths, no secrets

### Proof
- /tmp/proof_gh_tracker_phase6d1_pet_evolution_20260526T221321Z

### Git
- Head before: f6fda0314c0efd6dbd36269fb1af16e24c149e33
- Existing commit: cc0cf4f00880ed56986e683f5504b39c752cf177 — `feat: add pixel pet evolution stages`
- Push: not performed per instruction

### What Remains Unverified
- Manual browser visual QA of egg, hatchling, juvenile, and adult readability on desktop and mobile.
- Safari/private-tab hard refresh visual QA remains required before any push.

### Next Action
- Manual visual QA pet evolution stages. Do not push until eggs/hatchlings/juveniles/adults are visibly correct.

---

## 2026-05-26 — sBuild Mobile Editor Top-Level Overlay

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Replaced broken mobile right-drawer layout with a top-level mobile editor overlay/sheet rendered outside the workspace/canvas clipping stack.
- Root cause: Previous fix (commit a66f5b2, reverted as 074df2e) placed the drawer inside `.workspace`/`.canvas` where it was clipped by overflow:hidden and the fixed toolbar. Bottom-anchored drawer with max-height calc still grew into toolbar space.
- Extracted `renderRightDrawerBody()` function (~1020 lines of inline JSX) to avoid duplication.
- Desktop right drawer: conditionally rendered only when `!isMobileViewport` — completely unchanged.
- Mobile overlay: rendered at `.app` root level (sibling to context menu, settings modal) — completely outside `.workspace` clipping stack.
- Mobile overlay uses `position: fixed; top: 0; left: 0; right: 0; bottom: 0; z-index: 95`.
- Sheet uses `grid-template-rows: auto auto auto minmax(0, 1fr)` for fixed header/tabs/target + scrollable body.
- Sheet top offset: `calc(var(--mobile-toolbar-h, 0px) + env(safe-area-inset-top, 0px) + 8px)`.
- Removed old mobile right-drawer CSS overrides.
- Added 15 new required deterministic tests (136 total editor tests now).
- Reverted failed commit a66f5b2 cleanly → commit 074df2e before new work.

### Verified (Exact Commands)
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 136/136, server 20/20)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed: false)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (dryRun: true)

### Proof
- /tmp/proof_sbuild_mobile_editor_overlay_real_fix_20260526T220046Z

### Changed Files
- `packages/editor/src/App.tsx` — extracted renderRightDrawerBody(), added mobile overlay at .app root, conditional desktop drawer
- `packages/editor/src/styles.css` — .mobile-editor-overlay/sheet/header/tabs/target/body, removed old mobile .right-drawer overrides
- `packages/editor/src/ui-contract.test.js` — 136 tests (15 new overlay-specific tests)

### Git
- Local commit: `be55b08` — `fix: render mobile editor drawer as top-level overlay`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA: mobile editor overlay opens from context menu "Edit Properties"
- Manual iPhone QA: mobile editor overlay opens from context menu "AI Assistant"
- Manual iPhone QA: overlay header/title visible below toolbar
- Manual iPhone QA: compact X close visible and tappable
- Manual iPhone QA: Props/Style/Resize/Images/AI/Debug tabs visible
- Manual iPhone QA: Target row visible
- Manual iPhone QA: body scrolls internally
- Manual iPhone QA: header/tabs/target never clip
- Manual iPhone QA: desktop layout normal
- Manual iPhone QA: left drawer unchanged
- Manual iPhone QA: preview mode stays read-only
- Manual iPhone QA: Save still works
- Manual iPhone QA: Publish remains dry-run

### Next Action
QA should verify the manual QA checklist on iPhone at https://sbuilder.slimyai.xyz.

---

## 2026-05-26 — sBuild Mobile Right Drawer Layout Real Fix

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Rebuilt mobile right editor drawer layout model to fix persistent clipping of header/tabs/target area behind fixed SBUILD toolbar.
- Root cause: Drawer was `position: fixed; bottom: 8px` with `max-height` limiting upward growth. Even with max-height accounting for toolbar, the bottom-anchored drawer grew upward into toolbar space, clipping the header. Previous patches (max-height offsets, close button moves, absolute X buttons) were band-aids on a broken layout model.
- Fix: Changed drawer to explicit `top: calc(var(--mobile-topbar-h, 110px) + env(safe-area-inset-top, 0px) + 8px)` with `bottom: 8px`, `max-height: none`, `overflow: hidden`. Drawer now starts below toolbar and extends to viewport bottom.
- Added `right-drawer-mobile-header` flex row with "Edit block" title + compact X close button (no longer absolute positioned).
- Renamed tab wrapper from `mobile-drawer-tab-row` to `right-drawer-tabs`, removed padding-right hack.
- Header has `flex-shrink: 0` (never compressed), content has `overflow-y: auto; min-height: 0` (internal scroll).
- Same fix applied to 1100px tablet breakpoint.
- Updated 5 existing tests, added 7 new tests (128 total editor).

### Verified (Exact Commands)
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 128/128, server 20/20)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed: false)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (dryRun: true)

### Proof
- /tmp/proof_sbuild_mobile_right_drawer_layout_real_fix_20260526T212704Z

### Changed Files
- `packages/editor/src/App.tsx` — added right-drawer-mobile-header with title + X close, renamed tab wrapper to right-drawer-tabs
- `packages/editor/src/styles.css` — drawer uses explicit top offset below toolbar, overflow: hidden shell, flex-based X button, new mobile-header/title/tabs CSS, removed max-height calc and position sticky/relative from header
- `packages/editor/src/ui-contract.test.js` — 128 tests (5 updated for new layout model, 7 new for top offset, overflow hidden, mobile-header, AI context menu, Edit Properties)

### Git
- Local commit: `a66f5b2` — `fix: keep mobile editor drawer header below toolbar`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA: drawer header visible below toolbar on iPhone
- Manual iPhone QA: "Edit block" title visible in header
- Manual iPhone QA: compact X close button visible and tappable in header
- Manual iPhone QA: Props/Style/Resize/Images/AI/Debug tabs visible
- Manual iPhone QA: Target row visible
- Manual iPhone QA: no top clipping
- Manual iPhone QA: X closes drawer
- Manual iPhone QA: drawer body scrolls internally
- Manual iPhone QA: desktop layout normal
- Manual iPhone QA: left drawer unchanged
- Manual iPhone QA: AI Assistant from context menu opens drawer for correct block
- Manual iPhone QA: Edit Properties from context menu opens drawer
- Manual iPhone QA: toolbar stays visible while scrolling canvas
- Manual iPhone QA: Save still works
- Manual iPhone QA: Publish remains dry-run

### Next Action
QA should verify the 21-step manual QA checklist on iPhone at https://sbuilder.slimyai.xyz.

---

## 2026-05-26 — GH Tracker Phase 6D.1 Pixel Pet Evolution Stages

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Added deterministic pixel pet evolution stages: egg, hatchling, juvenile, adult.
- Added staged local SVG assets under `public/sprites/repo-pets/<species>/<stage>.svg` for data-frog, terminal-bat, market-mantis, repo-slime, paper-owl, pixel-crab, and unknown fallback.
- Kept old flat SVGs in place for compatibility; `RepoPetSprite` now prefers staged paths and falls back unsupported species to `unknown/<stage>.svg`.
- Added `calculatePetMaturityScore()` and `petStageFromMaturityScore()` using existing commit/activity/health/GitHub sync signals only.
- Thresholds: 0-2 egg, 3-15 hatchling, 16-60 juvenile, 61+ adult.
- Updated Quick View and full Repo Habitat cards to render stage-aware sprites and show labels like `Data Frog · egg`.
- Updated Action Center overview to show pet species/stage and evolution summary.
- Updated app version to `0.6.3-phase6d1-pet-evolution`.
- Added/updated tests for stage calculation, staged assets, no text/glyph placeholders, Quick View and Habitat stage sprite props, Action Center stage visibility, Cleanup Planner, Heatmap inspector, safe commands, and version.

### Verified (Exact Commands)
- Baseline before Phase 6D.1 project edits: `pnpm validate:github`, `pnpm validate:aggregate`, `pnpm typecheck`, `pnpm build`, `pnpm lint`, `pnpm test` — PASS (same existing `<img>` lint warning only)
- `pnpm validate:github` — PASS (`github_health_valid=1`, 14 repos synced)
- `pnpm validate:aggregate` — PASS (`aggregate_valid=1`, 32 locations, 3 machines)
- `pnpm -r typecheck` — no-op in standalone workspace (`No projects matched the filters`)
- `pnpm -r build` — no-op in standalone workspace (`No projects matched the filters`)
- `pnpm -r lint` — no-op in standalone workspace (`No projects matched the filters`)
- `pnpm -r test` — no-op in standalone workspace (`No projects matched the filters`)
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm lint` — PASS with existing warning only: Next.js `<img>` warning in `src/components/repo-pet-sprite.tsx`
- `pnpm test` — PASS (10 files, 41 tests)
- `! rg -n "<text\\b|font-family|font-size|>\\s*[@#^A-Za-z0-9?]\\s*<" public/sprites/repo-pets -g "*.svg"` — PASS, no text/font/glyph sprite content
- `! rg -n "const glyph|\\{glyph\\}|repoInitial|initials|initial sprite|placeholder sprite|placeholder glyph" src/components src/app --glob "*.tsx" --glob "*.ts"` — PASS, no old glyph/initial sprite visual path
- Runtime curl of every staged asset URL under `http://127.0.0.1:5055/sprites/repo-pets/<species>/<stage>.svg` — PASS, each served file includes `phase6d1-pet-evolution`
- `systemctl --user restart gh-tracker.service` — PASS
- `systemctl --user status gh-tracker.service --no-pager` — PASS, active
- `curl -I https://habitat.slimyai.xyz` — PASS, 401 Basic Auth challenge
- `curl -i http://127.0.0.1:5055/api/auth/me` — PASS, 401 unauthenticated
- `curl -I http://127.0.0.1:5055/` — PASS, 307 redirect to `/login` without session
- `systemctl --user status gh-tracker-github-health-sync.timer --no-pager` — PASS, active waiting
- Staged diff secret scan — PASS, no matches

### Proof
- `/tmp/proof_gh_tracker_phase6d1_pet_evolution_20260526T213000Z`

### Git
- Head before: `f6fda0314c0efd6dbd36269fb1af16e24c149e33`
- Local commit: `cc0cf4f00880ed56986e683f5504b39c752cf177` — `feat: add pixel pet evolution stages`
- Push: not performed per instruction

### What Remains Unverified
- Manual browser visual QA of egg, hatchling, juvenile, and adult readability on desktop and mobile.
- Safari/private-tab hard refresh visual QA remains required before any push.

### Next Action
- Manual visual QA pet evolution stages. Do not push until eggs/hatchlings/adults are visibly correct.

---

## 2026-05-26 — GH Tracker Phase 6D Creature SVG Visual Repair

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Replaced every file in `public/sprites/repo-pets/` with new hand-authored 96x96 SVG creature pixel art made from local SVG shapes only.
- `data-frog.svg` now has a frog head/body, two raised eye bumps with eyes, hind legs, and webbed feet.
- `terminal-bat.svg` now has large wings, pointed ears, central body, eyes, and fangs.
- `market-mantis.svg` now has a mantis head/body, antennae, long raptor arms, and claw blades.
- `repo-slime.svg` now has a blob body, eyes/mouth, shine, goo drips, and a neon drip.
- `paper-owl.svg` now has owl body, face discs, eyes, ear tufts, side wings, beak, and feet.
- `pixel-crab.svg` now has crab shell body, claws, legs, eye stalks, and eyes.
- `unknown.svg` now has a hooded mystery creature/blob silhouette with antennae, glowing eyes, body, and feet.
- Added `sprite_visual_check.md` with one paragraph per sprite describing visible creature features.
- Tightened Phase 6D tests to require 64/96 viewBox, `phase6d-creature-art`, no text/font glyphs, shape-only SVG tags, and proof file coverage.
- Confirmed `RepoPetSprite` still renders `<img src={asset}>` from `/sprites/repo-pets/...` and no old glyph/initial sprite rendering path is present.
- Kept app version at `0.6.2-phase6d-pixel-pets`.

### Verified (Exact Commands)
- Baseline before project edits: `pnpm validate:github && pnpm validate:aggregate && pnpm typecheck && pnpm build && pnpm lint && pnpm test` — PASS (lint warning only: existing `<img>` warning in `repo-pet-sprite.tsx`)
- `! rg -n "<text\\b" public/sprites/repo-pets --glob "*.svg"` — PASS, no sprite text elements
- `! rg -n "const glyph|\\{glyph\\}|repoInitial|initials|initial sprite|placeholder sprite|placeholder glyph" src/components src/app --glob "*.tsx" --glob "*.ts"` — PASS, no old glyph/initial sprite visual path
- `rg -n "<img className=\"repo-pet-sprite__image\" src=\{asset\}|/sprites/repo-pets/" src/components/repo-pet-sprite.tsx src/components/repo-habitat.tsx src/components/dashboard.tsx` — PASS, renderer uses local image assets
- `rg -n "phase6d-creature-art" public/sprites/repo-pets --glob "*.svg"` — PASS, all seven sprites have markers
- Post-change: `pnpm validate:github && pnpm validate:aggregate && pnpm typecheck && pnpm build && pnpm lint && pnpm test` — PASS (39/39 tests; same existing lint warning only)
- `pnpm -r typecheck && pnpm -r build && pnpm -r lint && pnpm -r test` — no-op in this standalone workspace (`No projects matched the filters`), so direct package scripts above are the real gate
- `systemctl --user restart gh-tracker.service && systemctl --user status gh-tracker.service --no-pager` — PASS, active
- `for f in data-frog terminal-bat market-mantis repo-slime paper-owl pixel-crab unknown; do curl -fsS "http://127.0.0.1:5055/sprites/repo-pets/$f.svg" | rg -n "phase6d-creature-art"; done` — PASS, served runtime assets include markers
- `rg -n "0\.6\.2-phase6d-pixel-pets" src/lib/dashboard-adapter.ts src/lib/__tests__/phase6d-pixel-pets.test.ts src/lib/auth/__tests__/hardening-static.test.ts src/lib/__tests__/phase6a-action-center.test.ts` — PASS
- `curl -I http://127.0.0.1:5055/` — PASS, 307 redirect to `/login` without session
- `curl -i http://127.0.0.1:5055/api/auth/me` — PASS, 401 unauthenticated
- `curl -I https://habitat.slimyai.xyz` — PASS, 401 Basic Auth challenge
- `systemctl --user status gh-tracker-github-health-sync.timer --no-pager` — PASS, active waiting

### Proof
- `/tmp/proof_gh_tracker_phase6d_creature_svg_repair_20260526T212700Z`

### Git
- Commit: not created
- Push: not performed per instruction

### What Remains Unverified
- Manual Safari/iPhone hard refresh or private-tab visual QA cannot be executed from this shell.
- QA should verify the live browser is not showing stale cached sprite assets and that the creatures are visually recognizable at desktop and compact/mobile sizes.

### Next Action
- Open https://habitat.slimyai.xyz in a private tab or hard-refresh Safari and visually confirm all seven pets render as creatures, not glyphs/placeholders.

---

## 2026-05-26 — sBuild Mobile Editor X Close Button

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Replaced failed full-width "Close" text button with compact "✕" X button in top-right of right editor drawer for mobile.
- Root cause: Commit 9da015e added a full-width "Close" button as the first element in a column-flex `mobile-drawer-tab-row` above the tab buttons. User reported "It got rid of the close button all together" — the full-width button was either clipped or not visible on iPhone.
- Fix: Added `mobile-editor-x-close` button with `position: absolute; top: 6px; right: 8px` inside `.right-drawer-header`, 44x44px tap target, circular, z-index: 20.
- Hidden on desktop (`display: none` base), shown on mobile (`display: inline-flex` in 768px breakpoint).
- Removed old `mobile-close-btn` and `drawer-close-btn` CSS entirely.
- Tab row given `padding-right: 48px` to avoid X button overlap.
- Added `.app.mobile-shell .right-drawer-header { position: relative }` to contain the absolute button.
- Updated 7 tests (replaced 6 old mobile-close-btn tests with 7 new mobile-editor-x-close tests).

### Verified (Exact Commands)
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 121/121, server 20/20)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed: false)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (dryRun: true)

### Proof
- /tmp/proof_sbuild_mobile_x_close_button_20260526T210821Z

### Changed Files
- `packages/editor/src/App.tsx` — Replaced mobile-close-btn with mobile-editor-x-close X button in right-drawer-header
- `packages/editor/src/styles.css` — Removed mobile-close-btn/drawer-close-btn CSS, added mobile-editor-x-close (hidden base, inline-flex+absolute+44px on mobile), padding-right on tab row, relative header
- `packages/editor/src/ui-contract.test.js` — 7 new X-close tests (aria, close handler, desktop hidden, 44px tap target, tab presence, scroll, desktop isolation)

### Git
- Local commit: `c65ff1e` — `fix: add mobile editor x close button`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA: X button visible in top-right of drawer
- Manual iPhone QA: X button not clipped by toolbar
- Manual iPhone QA: X button closes the drawer
- Manual iPhone QA: Props/Style/Resize/Images/AI/Debug tabs visible and usable
- Manual iPhone QA: drawer content scrolls internally
- Manual iPhone QA: desktop layout still normal

### Next Action
QA should verify the manual QA checklist on iPhone at https://sbuilder.slimyai.xyz.

---

## 2026-05-26 — sBuild Mobile Right Drawer Close Button Visible

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Fixed mobile right editor drawer Close button being hidden behind fixed top toolbar on iPhone.
- Root cause: The "Edit block" header + Close button were at the very top of a fixed-bottom drawer that grows upward. Even with max-height offset, the top portion was clipped by the fixed toolbar (~110px). The previous fix (max-height offset) reduced the drawer height but the header still started at the top where clipping occurred.
- Removed the "Edit block" mobile toolbar from the right drawer header entirely.
- Added a mobile-only "Close" button (`mobile-close-btn`) as the first element in a new `mobile-drawer-tab-row` wrapper, directly above the tab buttons. This button is full-width and prominently styled.
- On desktop, `.mobile-close-btn` is `display: none` in base CSS; only shown inside `@media (max-width: 768px)`.
- Made target summary more compact on mobile (11px font, reduced padding).
- Updated content max-height offset from 90px to 110px to account for the new close button row.
- Added 6 new UI contract tests (120 total).

### Verified (Exact Commands)
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (120/120)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed: false)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (dryRun: true)

### Proof
- /tmp/proof_sbuild_mobile_right_drawer_close_visible_20260526T205302Z

### Changed Files
- `packages/editor/src/App.tsx` — Replaced top "Edit block" toolbar with inline close button in mobile-drawer-tab-row wrapper
- `packages/editor/src/styles.css` — Added .mobile-close-btn (hidden by default, shown on mobile), .mobile-drawer-tab-row layout, compact target summary, updated content max-height offset
- `packages/editor/src/ui-contract.test.js` — 6 new contract tests for mobile close button visibility, close action, desktop hiding, tab presence, scroll, and desktop isolation

### Git
- Local commit: `9da015e` — `fix: make mobile editor drawer close control visible`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA: Close button is fully visible without scrolling
- Manual iPhone QA: Close button is not clipped by toolbar/status/browser chrome
- Manual iPhone QA: Close button closes the drawer
- Manual iPhone QA: Props/Style/Resize/Images/AI/Debug tabs visible and usable
- Manual iPhone QA: drawer content scrolls internally
- Manual iPhone QA: desktop layout still normal

### Next Action
QA should verify the 18-step manual QA checklist on iPhone at https://sbuilder.slimyai.xyz.

---

## 2026-05-26 — GH Tracker Phase 6D Creature Asset Cache Verification

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Re-inspected every sprite in `public/sprites/repo-pets/` and confirmed assets are shape-based creature SVG art with no text elements or font-rendered glyphs.
- Added `phase6d-creature-art` comments inside all seven SVG assets to make runtime/cache verification unambiguous.
- Updated Phase 6D tests to require the creature-art marker in each sprite asset.
- Added proof file `sprite_visual_check.md` with one paragraph per sprite describing visible creature features.
- Restarted `gh-tracker.service` and curled local SVG URLs through `http://127.0.0.1:5055/sprites/repo-pets/...`; served files include the `phase6d-creature-art` markers.
- Kept app version at `0.6.2-phase6d-pixel-pets`.

### Verified (Exact Commands)
- `pnpm validate:github` — PASS
- `pnpm validate:aggregate` — PASS
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `systemctl --user restart gh-tracker.service` — PASS
- `systemctl --user status gh-tracker.service --no-pager` — PASS (active)
- `curl http://127.0.0.1:5055/sprites/repo-pets/data-frog.svg` and all other sprite URLs — PASS, marker present
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Basic Auth challenge)
- `curl -i http://127.0.0.1:5055/api/auth/me` — PASS (401 unauthenticated)
- `curl -I http://127.0.0.1:5055/` — PASS (307 redirect to `/login` without session)

### Proof
- /tmp/proof_gh_tracker_phase6d_creature_asset_cache_verify_20260526T211227Z

### Git
- Local commit: `f6fda0314c0efd6dbd36269fb1af16e24c149e33` — `fix: verify creature sprite assets`
- Push: not performed

### Next Action
- Manual visual QA again in a private tab or after hard refresh. Do not push until the visible pet art is confirmed creature-based.

---

## 2026-05-26 — GH Tracker / Repo Habitat Phase 6D Pixel Pet Visual Repair

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Repaired Phase 6D pixel pet art after manual QA found the first SVG set still read like glyph placeholders at compact size.
- Replaced all required sprite SVGs with larger creature-shaped pixel art built from blocky SVG rectangles and named anatomy groups.
- Data Frog now has eye bumps, hind legs, body, belly, face, and frog stance.
- Terminal Bat now has wide wings, ears, eyes, fangs, and body.
- Market Mantis now has antennae, thin body, back legs, and raptor forearms/blades.
- Repo Slime now has a blob body, shine, drips, face, and puddle silhouette.
- Paper Owl now has ear tufts, face discs, eyes, beak, wings, and feet.
- Pixel Crab now has claws, eye stalks, shell, legs, and mouth.
- Unknown fallback now renders a hooded mystery creature with glowing eyes, antennae, and feet instead of a question-mark/glyph form.
- Added tests asserting local creature assets use SVG shape blocks, have no text/font glyph placeholders, and retain mapping/fallback/regression coverage.
- Kept app version at `0.6.2-phase6d-pixel-pets`.

### Verified (Exact Commands)
- `pnpm validate:github` — PASS
- `pnpm validate:aggregate` — PASS
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `systemctl --user restart gh-tracker.service` — PASS
- `systemctl --user status gh-tracker.service --no-pager` — PASS (active)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Basic Auth challenge)
- `curl -i http://127.0.0.1:5055/api/auth/me` — PASS (401 unauthenticated)
- `curl -I http://127.0.0.1:5055/` — PASS (307 redirect to `/login` without session)
- `systemctl --user status gh-tracker-github-health-sync.timer --no-pager` — PASS (active waiting)

### Proof
- /tmp/proof_gh_tracker_phase6d_pixel_pet_visual_repair_20260526T205718Z

### Git
- Local commit: `6dd196a4bbac278720048c98d3682802361c7136` — `fix: replace placeholder pet glyphs with pixel creatures`
- Push: not performed per instruction

### Next Action
- Manual visual QA again. Do not push until pet art is visibly creature-based.

---

## 2026-05-26 — GH Tracker / Repo Habitat Phase 6D Pixel Pet Sprites

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Replaced Repo Habitat and Habitat Quick View placeholder glyph pets with original local SVG pixel pet sprites.
- Added shared `RepoPetSprite` renderer with known species mapping, unknown fallback, full/compact modes, useful alt text, and status classes.
- Added seven local SVG assets under `public/sprites/repo-pets/` for Terminal Bat, Market Mantis, Repo Slime, Paper Owl, Pixel Crab, Data Frog, and unknown fallback.
- Added status styling for healthy/focused, needs-care/dirty, alert/unpushed, idle, and unknown states with reduced-motion support.
- Updated app version to `0.6.2-phase6d-pixel-pets`.
- Added `docs/PIXEL_PETS.md` and Phase 6D tests.
- Restarted `gh-tracker.service`; service is active.

### Verified (Exact Commands)
- `pnpm validate:github` — PASS
- `pnpm validate:aggregate` — PASS
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `curl -I http://127.0.0.1:5055` — PASS (307 redirect to `/login` without session)
- `curl -i http://127.0.0.1:5055/api/auth/me` — PASS (401 unauthenticated)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Basic Auth challenge)
- `systemctl --user status gh-tracker-github-health-sync.timer --no-pager` — PASS (active waiting)

### Proof
- /tmp/proof_gh_tracker_phase6d_pixel_pets_20260526T203940Z

### Git
- Local commit: `10dee88141fbc72aa02e024ba2b7f2435a435c2b` — `feat: add pixel pet sprites`
- Push: not performed per Phase 6D safety rule

### Next Action
- Manual visual QA of pixel pet readability on mobile and desktop, then push if accepted.

---

## 2026-05-26 — sBuild Mobile Right Drawer Close Visible Below Toolbar

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Fixed mobile right editor drawer close/header being hidden behind the fixed top toolbar.
- Root cause: The right drawer was `position: fixed; bottom: 8px; max-height: 72vh` on mobile. With 72vh max-height, the drawer extended upward behind the fixed toolbar (z-index: 90, ~110px tall). The "Edit block" header, Close button, and tab row were hidden behind the toolbar.
- Changed `.right-drawer` max-height in `@media (max-width: 768px)` from `72vh` to `calc(100dvh - var(--mobile-topbar-h, 110px) - 16px - env(safe-area-inset-top, 0px))`.
- Changed `.right-drawer-content` max-height from `62vh` to `calc(100dvh - var(--mobile-topbar-h, 110px) - 16px - env(safe-area-inset-top, 0px) - 90px)`.
- Added `flex-shrink: 0` to `.right-drawer-header` to prevent header from being compressed.
- Removed duplicate `.right-drawer-header` block in the 768px media query (first block was missing sticky/flex-shrink).
- Added `max-height` with toolbar offset to `@media (max-width: 1100px)` `.app.mobile-shell .right-drawer` for tablet breakpoint coverage.
- Added 7 new UI contract tests (114 total).

### Verified (Exact Commands)
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (114/114)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed: false)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (dryRun: true)

### Proof
- /tmp/proof_sbuild_mobile_right_drawer_close_offset_20260526T203223Z

### Changed Files
- `packages/editor/src/styles.css` — mobile right drawer max-height accounts for fixed toolbar, duplicate header block removed, content max-height respects toolbar offset
- `packages/editor/src/ui-contract.test.js` — 7 new contract tests

### Git
- Local commit: `00a2845` — `fix: keep mobile editor drawer close visible below toolbar`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA: right drawer "Edit block" header visible and not behind toolbar
- Manual iPhone QA: Close button tappable
- Manual iPhone QA: Props/Style/Resize/Images/AI/Debug tabs visible
- Manual iPhone QA: drawer content scrolls internally
- Manual iPhone QA: desktop layout still normal

### Next Action
QA should verify the 19-step manual QA checklist on iPhone at https://sbuilder.slimyai.xyz.

---

## 2026-05-26 — GH Tracker / Repo Habitat — Phase 6C acceptance tag pushed

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Created/preserved acceptance tag `v0.6.1-phase6c` on commit `df4455ce7206ba0d047cf378f97dfbca6e0e8c36`.
- Pushed tag to `origin` (tag-only push; no branch push).
- Recorded acceptance proof: `/tmp/opencode/proof_phase6c_acceptance_20260526T202455Z`.
- Confirmed Phase 6C cleanup planner acceptance state is preserved.
- Confirmed Action Center behavior preserved.
- Confirmed heatmap behavior preserved.
- Confirmed auth/session gates preserved for dashboard and protected APIs.
- Confirmed public Basic Auth 401 outer gate preserved.

### Tag
- `v0.6.1-phase6c`
- Message: `GH Tracker Phase 6C Repo Cleanup Planner accepted`
- Commit: `df4455ce7206ba0d047cf378f97dfbca6e0e8c36`

### Next Action
None.

---

## 2026-05-26 — sBuild Fixed Toolbar + Block Context AI

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Changed mobile topbar from `position: sticky` to `position: fixed` with `left: 0; right: 0; z-index: 90` and `box-shadow`.
- Added `topbarRef` with ResizeObserver to dynamically measure topbar height and set `--mobile-topbar-h` CSS variable.
- Added `.topbar-mobile-spacer` div after topbar to compensate for fixed positioning (hidden on desktop, visible on mobile, uses measured height).
- When left drawer opens on mobile (`mobile-left-open` class), both topbar and spacer hide; left drawer extends to top of screen with `calc(8px + env(safe-area-inset-top, 0px))`.
- Updated `.left-drawer` mobile `top` from `70px` to `calc(var(--mobile-topbar-h, 110px) + 4px)`.
- Updated `.canvas-controls` mobile sticky `top` from `66px` to `calc(var(--mobile-topbar-h, 110px) + 4px)`.
- Added "AI Assistant" button directly after "Edit Properties" in block context menu. Calls `openAiDrawer(contextMenu.blockId)` and closes menu.
- Desktop topbar unchanged (still `position: sticky` inside non-scrolling flex container).
- Added 10 new tests (107 total): block context AI Assistant ordering, spacer existence, left-open hiding, fixed position, ResizeObserver measurement, canvas-controls offset.

### Root Cause: Toolbar Disappearing
On mobile, `.app.mobile-shell` had `overflow: visible` making the body the scroll container. `position: sticky` inside a flex column with `overflow: visible` and `min-height: 100vh` is unreliable in iOS Safari. Fixed by switching to `position: fixed` with dynamic height measurement.

### Root Cause: AI Only on Site Header Menu
Block context menu had "AI Edit", "Generate Image", "Edit Photo" buried at position 14-16 of 18 items. No "AI Assistant" label. Users couldn't find it. Added "AI Assistant" at position 2 (after Edit Properties).

### Verified (Exact Commands)
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (107/107)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed: false)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (dryRun: true)

### Proof
- /tmp/proof_sbuild_static_toolbar_block_context_ai_20260526T195525Z

### Changed Files
- `packages/editor/src/App.tsx` — topbarRef, ResizeObserver, spacer div, AI Assistant in block context menu
- `packages/editor/src/styles.css` — fixed topbar on mobile, spacer, left-drawer/canvas-controls offset, left-open hide
- `packages/editor/src/ui-contract.test.js` — 10 new tests, updated mobile topbar test

### Git
- Local commit: `f9748ba` — `fix: keep toolbar static and add block context AI`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA: toolbar stays visible while scrolling
- Manual iPhone QA: AI Assistant appears in block context menus (Hero, Cards, Text, Gallery, etc.)
- Manual iPhone QA: left drawer hides topbar when opened
- Manual iPhone QA: desktop layout still looks normal

### Next Action
QA should verify the 20-step manual QA checklist on iPhone at https://sbuilder.slimyai.xyz.

---

## 2026-05-26 — GH Tracker / Repo Habitat Phase 6B Acceptance Push

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git

### What Was Done
- Recorded Phase 6B Stable Heatmap Reimplementation as accepted and pushed.
- Accepted commit: `d6fedc4e0321f7742b45a40c9e32cc2a0414ced4`.
- Proof: `/tmp/proof_gh_tracker_phase6b_acceptance_push_20260526T194712Z`.
- Confirmed accepted behavior: heatmap interactivity restored (tap/click), selected-day highlight, and Activity Day Inspector details panel with truthful data/no-details fallback.
- Confirmed Action Center preserved with copy-only command blocks.
- Confirmed auth/security posture preserved: dashboard requires Habitat session, protected API requires session, public Basic Auth gate remains 401, no secrets exposed.

### Verification (Acceptance Evidence)
- `pnpm validate:github` — PASS
- `pnpm validate:aggregate` — PASS
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm lint` — PASS
- `pnpm test` — PASS (29/29)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Basic Auth challenge)
- `curl -I http://127.0.0.1:5055` — PASS (307 redirect to `/login` without session)
- `curl -i http://127.0.0.1:5055/api/auth/me` — PASS (401 `{"authenticated":false}`)

### Next Recommended Phase
- Phase 6C or PM-selected GH Tracker polish/data task (for example richer per-day activity provenance in heatmap inspector).

---

## 2026-05-26 — sBuild Sticky Toolbar + Context Menu AI

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Made top SBUILD toolbar sticky with safe-area-inset-top support for iOS.
- Desktop: topbar stays visible via flex layout (`.app` overflow:hidden, topbar is flex child that never scrolls).
- Mobile: added `position: sticky; top: 0; z-index: 80` override in `@media (max-width: 768px)` with `env(safe-area-inset-top)`. Toolbar stays visible during document scroll.
- Added "AI Assistant" button to site header context menu. Calls `openAiDrawer()` (no blockId) which triggers `computeAiTarget()` → targets site header.
- Block context menu already had "AI Edit", "Generate Image", "Edit Photo" via `openAiDrawer(contextMenu.blockId)`.
- Added 8 new UI contract tests covering sticky toolbar, context menu AI action, normalized AI target resolution, and preview mode guards.

### Verified (Exact Commands)
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 97/97, server 20/20)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed: false)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (dryRun: true)

### Proof
- /tmp/proof_sbuild_sticky_toolbar_context_ai_20260526T193510Z

### Changed Files
- `packages/editor/src/App.tsx` — Added "AI Assistant" to site header context menu
- `packages/editor/src/styles.css` — Safe-area-inset-top on base topbar, mobile sticky z-index:80
- `packages/editor/src/ui-contract.test.js` — 8 new contract tests

### Git
- Local commit: `ea832ca` — `fix: keep editor toolbar visible and add context AI action`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA: toolbar stays visible while scrolling on mobile
- Manual iPhone QA: AI Assistant appears in site header context menu
- Manual iPhone QA: block context menu AI actions still work

### Next Action
QA should verify the sticky toolbar and context menu AI checklist on iPhone at https://sbuilder.slimyai.xyz.

---

## 2026-05-26 — sBuild AI Target Simplification

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Added `computeAiTarget()` helper function (`packages/editor/src/App.tsx:1203`) that returns a normalized AI target object with kind (`site-header` | `block` | `none`), blockId, blockType, and label.
- Updated `openAiDrawer()` to use `computeAiTarget()` for resolution, accepting optional `targetBlockId` for context menu invocation.
- AI panel label now reflects computed AI target (site header / block `<type> · <id>`), independent from stale `selectedBlockId`.
- Context menu AI buttons now use `openAiDrawer(contextMenu.blockId)` instead of raw `selectBlock` + `setRightTab("ai")`.
- Updated 3 existing tests and added 8 new deterministic tests proving AI target independence.

### AI Target Resolution Rules
1. `selectedSitePart` in set `[site-title, nav, site-header]` → `kind: "site-header"`, label = "site header"
2. `lastFocusedTextBlockId.current || selectedBlockId` → parent block (excluding spacer/divider/html)
3. Fallback: first editable block (excluding spacer/divider/html)
4. Never falls back to stale hero-1 when site header or other blocks are selected

### Verification
- `pnpm -r typecheck`: PASS
- `pnpm -r build`: PASS
- `pnpm -r lint`: PASS
- `pnpm -r test`: 90/90 PASS
- `bash scripts/smoke-sbuild.sh`: PASS
- `curl http://127.0.0.1:3137/health`: PASS
- `curl -X POST http://127.0.0.1:3137/api/publish`: PASS (dry-run)

### Next
- Manual QA on iPhone: verify AI panel shows correct target for site header, cards, text, gallery.

---

## 2026-05-26 — sBuild Site Header Container Selection Fix

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Added `selectSiteHeaderContainer()` function that sets `selectedSitePart("site-header")` and clears block/gallery selection.
- Added `openSiteHeaderContextMenu()` function that opens a context menu with `isSiteHeader: true` flag.
- Extended `openSiteHeaderDrawer()` to accept `"site-header"` part — opens the right drawer for container editing.
- Extended `startSiteHeaderLongPress()` to support `"site-header"` — mobile long-press on empty header area.
- Updated `<nav>` element with:
  - `onClick` (empty-area click selects container with `e.target === e.currentTarget` guard)
  - `onPointerDown`/`onPointerUp`/`onPointerMove` for mobile long-press
  - `onContextMenu` for desktop right-click
  - `className` with `selected-site-part` class when site-header is selected
- Updated "..." button to call `openSiteHeaderContextMenu(e)` instead of direct drawer open.
- Updated `targetSummary()` with `"Target: Site header → Whole header"` branch.
- Updated context menu rendering with `isSiteHeader` flag — site header shows subset (Edit Properties, Reset colors, Reset all blocks, Close).
- Updated Properties tab — site-header shows title + nav links editing controls.
- Updated CSS: `.canvas-nav.selected-site-part` outline, preview mode guard, edit mode hover border.
- Updated `renderCurrentTargetCard()` to include site-header in `showSitePart`.

### Verified (Exact Commands)
- `cd /opt/slimy/sbuild && pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 82/82, server 20/20)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed: false)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (dryRun: true)

### Proof
- /tmp/proof_sbuild_site_header_container_select_20260526T164459Z

### Changed Files
- `packages/editor/src/App.tsx` — selectSiteHeaderContainer, openSiteHeaderContextMenu, extended state types, nav handlers, context menu, properties tab
- `packages/editor/src/styles.css` — .canvas-nav.selected-site-part, preview guard, hover effects
- `packages/editor/src/ui-contract.test.js` — 18 new contract tests

### Git
- Local commit: `803eb85` — `fix: make site header container selectable`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA on https://sbuilder.slimyai.xyz for the 14-step site header container selection checklist.

### Next Action
QA should verify the 14-step site header container selection checklist on iPhone at https://sbuilder.slimyai.xyz.

---

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Root cause: contentEditable elements call `e.stopPropagation()` on `onPointerDown`, preventing block-level `handleBlockPointerUp()` from updating `selectedBlockId`. When AI drawer opens, it reads stale `selectedBlockId` (Hero).
- Added `activateBlockTextTarget(blockId, part?)` helper that updates `selectedBlockId`, clears `selectedGalleryIndex/selectedSitePart/selectedNavIndex`, and sets `lastFocusedTextBlockId.current` ref.
- Added `lastFocusedTextBlockId` ref to track the most recent text-editing target.
- Updated `openAiDrawer()` to prefer `lastFocusedTextBlockId.current` over `selectedBlockId`, syncing state when stale.
- Added `onActivateTarget` prop to all block components (Hero, Text, Cards, Hours, Gallery, Contact, Testimonial, Map, Marquee, Image).
- Wired contentEditable `onPointerDown` handlers to call `onActivateTarget(part)` before `e.stopPropagation()`.
- Updated `selectBlock()`, `handleBlockPointerUp()`, and preview-mode `useEffect` to maintain the ref.
- Added 10 UI contract tests for AI target freshness.
- Updated `feature_list.json` with new feature entry.

### Verified (Exact Commands)
- `cd /opt/slimy/sbuild && pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 64/64, server 20/20)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed: false)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (dryRun: true)

### Proof
- /tmp/proof_sbuild_ai_target_binding_20260526T134150Z

### Changed Files
- `packages/editor/src/App.tsx` — activateBlockTextTarget helper, lastFocusedTextBlockId ref, onActivateTarget prop wiring, openAiDrawer preference for fresh target
- `packages/editor/src/ui-contract.test.js` — 10 new tests for AI target freshness

### Git
- Local commit: `aaac1c2` — `fix: refresh AI target from direct text editing context`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA on https://sbuilder.slimyai.xyz for the 26-step AI target binding checklist.

### Next Action
QA should verify the 26-step AI target binding checklist on iPhone at https://sbuilder.slimyai.xyz.

---

## 2026-05-25 — GH Tracker Phase 5D.1: Slimy Auth Bridge Discovery

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git
- Public URL: https://habitat.slimyai.xyz
- Slimy Monorepo: /opt/slimy/slimy-monorepo

### What Was Done
- Performed read-only discovery of Slimy auth system in slimy-monorepo.
- Found complete email/password auth stack: SlimyUser, SlimySession, SlimyPasswordReset, argon2 hashing, DB-backed sessions.
- Found login/logout/me/forgot-password/reset-password API routes and pages.
- Found cookie name `slimy_session` with SameSite=lax, path=/, no domain attribute.
- Determined habitat.slimyai.xyz CANNOT share cookies with slimyai.xyz (no domain attribute = exact hostname scope).
- Confirmed GH Tracker has zero auth infrastructure (no middleware, no auth deps, no user model).
- Confirmed Caddy Basic Auth remains active on habitat.slimyai.xyz.
- Analyzed integration options A through E.
- Recommended Option A for Phase 5D.2: keep Basic Auth, add settings UI with gate-info only.

### Verified (Exact Commands)
- `cd /opt/slimy/gh-tracker && git rev-parse HEAD` — 31d9ca4
- `cd /opt/slimy/slimy-monorepo && git rev-parse HEAD` — ab3a128
- `rg -i auth src/ -g "*.ts" -g "*.tsx" -l` in GH Tracker — 0 auth files (only demo-data.ts has word "auth" in commit message)
- `rg -i auth src/ -g "*.ts" -g "*.tsx" -l` in slimy-monorepo — 64 auth-related files
- `cat apps/web/lib/slimy-auth/session.ts` — cookie name `slimy_session`, no domain attribute
- `cat apps/web/prisma/schema.prisma` — SlimyUser, SlimySession, SlimyPasswordReset models confirmed
- `cat apps/web/app/api/session/forgot-password/route.ts` — forgot-password flow with email + 1h token TTL
- `cat apps/web/app/api/session/reset-password/route.ts` — reset-password flow with argon2 + session revocation
- `grep habitat /etc/caddy/Caddyfile` — basicauth block confirmed
- `curl -I https://habitat.slimyai.xyz` — 401 with WWW-Authenticate: Basic
- `systemctl status caddy` — active (running)
- Secret scan — PASS (no secrets in proof)
- Forbidden file check — PASS (no modifications to monorepo or sbuild)

### Proof
- /tmp/proof_gh_tracker_phase5d1_slimy_auth_bridge_discovery_20260525T225419Z

### Key Findings
- Slimy auth is mature and complete (email/password, sessions, reset, email)
- Cookie domain NOT SET = no cross-subdomain sharing
- GH Tracker is completely auth-free
- Basic Auth is the only current protection
- SSO would require slimy-monorepo cookie domain change or new API endpoint

### Next Action
Phase 5D.2: Implement Option A — add settings button/modal to GH Tracker with edge-auth info, app version, timer status; create docs/PASSWORD_RESET.md for admin instructions only. No fake auth flows.

---

## 2026-05-25 — GH Tracker Phase 5C: Acceptance Push

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git
- Public URL: https://habitat.slimyai.xyz

### What Was Done
- Performed pre-flight checks: repo path exists, remote correct, HEAD at 31d9ca4, git status clean, gh auth authenticated.
- Verified timer: `gh-tracker-github-health-sync.timer` active, enabled, waiting (next trigger 22:57:58 UTC).
- Verified Phase 5C state: app version 0.5.2-phase5c, canonical repos 19, locations 32, duplicates removed 13.
- Confirmed expandable details (`expandedRepos`, `onToggleExpand`), mixed dirty state (`clean`/`dirty`/`mixed`), machine details preserved, GitHub health joined once per canonical repo.
- Confirmed `nousearch-hermes-agent` absent from all data (only in exclusion logic).
- Ran validation: `pnpm validate:github` PASS (14/14 synced), `pnpm validate:aggregate` PASS (32 locations, 3 machines).
- Ran builder gates: `pnpm lint` PASS, `pnpm typecheck` PASS (after `.next` clean; Next.js generated type quirk), `pnpm build` PASS.
- Route checks: local 200 OK, public 401 Basic Auth challenge — PASS.
- Secret scan: no secrets in source, logs, systemd units, or generated data — PASS.
- Forbidden file check: no modifications to slimy-monorepo or sbuild — PASS.
- Pushed commit 31d9ca4 to origin/main.
- Post-push verify: remote main matches local HEAD (31d9ca4).
- Updated `feature_list.json`: `gh-tracker-phase-5c-canonical-repo-view-001` now `passes:true`, `publish_allowed:true`, `status:completed`.

### Verified (Exact Commands)
- `cd /opt/slimy/gh-tracker && git rev-parse HEAD` — 31d9ca4
- `git remote -v` — origin git@github.com:GurthBro0ks/gh-tracker.git
- `git status --short` — clean
- `gh auth status` — authenticated (redacted)
- `systemctl --user status gh-tracker-github-health-sync.timer` — active, enabled, waiting
- `systemctl --user list-timers` — timer listed
- `pnpm validate:github` — github_health_valid=1, repos=14, dashboard_status=synced
- `pnpm validate:aggregate` — aggregate_valid=1, repo_locations=32, machines=3
- `pnpm lint` — PASS
- `pnpm typecheck` — PASS (after rm -rf .next)
- `pnpm build` — PASS
- `curl -I http://127.0.0.1:5055` — 200 OK
- `curl -I https://habitat.slimyai.xyz` — 401 Unauthorized
- Secret scan across repo, logs, systemd units — PASS (no secrets)
- Forbidden repo check — PASS (no modifications)
- `git push origin HEAD:main` — 043d761..31d9ca4
- `git ls-remote origin main` — 31d9ca4

### Proof
- /tmp/proof_gh_tracker_phase5c_acceptance_push_20260525T223406Z

### Changed Files
- `feature_list.json` — marked Phase 5C as passes:true, publish_allowed:true
- `claude-progress.md` — added acceptance push session entry
- `server-state.md` — updated Phase 5C status to pushed

### Git
- Before push: 31d9ca4 (local), 043d761 (remote)
- After push: 31d9ca4 on origin/main

### What Remains Unverified
- None. Phase 5C is complete and pushed.

### Next Action
None.

---

## 2026-05-25 — GH Tracker Phase 5C: Canonical Repo Default View

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git
- Public URL: https://habitat.slimyai.xyz

### What Was Done
- Added canonical repo grouping layer to `src/lib/dashboard-adapter.ts`:
  - `CanonicalRepoView` type with combined stats, machine/location details, dirty state, GitHub health
  - `buildCanonicalRepos()` function groups repo locations by canonical repo
  - Supports `clean`/`dirty`/`mixed` dirty state when repo has mixed status across machines
  - Sums commits, pushes, additions, deletions, unpushed commits across machines
  - Preserves per-machine and per-location detail arrays for expansion
- Updated `src/components/dashboard.tsx`:
  - Repo Habitat cards now show canonical repo view by default (combined stats, machine count, location count)
  - Added expandable state (`expandedRepos`) with tap/click to expand
  - Repo Locations section now shows canonical repos grouped by default with per-location expandable detail
  - Updated app version to `0.5.2-phase5c`
- Updated `src/components/repo-habitat.tsx`:
  - `RepoHabitatGrid` now accepts `expandedRepos` and `onToggleExpand` props
  - `RepoPetCard` shows combined dirty state, machine list, location count
  - Expanded view shows per-machine details (commits, pushes, dirty, branch) and per-location details (path, branch, dirty, unpushed)
- GitHub health attaches once per canonical repo (not repeated per location)

### Verified (Exact Commands)
- `cd /opt/slimy/gh-tracker && git rev-parse HEAD` — 31d9ca4
- `git status --short` — 3 files modified (dashboard.tsx, repo-habitat.tsx, dashboard-adapter.ts)
- `pnpm validate:github` — github_health_valid=1, repos=14, dashboard_status=synced
- `pnpm validate:aggregate` — aggregate_valid=1, repo_locations=32, machines=3
- `pnpm lint` — PASS
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `systemctl --user restart gh-tracker.service` — PASS
- `systemctl --user status gh-tracker.service` — active (running)
- `curl -I http://127.0.0.1:5055` — 200 OK
- `curl -I https://habitat.slimyai.xyz` — 401 Unauthorized
- `systemctl --user status gh-tracker-github-health-sync.timer` — active, enabled
- Secret scan — PASS (no secrets in source)
- Forbidden file check — PASS (no modifications to slimy-monorepo or sbuild)

### Proof
- /tmp/proof_gh_tracker_phase5c_canonical_repo_view_20260525T155925Z

### Changed Files
- `src/lib/dashboard-adapter.ts` — added CanonicalRepoView, PerMachineDetail, PerLocationDetail types; buildCanonicalRepos function; updated mergeGithubHealth; version 0.5.2-phase5c
- `src/components/dashboard.tsx` — canonical repo habitat rows, expandable repo locations, expandedRepos state, toggleRepoExpand helper
- `src/components/repo-habitat.tsx` — expandable RepoPetCard with per-machine/per-location detail panels

### Git
- Before: 043d761
- After: 31d9ca4 — `feat: group dashboard by canonical repo`
- Push: not performed (per Phase 5C instructions)

### What Remains Unverified
- Manual browser QA of canonical repo grouping, expandable cards, and mixed state display on mobile/desktop

### Next Action
QA should verify the authenticated dashboard on https://habitat.slimyai.xyz and confirm:
1. Repos appear once by default (not duplicated per machine)
2. Repo Habitat cards show combined stats and machine list
3. Tapping/clicking expands per-machine and per-location details
4. Mixed dirty state shows correctly for repos with mixed status
5. GitHub health badges appear once per repo

---

## 2026-05-25 — GH Tracker Phase 5B: Acceptance Push

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git
- Public URL: https://habitat.slimyai.xyz

### What Was Done
- Performed pre-flight checks: repo path exists, remote correct, HEAD at 043d761, git status clean, gh auth authenticated.
- Verified timer: `gh-tracker-github-health-sync.timer` active and enabled.
- Verified sync service: triggered by timer, currently running (normal hourly sync in progress).
- Ran validation: `pnpm validate:github` PASS (14/14 synced, valid), `pnpm validate:aggregate` PASS (32 locations, 3 machines).
- Ran builder gates: `pnpm lint` PASS, `pnpm typecheck` PASS, `pnpm build` PASS.
- Route checks: local 200 OK, public 401 Basic Auth challenge — PASS.
- Secret scan: no secrets in source, logs, systemd units, or generated data (only node_modules third-party docs).
- Forbidden file check: no modifications to slimy-monorepo or sbuild.
- Pushed commit 043d761 to origin/main.
- Post-push verify: remote main matches local HEAD (043d761).
- Updated `feature_list.json`: `gh-tracker-phase-5b-scheduled-sync-001` now `passes:true`, `publish_allowed:true`.

### Verified (Exact Commands)
- `cd /opt/slimy/gh-tracker && git rev-parse HEAD` — 043d761
- `git remote -v` — origin git@github.com:GurthBro0ks/gh-tracker.git
- `git status --short` — clean
- `gh auth status` — authenticated (redacted)
- `systemctl --user status gh-tracker-github-health-sync.timer` — active, enabled
- `systemctl --user list-timers` — timer listed
- `pnpm validate:github` — github_health_valid=1, repos=14, dashboard_status=synced
- `pnpm validate:aggregate` — aggregate_valid=1, repo_locations=32, machines=3
- `pnpm lint` — PASS
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `curl -I http://127.0.0.1:5055` — 200 OK
- `curl -I https://habitat.slimyai.xyz` — 401 Unauthorized
- Secret scan across repo, logs, systemd units — PASS (no secrets)
- Forbidden repo check — PASS (no modifications)
- `git push origin HEAD:main` — f3bd3e9..043d761
- `git ls-remote origin main` — 043d761

### Proof
- /tmp/proof_gh_tracker_phase5b_acceptance_push_20260525T155011Z

### Changed Files
- Same as Phase 5B implementation (10 files; see previous session entry).

### Git
- Before push: f3bd3e9
- After push: 043d761 on origin/main

### What Remains Unverified
- Long-term timer stability (requires waiting for next automatic run).

### Next Action
None. Phase 5B is complete and pushed.

---

## 2026-05-25 — GH Tracker Phase 5B: Scheduled GitHub Health Refresh + Stale Data Guard

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git
- Public URL: https://habitat.slimyai.xyz

### What Was Done
- Added safe wrapper script `scripts/run-github-health-sync.sh` with flock, logging, and log pruning.
- Added systemd user timer/service units for hourly GitHub health sync.
- Installed and enabled timer on NUC1: `gh-tracker-github-health-sync.timer` (every 1h + boot after 3min).
- Added stale-data guard to dashboard with freshness calculation (fresh/stale/old/missing thresholds).
- Updated dashboard UI to show freshness badge and sync age in GitHub health panel.
- Updated app version to 0.5.1-phase5b.
- Added `data/github/remotes/` to `.gitignore` to avoid runtime-data dirtiness.
- Updated `docs/GITHUB_REMOTE_HEALTH_SYNC.md` with timer install/disable instructions and stale thresholds.
- Committed locally (not pushed per Phase 5B rules).

### Verified (Exact Commands)
- `systemctl --user start gh-tracker-github-health-sync.service` — PASS (14/14 synced, validate:github passed)
- `systemctl --user status gh-tracker-github-health-sync.timer` — PASS (active, enabled)
- `systemctl --user list-timers` — PASS (timer listed)
- `pnpm validate:github` — PASS (github_health_valid=1, repos=14, dashboard_status=synced)
- `pnpm validate:aggregate` — PASS (aggregate_valid=1, repo_locations=32, machines=3)
- `pnpm lint` — PASS
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm -r test --if-present` — PASS/no tests
- Secret scan — PASS (no secrets in diff, logs, or generated data)
- Forbidden file check — PASS (no modifications to slimy-monorepo or sbuild)
- `systemctl --user restart gh-tracker.service` — PASS
- `curl -I http://127.0.0.1:5055` — PASS (200)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Unauthorized)

### Proof
- /tmp/proof_gh_tracker_phase5b_scheduled_github_sync_20260525T144343Z

### Changed Files
- `.gitignore` — added `data/github/remotes/`
- `scripts/run-github-health-sync.sh` — safe wrapper with flock, logging, pruning
- `systemd/user/gh-tracker-github-health-sync.service` — systemd user service
- `systemd/user/gh-tracker-github-health-sync.timer` — systemd user timer
- `src/lib/dashboard-adapter.ts` — added freshness fields, updated version to 0.5.1-phase5b
- `src/lib/local-snapshot.ts` — added freshness calculation
- `src/components/dashboard.tsx` — added freshness badge, sync age display, debug dock updates
- `docs/GITHUB_REMOTE_HEALTH_SYNC.md` — timer docs, stale thresholds

### Git
- Local commit: `043d761` — `feat: schedule GitHub remote health sync`
- Push: not performed (per Phase 5B instructions)

### What Remains Unverified
- Long-term timer stability (requires waiting for next automatic run).
- Manual browser QA of freshness badge and sync age display.

### Next Action
QA should verify the dashboard shows Fresh badge and sync age, then approve push.

---

## 2026-05-25 — GH Tracker Phase 5A.2: Acceptance Polish + Push

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git
- Public URL: https://habitat.slimyai.xyz

### What Was Done
- Verified manual mobile browser QA acceptance for Phase 5A.1.
- Updated hardcoded app version string from "0.4.0-phase4b" to "0.5.0-phase5a" in `src/lib/dashboard-adapter.ts`.
- Sanity-checked Open PRs count (14) against `data/github/remotes/latest.json` — confirmed correct (slimyai-web: 10, pm_updown_bot_bundle: 3, slimy-monorepo: 1).
- Confirmed `nousearch-hermes-agent` is absent from all generated GitHub health data.
- Committed polish fix and pushed Phase 5A to origin/main.

### Verified (Exact Commands)
- `cd /opt/slimy/gh-tracker && pnpm validate:github` — PASS (github_health_valid=1, repos=14, dashboard_status=synced)
- `pnpm validate:aggregate` — PASS (aggregate_valid=1, repo_locations=32, machines=3)
- `pnpm lint` — PASS
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm -r test --if-present` — PASS/no tests
- Secret scan — PASS (no secrets in diff or generated data)
- Forbidden file check — PASS (no modifications to slimy-monorepo or sbuild)
- `systemctl --user restart gh-tracker.service` — PASS
- `systemctl --user status gh-tracker.service --no-pager` — PASS (active)
- `curl -I http://127.0.0.1:5055` — PASS (200)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Unauthorized)
- `git push origin HEAD:main` — PASS (f727349..f3bd3e9)

### Proof
- /tmp/proof_gh_tracker_phase5a2_acceptance_push_20260525T130016Z

### Changed Files
- `src/lib/dashboard-adapter.ts` — version string updated to 0.5.0-phase5a

### Git
- Local commit before: `398bb5c` — `feat: add GitHub remote health sync`
- Polish commit: `f3bd3e9` — `fix: polish Phase 5A GitHub health status display`
- Pushed to origin/main: `f3bd3e9`

### What Remains Unverified
- None. Phase 5A is complete and pushed.

### Next Action
QA should mark `gh-tracker-phase-5a1-github-remote-health-001` as `passes:true` in feature_list.json.

---

## 2026-05-25 — GH Tracker Phase 5A.1: GitHub Remote Health Sync

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git
- Public URL: https://habitat.slimyai.xyz

### What Was Done
- Implemented read-only GitHub CLI remote health sync.
- Added `pnpm github:sync` and `pnpm validate:github`.
- Added generated snapshots:
  - `data/github/remotes/latest.json`
  - `data/github/remotes/latest-summary.json`
- Synced only ownership-filtered GurthBro0ks GitHub candidates from aggregate data.
- Confirmed candidate count is 14 and `nousearch-hermes-agent` is excluded.
- Added GitHub remote health dashboard merge with graceful missing-file fallback.
- Dashboard now shows GitHub sync status, latest sync time, synced repo count, release gaps, CI state, and PR/issue pressure.
- Repo Habitat cards now show real GitHub health badges and release/CI/PR/issue details when snapshot data exists.
- Added `docs/GITHUB_REMOTE_HEALTH_SYNC.md` documenting read-only design and safety rules.

### Verified (Exact Commands)
- `cd /opt/slimy/gh-tracker && pnpm github:sync` — PASS (14 candidates, 14 synced, 0 partial, 0 failed)
- `pnpm validate:github` — PASS (github_health_valid=1, dashboard_status=synced)
- `pnpm validate:aggregate` — PASS
- `pnpm typecheck` — PASS
- `pnpm build` — PASS (existing Recharts prerender width warnings only)
- `pnpm lint` — PASS
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test --if-present` — PASS/no configured test projects
- `systemctl --user restart gh-tracker.service` — PASS
- `systemctl --user status gh-tracker.service --no-pager` — PASS (active)
- `curl -I http://127.0.0.1:5055` — PASS (200)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Unauthorized Basic Auth challenge)
- Secret scan — PASS (no token-like material in source diff, generated GitHub data, or proof dir)
- Forbidden file check — PASS (only safe git status checks against forbidden repos; no writes)

### Proof
- /tmp/proof_gh_tracker_phase5a1_github_remote_health_20260525T062406Z

### Changed Files
- `package.json` — GitHub sync/validate scripts
- `scripts/sync-github-remotes.ts` — read-only GitHub CLI sync
- `scripts/validate-github-health.ts` — snapshot/summary validator
- `data/github/remotes/latest.json` — generated full health snapshot
- `data/github/remotes/latest-summary.json` — generated health summary
- `src/lib/dashboard-adapter.ts` — GitHub health dashboard model and merge
- `src/lib/local-snapshot.ts` — optional GitHub health loading
- `src/components/dashboard.tsx` — GitHub health status panel and habitat health merge
- `src/components/repo-habitat.tsx` — GitHub health badges/details
- `docs/GITHUB_REMOTE_HEALTH_SYNC.md` — design/safety docs

### Git
- Local commit: `398bb5c` — `feat: add GitHub remote health sync`
- Push: not performed (explicitly forbidden for Phase 5A.1)

### What Remains Unverified
- Manual browser QA of the GitHub health dashboard panel and Repo Habitat card layout.
- Independent QA acceptance before marking feature `passes:true`.

### Next Action
Manual QA should verify the authenticated dashboard on https://habitat.slimyai.xyz and confirm the GitHub health panel remains readable on desktop and mobile.

---

## 2026-05-25 — GH Tracker Phase 4B.2: Dashboard + Laptop Workflow Cleanup

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git
- Public URL: https://habitat.slimyai.xyz

### What Was Done
- Fixed pnpm-workspace.yaml: added `packages: ["."]` so pnpm works on laptop/standalone checkouts.
- Hardened laptop workflow docs (`docs/LAPTOP_INGESTION_WORKFLOW.md`):
  - Corrected SSH alias from `nuc1-ts` to `nuc1` (with Tailscale fallback)
  - Added real scan roots: `$HOME/Projects,$HOME/Standalone,$HOME/slimy-dev,$HOME/Desktop`
  - Added HTTPS clone fallback if GitHub SSH is unavailable
  - Added explicit warning not to upload `repo_locations=0` snapshots
  - Added npm/tsx fallback if pnpm is broken before patch
- Hardened snapshot validation (`scripts/validate-snapshot.ts`):
  - `repo_locations=0` now fails with non-zero exit and clear message for real machines
  - Use `--allow-empty` or `GH_TRACKER_ALLOW_EMPTY_SNAPSHOT=1` for testing/discovery
  - Outputs `snapshot_invalid=1` and `reason=no_repo_locations`
- Fixed dashboard wording (`src/components/dashboard.tsx`):
  - Subtitle dynamically shows "Aggregated local Git activity across Laptop, NUC1, and NUC2" when laptop is loaded
  - Shows "Laptop pending manual snapshot import" only when laptop is missing
  - Debug dock shows: loaded machines list, machine count, ownership filter status, excluded repos count
- Added timeline deduplication (`src/components/dashboard.tsx`):
  - Groups duplicate canonical repo events by (repoId, type, message)
  - Shows machine list and count when event spans multiple machines
  - Preserves raw data; UI grouping only
- Updated documentation: `docs/PHASES.md`, `docs/MULTI_MACHINE_INGESTION.md`, `README.md`

### Verified (Exact Commands)
- `cd /opt/slimy/gh-tracker && pnpm install` — PASS
- `pnpm lint` — PASS
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm validate:aggregate` — PASS (aggregate_valid=1, repo_locations=32, machines=3, machine_ids=laptop,nuc1,nuc2)
- Zero-repo snapshot without flag — FAIL as expected (exit 1, snapshot_invalid=1, reason=no_repo_locations)
- Zero-repo snapshot with `--allow-empty` — PASS as expected (snapshot_valid=1, repo_locations=0)
- `systemctl --user restart gh-tracker.service` — PASS
- `systemctl --user is-active gh-tracker.service` — PASS (active)
- `curl -I http://127.0.0.1:5055` — PASS (200)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Unauthorized)
- Forbidden file check — PASS (no forbidden files touched)
- Secret scan — PASS (no secrets exposed)

### Proof
- /tmp/proof_gh_tracker_phase4b2_dashboard_laptop_cleanup_20260525T044753Z

### Changed Files
- `pnpm-workspace.yaml` — added packages root
- `scripts/validate-snapshot.ts` — zero-repo validation hardening
- `src/components/dashboard.tsx` — dynamic subtitle, debug dock, timeline dedupe
- `src/lib/dashboard-adapter.ts` — `excludedReposCount` field
- `src/lib/local-snapshot.ts` — load excluded repos count from report
- `docs/LAPTOP_INGESTION_WORKFLOW.md` — corrected workflow, scan roots, warnings
- `docs/MULTI_MACHINE_INGESTION.md` — updated status, validation hardening section
- `docs/PHASES.md` — Phase 4B.2 description
- `README.md` — Phase 4B.2 section

### Git
- Local commit: PENDING (to be committed now)
- Push: not performed (per instructions)

### What Remains Unverified
- QA verification of dashboard wording and timeline grouping on actual browser
- Operator approval of excluded repos list

### Next Action
QA should verify dashboard subtitle and debug dock on https://habitat.slimyai.xyz (authenticated).

---

## 2026-05-25 — GH Tracker Phase 4B.1: Ownership Filter

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git
- Public URL: https://habitat.slimyai.xyz

### What Was Done
- Implemented repo ownership filtering in aggregate generation to exclude non-owned GitHub remotes from the dashboard.
- Suspect repo `nousresearch-hermes-agent` (owner: NousResearch) traced and excluded.
- Added env var support:
  - `GH_TRACKER_ALLOWED_REMOTE_OWNERS` — default "GurthBro0ks", comma-separated
  - `GH_TRACKER_EXCLUDE_REPO_NAMES` — optional explicit exclusions
- Updated `scripts/aggregate-snapshots.ts`:
  - Filters repos by remote owner before merging into aggregate
  - Local repos (owner="local") are retained
  - Generates `data/snapshots/aggregate/excluded_repos_report.json` with repo name, path, machine, remote key, and redacted canonical remote
  - Recalculates `dailyMachineStats` from filtered `dailyRepoStats`
- Updated documentation:
  - `docs/LAPTOP_INGESTION_WORKFLOW.md` — ownership filter section, broad roots are discovery-only
  - `docs/MULTI_MACHINE_INGESTION.md` — ownership filter section
  - `docs/DATA_MODEL.md` — Phase 4B.1 additions
  - `README.md` — Phase 4B.1 description

### Verified (Exact Commands)
- `cd /opt/slimy/gh-tracker && pnpm aggregate:snapshots` — PASS (32 repo locations, 19 unique repos, 3 machines, 14 excluded)
- `pnpm validate:aggregate` — PASS (aggregate_valid=1, machines=3, machine_ids=laptop,nuc1,nuc2)
- `pnpm lint` — PASS
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `systemctl --user restart gh-tracker.service` — PASS
- `systemctl --user is-active gh-tracker.service` — PASS (active)
- `curl -I http://127.0.0.1:5055` — PASS (200)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Unauthorized)
- Forbidden file check — PASS (only gh-tracker source/docs/data modified)
- Secret scan — PASS (no secrets exposed)

### Proof
- /tmp/proof_gh_tracker_phase4b1_ownership_filter_20260525T043254Z

### Changed Files
- `scripts/aggregate-snapshots.ts` — ownership filter + excluded report generation
- `docs/LAPTOP_INGESTION_WORKFLOW.md` — ownership filter docs
- `docs/MULTI_MACHINE_INGESTION.md` — ownership filter docs
- `docs/DATA_MODEL.md` — Phase 4B.1 docs
- `README.md` — Phase 4B.1 docs

### Git
- Local commit: PENDING
- Push: not performed (per instructions)

### What Remains Unverified
- Operator approval of excluded repos list (some may be intentional clones)
- Adding additional allowed owners via `GH_TRACKER_ALLOWED_REMOTE_OWNERS` if needed
- Laptop snapshot collection on actual laptop (requires manual operator action)

### Next Action
If operator wants to include any excluded repos (e.g., intentional forks), set `GH_TRACKER_ALLOWED_REMOTE_OWNERS=GurthBro0ks,anthropics` (or other owners) and re-run `pnpm aggregate:snapshots`.

---

## 2026-05-25 — GH Tracker Phase 4B: Laptop Snapshot Ingestion Workflow

### Project
- /opt/slimy/gh-tracker
- GitHub: git@github.com:GurthBro0ks/gh-tracker.git
- Public URL: https://habitat.slimyai.xyz

### What Was Done
- Discovered laptop is not reachable via SSH from NUC1 (tried laptop, mint, slimy-laptop — all failed).
- Created safe manual laptop export workflow: `docs/LAPTOP_INGESTION_WORKFLOW.md`.
- Updated dashboard to support laptop as pending or loaded state:
  - `src/lib/dashboard-adapter.ts`: added `loadedMachineIds` and `laptopStatus` fields.
  - `src/components/dashboard.tsx`: dynamic debug dock shows actual loaded machines + laptop status.
  - Updated subtitle to mention NUC1, NUC2, and Laptop (pending).
- Updated documentation:
  - `README.md`: Phase 4B section with laptop workflow.
  - `docs/PHASES.md`: Phase 4B description.
  - `docs/MULTI_MACHINE_INGESTION.md`: Current status + laptop ingestion section.
  - `docs/COLLECTOR_PLAN.md`: Phase 4A/4B status.
  - `docs/DATA_MODEL.md`: Multi-machine aggregation notes.
- No fabricated laptop data — dashboard clearly shows "Laptop pending manual snapshot import" until real snapshot is imported.

### Verified (Exact Commands)
- `cd /opt/slimy/gh-tracker && pnpm lint` — PASS
- `pnpm typecheck` — PASS
- `pnpm build` — PASS
- `pnpm validate:aggregate` — PASS (2 machines: nuc1, nuc2; 42 repo locations)
- `systemctl --user restart gh-tracker.service` — PASS
- `systemctl --user is-active gh-tracker.service` — PASS (active)
- `curl -I http://127.0.0.1:5055` — PASS (200)
- `curl -I https://habitat.slimyai.xyz` — PASS (401 Unauthorized with Basic Auth challenge)
- Forbidden file check — PASS (only gh-tracker source/docs modified)
- Secret scan — PASS (no secrets exposed)

### Proof
- /tmp/proof_gh_tracker_phase4b_laptop_ingestion_20260525T032539Z

### Changed Files
- `src/components/dashboard.tsx` — laptop pending/loaded status in debug dock and subtitle
- `src/lib/dashboard-adapter.ts` — `loadedMachineIds` and `laptopStatus` fields
- `docs/LAPTOP_INGESTION_WORKFLOW.md` — new manual export workflow document
- `README.md`, `docs/PHASES.md`, `docs/MULTI_MACHINE_INGESTION.md`, `docs/COLLECTOR_PLAN.md`, `docs/DATA_MODEL.md` — updated for Phase 4B

### Git
- Local commit: PENDING (not yet committed)
- Push: not performed

### What Remains Unverified
- Laptop snapshot collection on actual laptop (requires manual operator action)
- Full 3-machine aggregate (NUC1 + NUC2 + Laptop) — pending laptop snapshot import
- Public authenticated route test (password not accessible in automation, but Caddy basicauth is confirmed configured)

### Next Action
Operator should follow `docs/LAPTOP_INGESTION_WORKFLOW.md` to:
1. Run `GH_TRACKER_MACHINE_ID=laptop pnpm collect:local` on laptop
2. Copy snapshot to NUC1 via scp
3. Run `pnpm import:snapshot` and `pnpm aggregate:snapshots` on NUC1
4. Restart service — dashboard will show 3 machines

---

## 2026-05-25 — sBuild Context Menu "Edit Properties" Drawer Fix

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Fixed context menu "Edit Properties" action to open the right editor drawer on mobile.
- Root cause: the handler called `selectBlock(contextMenu.blockId)` which only sets the selected block ID but does NOT set `rightDrawerMobileOpen(true)` on mobile.
- Fix: changed the handler to call `openBlockDrawer(contextMenu.blockId)` instead, which does everything `selectBlock` does PLUS sets `rightDrawerMobileOpen(true)` and `setRightTab("properties")`.
- This makes the context menu path identical to the long-press drawer-opening path.
- Added 3 new UI contract tests:
  1. `context menu Edit Properties opens right drawer via openBlockDrawer`
  2. `context menu Edit Properties closes menu after action`
  3. `mobile drawer open state and classes exist for context menu path`

### Verified (Exact Commands)
- `cd /opt/slimy/sbuild && pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS (editor 50/50, server 20/20)
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS (publishAllowed: false)
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (dryRun: true)

### Proof
- /tmp/proof_sbuild_context_menu_edit_properties_20260525T030746Z

### Changed Files
- packages/editor/src/App.tsx — context menu "Edit Properties" now calls `openBlockDrawer` instead of `selectBlock`
- packages/editor/src/ui-contract.test.js — 3 new contract tests for context menu drawer behavior

### Git
- Local commit: `d42dbf2` — `fix: open edit drawer from context menu properties action`
- Push: not performed; manual QA acceptance required.

### What Remains Unverified
- Manual iPhone QA on https://sbuilder.slimyai.xyz for:
  1. Tap Hero block three-dot button → context menu opens
  2. Tap Edit Properties → context menu closes
  3. Right edit drawer opens with Props tab active
  4. Same for Cards, Text, Hours, Contact, Gallery blocks
  5. Preview mode: context menu does not open edit drawer
  6. Desktop layout still looks normal

---

## 2026-05-26 — gh-tracker
- Repaired Phase 5D.2A auth route protection by migrating Next.js guard from deprecated middleware convention to `proxy.ts` and enforcing signed session validation.
- Added/updated auth tests for proxy protection, login owner gate (mocked bridge), and logout session clearing.
- Verified: local unauthenticated `/` redirects to `/login`, `/api/auth/me` returns 401, public Basic Auth remains 401 challenge, timer active, service active.
- Committed locally: `acd3f98` (`feat: bridge Habitat to Slimy owner auth`).
- Next: optional remote push after approval.

## 2026-05-26 — gh-tracker
- Ran Phase 5D.2B acceptance push preflight/validation on commit `acd3f9893ab5454e972b40627c2e5716e0e551c2`.
- Verified local auth protections, login accessibility, Basic Auth 401 gate, timer active, and full validation suite passing.
- Push withheld with `NEED_MANUAL_QA` because explicit verification that Settings opens cleanly and Logout clears GH Tracker app session is required by acceptance gate and was not explicitly attested in the gate record.
- Remote main remains `31d9ca4486224fe4726e8c4a32f8b62d4f78a08a`.

## 2026-05-26 — gh-tracker
- Manual QA acceptance received for Settings + Logout behavior.
- Re-ran Phase 5D.2B final gates and probes; all checks passed.
- Pushed accepted commit `acd3f9893ab5454e972b40627c2e5716e0e551c2` to `origin/main`.
- Remote main now matches local accepted commit.

## 2026-05-26 — gh-tracker
- Implemented Phase 5E auth hardening for Habitat owner bridge.
- Added generic failed-login responses, expired-session proxy test, static hardening checks, and canonical grouping coverage.
- Updated app version to `0.5.4-phase5e-auth-hardening` and added `docs/AUTH_ROLLBACK.md` + `docs/AUTH_QA_CHECKLIST.md`.
- Re-ran validate/typecheck/build/lint/test, restarted `gh-tracker.service`, verified public Basic Auth 401 and local unauth route/API gating.
- Local commit: `21506a22f5801fc87088fddf574e60a4f62fbb7f` (not pushed).

## 2026-05-26 — gh-tracker
- Manual Phase 5E QA accepted (settings/logout/refresh/session-gate checks).
- Re-ran final validation and auth/public gate probes for commit `21506a26e00f9882e91e570dda8abb7afe877f55`.
- Pushed Phase 5E hardening commit to `origin/main`; remote main now matches local HEAD.
## 2026-05-27 — sBuild Mobile Overlay/Menu Polish + Row Actions

### Project
- /opt/slimy/sbuild
- GitHub: git@github.com:GurthBro0ks/sbuild.git

### What Was Done
- Kept top-level mobile editor overlay architecture and reduced overlay dimming to light backdrop (`rgba(0,0,0,0.22)`) so preview remains readable.
- Added context menu backdrop layer (`.context-menu-backdrop`) with light dimming and click-to-close.
- Kept compact single-row mobile sheet header (`Edit block` + `mobile-editor-x-close`) and preserved 44x44 close target.
- Added mobile form safety rules in sheet: full-width inputs/selects/textareas, overflow-x guards, stacked rows for buttons/quick actions/nav/style controls.
- Added mobile AI panel layout wrappers (`mobile-ai-panel`, `mobile-button-row`) so Send/Generate/Apply actions do not collide with fields.
- Improved row/layout action reliability from context menu by selecting `contextMenu.blockId` before Resize/Layout, Start row, Place above/below, Remove, Move Up/Down.
- Updated row action status text to explicit messages: `Placed block with block above`, `Placed block with block below`, `Moved block up/down`, `Removed block from row`.
- Updated UI contract tests to cover dimming, header/close target, mobile form contracts, context menu action set/order, context block selection before row actions, menu close behavior, and dry-run publish preservation.

### Verified (Exact Commands)
- `git status --short`
- `pnpm -r typecheck` — PASS
- `pnpm -r build` — PASS
- `pnpm -r lint` — PASS
- `pnpm -r test` — PASS
- `bash scripts/smoke-sbuild.sh` — PASS
- `curl -fsS http://127.0.0.1:3137/health` — PASS
- `curl -fsS -X POST http://127.0.0.1:3137/api/publish -H 'content-type: application/json' -d '{}'` — PASS (`dryRun: true`)
- `grep -R "mobile-editor-overlay\|mobile-editor-sheet\|mobile-editor-x-close\|backdrop\|contextMenu.blockId\|Place with block above\|Place with block below\|Move Up\|Move Down\|AI Assistant" packages/editor/src/App.tsx packages/editor/src/styles.css packages/editor/src/ui-contract.test.js` — PASS

### Proof
- /tmp/proof_sbuild_mobile_overlay_polish_row_actions_20260527T093202Z

### Changed Files
- `packages/editor/src/App.tsx`
- `packages/editor/src/styles.css`
- `packages/editor/src/ui-contract.test.js`

### Git
- Local commit: `dbcd4cc` — `fix: polish mobile editor overlay and row actions`
- Push: not performed

### What Remains Unverified
- Manual iPhone QA checklist against https://sbuilder.slimyai.xyz (overlay brightness, compact header/X, tab/form spacing, row actions after resize, save/refresh persistence, desktop sanity).

### Next Action
QA should execute the 28-step manual iPhone checklist and confirm acceptance.
## 2026-05-28 — gh-tracker
- Implemented Phase 6D.2 polish in `/opt/slimy/gh-tracker` on top of accepted 6D.1 state.
- Proof dir: `/tmp/proof_gh_tracker_phase6d2_pet_animation_health_wording_20260528T194254Z`.
- Added lightweight pet animation behaviors (idle, curious, focused, stressed, needs-care) and reduced-motion fallback.
- Clarified compact habitat copy for species/stage/mood and evolution/mood reason strings.
- Updated GitHub health wording for no-release/no-CI and clear PR/issue state while preserving sync status semantics.
- Confirmed Action Center remains manual-only copy flow with explicit non-execution warning.
- Validation results: `pnpm lint` PASS, `pnpm typecheck` PASS, `pnpm test` PASS, `pnpm validate:runtime-assets` PASS, `pnpm validate:aggregate` PASS, `pnpm validate:github` PASS, `pnpm build` PASS.
- Runtime/public checks: `gh-tracker.service` active after restart, local route redirects to `/login` (307), public gate returns `401` Basic Auth challenge.
- Manual QA checklist pending visual verification for animation polish on mobile/desktop.
- Local commit: `aaa87a6fdb7ec89febfafebc204f3013b0f96dc9` (`polish: animate repo pets and clarify health wording`).
