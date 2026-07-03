# Bot Validation Recipes (slimy-monorepo)

Canonical test invocations for SlimyAI bot mission prompts and truth gates.
Written after Fable bot audit finding F8: mission prompts kept using
Jest-style arguments with Vitest, wrong test paths that were silently
dropped, and `|| true` patterns that masked failures. Copy recipes from
here — do not improvise test commands in mission prompts.

The monorepo lives at `/opt/slimy/slimy-monorepo` (NUC1). The bot app is
`apps/bot` (Discord bot, Vitest; NOT a placeholder). Standalone script tests
live in `scripts/__tests__/` at the repo root.

## 1. Focused bot tests (the default for bot missions)

Run named test files directly with Vitest from `apps/bot`:

```bash
cd /opt/slimy/slimy-monorepo/apps/bot
npx vitest run tests/lib/club-write-guard.test.ts tests/lib/club-write-policy.test.ts
rc=$?
echo "$rc"
```

Known-correct bot test paths (relative to `apps/bot/`):

- `tests/lib/club-write-guard.test.ts`
- `tests/lib/club-write-policy.test.ts`

WRONG paths seen in past prompts — these look plausible but match nothing:

- `apps/bot/tests/club-write-guard.test.ts` (missing `lib/`)
- running `tests/...` paths from the repo root instead of `apps/bot/`

### Vitest filter behavior — why wrong paths are dangerous

Vitest CLI arguments are path FILTERS, not required files:

- If NO filter matches, Vitest exits non-zero ("No test files found") —
  which past prompts then masked with `|| true`.
- If SOME filters match, non-matching filters are SILENTLY IGNORED and the
  run still reports green. A typo'd path means that test never ran.

Therefore: after any focused run, verify the reported "Test Files" count
equals the number of files you asked for. If you asked for 2 and it ran 1,
the run is a FAIL for proof purposes even if exit code is 0.

## 2. Script tests (`scripts/__tests__/`, not `scripts/tests/`)

Root-level migration/utility script tests use a separate Vitest config:

```bash
cd /opt/slimy/slimy-monorepo
npx vitest run --config scripts/vitest.config.mjs scripts/__tests__/migrate-multi-club-write-policy.test.mjs
rc=$?
echo "$rc"
```

Known-correct script test paths:

- `scripts/__tests__/migrate-multi-club-write-policy.test.mjs`
- `scripts/__tests__/migrate-multi-club-track-b-schema.test.mjs`

The directory is `scripts/__tests__/`. `scripts/tests/` does not exist.
`pnpm test:scripts` runs the whole script-test config (fine for full script
coverage; use the explicit path form above for focused runs).

## 3. Jest flags do not work with Vitest

- `--runInBand` is a Jest flag. Vitest rejects it and the run fails without
  running any tests. Do not use it in prompts.
- If a serial run is genuinely needed, the Vitest equivalent is
  `--no-file-parallelism`. Usually you do not need it.

## 4. Wrapper commands expand to full suites

These are FULL-SUITE commands. Never use them when a focused test was
intended, and never present their output as proof of a focused fix:

| Command | Actually runs |
|---------|---------------|
| `pnpm --filter @slimy/bot test` | entire bot suite (`vitest run`, no filter) |
| `pnpm test:bot` (repo root) | entire bot suite |
| `pnpm test:all` (repo root) | every workspace suite (bot + web + admin) |
| `pnpm test:scripts` (repo root) | entire scripts/__tests__ suite |

Appending a path to a pnpm wrapper (`pnpm test:bot tests/lib/foo.test.ts`)
depends on pnpm arg passthrough and the caller's cwd — prompts should use
the direct `npx vitest run <paths>` form from the correct directory instead.

## 5. Honest exit-code capture

The proof pattern is: run, capture `$?` immediately, then report.

```bash
npx vitest run tests/lib/club-write-guard.test.ts > "$PROOF_DIR/bot_tests.txt" 2>&1
rc=$?
echo "$rc" > "$PROOF_DIR/bot_tests_exit.txt"
```

NEVER this:

```bash
some-test-command || true; echo $?   # BROKEN — $? is from `true`, always 0
```

If the shell runs with `set -e` and you must not abort on failure, capture
into a variable instead of discarding the status:

```bash
rc=0
npx vitest run tests/lib/club-write-guard.test.ts > "$PROOF_DIR/bot_tests.txt" 2>&1 || rc=$?
echo "$rc" > "$PROOF_DIR/bot_tests_exit.txt"
```

`|| true` is acceptable only for best-effort cleanup/notify lines whose
status is genuinely irrelevant — never on a command whose result feeds a
PASS/WARN/FAIL claim.

## 6. Full-suite runs: known-WARN handling

As of 2026-07-03, the full suite (`pnpm test:all`) has one known unrelated
WARN: `version-manifest.test.ts` fails because apps/web is 0.4.0 while the
manifest says 0.4.3. When a mission runs the full suite:

- Report it explicitly as KNOWN-WARN with the failing test name.
- Do not report the run as clean PASS, and do not hide the failure behind
  `|| true` or a truncated log.
- Any OTHER failure in the same run is a real FAIL, not part of this WARN.

If the version-manifest mismatch has since been fixed, a fully green
`pnpm test:all` is a plain PASS and this section no longer applies —
verify, don't assume.

## 7. Prompt-authoring checklist

When writing a mission VALIDATION section that touches the bot:

1. Copy the exact focused-test recipe from section 1/2 — correct cwd,
   correct paths, `npx vitest run`.
2. Capture exit codes per section 5 — never `|| true; echo $?`.
3. State whether the mission expects a focused run or full suite; if full
   suite, include the section 6 known-WARN wording.
4. Require the agent to check the reported test-file count against the
   number of requested files (section 1).

Regression coverage for this doc and the templates that point to it:
`sequencer/tests/test_validation_recipe_docs.sh` in slimy-harness.
