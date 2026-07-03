#!/usr/bin/env bash
# test_validation_recipe_docs.sh — bot validation recipes stay correct and
# prompt templates never reintroduce the Fable audit F8 anti-patterns:
# Jest-style flags with Vitest, wrong test paths, masked exit codes, and
# focused-test prompts that silently run full suites.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOC="$REPO_ROOT/docs/BOT_VALIDATION_RECIPES.md"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== test_validation_recipe_docs.sh ==="
echo "REPO_ROOT=$REPO_ROOT"

# Prompt/template files that agents copy validation commands from, plus the
# recipe doc itself and the scripts that drive automated sessions.
TEMPLATE_FILES=(
  "auto-prompts.sh"
  "server/auto-prompts.md"
  "server/AGENTS.md"
  "PROMPT_TEMPLATES.md"
  "per-repo/slimy-monorepo/AGENTS.md"
  "cheat-sheets/CHEAT_SHEET_FINAL.md"
  "sequencer/goal_runner.py"
  "sequencer/auto-sequence.sh"
  "docs/BOT_VALIDATION_RECIPES.md"
)

# ------------------------------------------------------------
# 1. Canonical recipe doc exists with required content
# ------------------------------------------------------------
if [[ -f "$DOC" ]]; then
  pass "docs/BOT_VALIDATION_RECIPES.md exists"
else
  fail "docs/BOT_VALIDATION_RECIPES.md missing"
fi

REQUIRED_MARKERS=(
  "tests/lib/club-write-guard.test.ts"
  "tests/lib/club-write-policy.test.ts"
  "scripts/__tests__/migrate-multi-club-write-policy.test.mjs"
  "scripts/__tests__/migrate-multi-club-track-b-schema.test.mjs"
  "runInBand"
  "version-manifest"
  "rc=\$?"
  "test:all"
)
for marker in "${REQUIRED_MARKERS[@]}"; do
  if [[ -f "$DOC" ]] && grep -qF -- "$marker" "$DOC"; then
    pass "recipe doc covers: $marker"
  else
    fail "recipe doc missing required content: $marker"
  fi
done

# ------------------------------------------------------------
# 2. No Jest-style --runInBand in any command context
#    (lowercase runner names = actual invocations; prose that merely warns
#    about the flag capitalizes "Vitest"/"Jest" and names no runner)
# ------------------------------------------------------------
for f in "${TEMPLATE_FILES[@]}"; do
  path="$REPO_ROOT/$f"
  [[ -f "$path" ]] || continue
  hits=$(grep -nE 'vitest[^A-Za-z]+.*--runInBand|--runInBand.*vitest|npx .*--runInBand|pnpm .*--runInBand|jest .*--runInBand' "$path")
  if [[ -z "$hits" ]]; then
    pass "no --runInBand invocation: $f"
  else
    fail "--runInBand used in a command in $f: $hits"
  fi
done

# ------------------------------------------------------------
# 3. Wrong test paths only ever appear as flagged anti-patterns
# ------------------------------------------------------------
for f in "${TEMPLATE_FILES[@]}"; do
  path="$REPO_ROOT/$f"
  [[ -f "$path" ]] || continue

  # scripts/tests/ (real dir is scripts/__tests__/)
  hits=$(grep -n 'scripts/tests/' "$path" | grep -viE 'never|not|wrong')
  if [[ -z "$hits" ]]; then
    pass "no unflagged scripts/tests/ path: $f"
  else
    fail "unflagged wrong path scripts/tests/ in $f: $hits"
  fi

  # apps/bot/tests/club-write-*.test.ts (real files are under tests/lib/)
  hits=$(grep -n 'apps/bot/tests/club-write' "$path" | grep -viE 'missing|never|not|wrong')
  if [[ -z "$hits" ]]; then
    pass "no unflagged truncated club-write path: $f"
  else
    fail "unflagged truncated bot test path in $f: $hits"
  fi
done

# ------------------------------------------------------------
# 4. No masked exit-code pattern except as a flagged anti-pattern
# ------------------------------------------------------------
for f in "${TEMPLATE_FILES[@]}"; do
  path="$REPO_ROOT/$f"
  [[ -f "$path" ]] || continue
  hits=$(grep -nE '\|\| true[[:space:]]*;[[:space:]]*echo \$\?' "$path" | grep -viE 'never|broken')
  if [[ -z "$hits" ]]; then
    pass "no unflagged '|| true; echo \$?' masking: $f"
  else
    fail "masked exit-code pattern in $f: $hits"
  fi
done

# ------------------------------------------------------------
# 5. Monorepo-facing templates point at the canonical recipe doc
# ------------------------------------------------------------
REFERENCING_FILES=(
  "server/AGENTS.md"
  "server/auto-prompts.md"
  "auto-prompts.sh"
  "PROMPT_TEMPLATES.md"
  "per-repo/slimy-monorepo/AGENTS.md"
  "cheat-sheets/CHEAT_SHEET_FINAL.md"
)
for f in "${REFERENCING_FILES[@]}"; do
  path="$REPO_ROOT/$f"
  if [[ -f "$path" ]] && grep -q 'BOT_VALIDATION_RECIPES' "$path"; then
    pass "references recipe doc: $f"
  else
    fail "missing BOT_VALIDATION_RECIPES reference: $f"
  fi
done

# ------------------------------------------------------------
# 6. Templates that mention full-suite wrappers flag the expansion,
#    and the known full-suite WARN is documented
# ------------------------------------------------------------
if grep -qE 'FULL' "$REPO_ROOT/cheat-sheets/CHEAT_SHEET_FINAL.md" \
   && grep -qE 'FULL' "$REPO_ROOT/per-repo/slimy-monorepo/AGENTS.md"; then
  pass "full-suite wrapper expansion is flagged in templates"
else
  fail "full-suite wrapper expansion warning missing from templates"
fi

if grep -q 'KNOWN-WARN' "$REPO_ROOT/per-repo/slimy-monorepo/AGENTS.md" \
   && grep -q 'version-manifest' "$REPO_ROOT/per-repo/slimy-monorepo/AGENTS.md"; then
  pass "known version-manifest WARN documented for full-suite runs"
else
  fail "known version-manifest WARN handling missing from monorepo AGENTS.md"
fi

echo ""
echo "SUMMARY: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
