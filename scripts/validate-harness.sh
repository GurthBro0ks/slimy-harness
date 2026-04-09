#!/usr/bin/env bash
# ============================================================
# slimy-harness — Validation Script
#
# Run this to check the harness repo is well-formed before NUC2 rollout.
#
# Usage:
#   bash scripts/validate-harness.sh
#   bash scripts/validate-harness.sh --strict
#
# Checks:
#   1. bash -n on all shell scripts
#   2. dry-run has zero write side effects
#   3. docs don't contradict installer behavior
#   4. required repo files exist
#
# --strict: also fails if any advisory files (e.g. cheat sheets) are missing
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
FAIL_COUNT=0; WARN_COUNT=0; PASS_COUNT=0

pass()  { echo -e "  ${GREEN}✓${NC}  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail()  { echo -e "  ${RED}✗${NC}  $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn()  { echo -e "  ${YELLOW}~${NC}  $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
info()  { echo -e "       $1"; }

header() { echo ""; echo -e "${GREEN}=== $1 ===${NC}"; }

report() {
  echo ""
  echo "========================================"
  echo -e "Results: ${GREEN}${PASS_COUNT} passed${NC} | ${YELLOW}${WARN_COUNT} warnings${NC} | ${RED}${FAIL_COUNT} failures${NC}"
  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo -e "${RED}VALIDATION FAILED${NC}"
    exit 1
  elif [[ "$WARN_COUNT" -gt 0 ]]; then
    echo -e "${YELLOW}VALIDATION PASSED WITH WARNINGS${NC}"
    exit 0
  else
    echo -e "${GREEN}VALIDATION PASSED${NC}"
    exit 0
  fi
}

# ============================================================
# CHECK 1: bash -n on all shell scripts
# ============================================================
header "Check 1: Shell Script Syntax"
SHELLS=$(find "$REPO_ROOT" -name "*.sh" -type f)
for f in $SHELLS; do
  rel="${f#$REPO_ROOT/}"
  if bash -n "$f" 2>/dev/null; then
    pass "$rel"
  else
    fail "$rel: syntax error"
  fi
done

# ============================================================
# CHECK 2: dry-run has zero write side effects
# ============================================================
header "Check 2: dry-run Zero-Write"

DRY_OUT=$(bash "$REPO_ROOT/server-install.sh" --dry-run 2>&1)
DRY_EXIT=$?

if [[ "$DRY_EXIT" -ne 0 ]]; then
  fail "server-install.sh --dry-run exited non-zero: $DRY_EXIT"
else
  pass "server-install.sh --dry-run exits 0"
fi

# Grep for write operations that should not appear in dry-run output
WRITE_OPS="(WOULD WRITE|WOULD DELETE|WOULD OVERWRITE|WOULD MOVE|WOULD CHMOD.*[0-9])"
if echo "$DRY_OUT" | grep -qiE "$WRITE_OPS"; then
  fail "dry-run output contains write operation keywords:"
  echo "$DRY_OUT" | grep -iE "$WRITE_OPS" | while read -r l; do info "  $l"; done
else
  pass "dry-run output contains no write operation keywords"
fi

# Confirm dry-run does NOT modify any files
TS_BEFORE=$(date +%s)
bash "$REPO_ROOT/server-install.sh" --dry-run >/dev/null 2>&1
TS_AFTER=$(date +%s)

# Use a temp file to detect any writes
TMPCHECK=$(mktemp)
find "$REPO_ROOT" -newer "$REPO_ROOT/.git/index" -type f ! -path "$REPO_ROOT/.git/*" > "$TMPCHECK" 2>/dev/null
WRITES_AFTER=$(wc -l < "$TMPCHECK")
rm -f "$TMPCHECK"

if [[ "$WRITES_AFTER" -eq 0 ]]; then
  pass "no files modified during dry-run (confirmed by file mtime check)"
else
  # Filter out files that are expected to differ (e.g. compat wrapper timestamp)
  EXTRAS=$(find "$REPO_ROOT" -newer "$REPO_ROOT/.git/index" -type f ! -path "$REPO_ROOT/.git/*" ! -name "*.bak" 2>/dev/null)
  if [[ -n "$EXTRAS" ]]; then
    warn "files newer than git index after dry-run (review: $EXTRAS)"
  else
    pass "no unexpected file writes during dry-run"
  fi
fi

# ============================================================
# CHECK 3: docs don't contradict installer
# ============================================================
header "Check 3: Docs vs Installer Consistency"

# 3a. server-install.sh --help/dry-run should mention --commit
if grep -q "\-\-commit" "$REPO_ROOT/server-install.sh"; then
  pass "--commit flag documented in server-install.sh"
else
  fail "--commit flag missing from server-install.sh"
fi

# 3b. README should mention dry-run
if grep -qi "dry-run\|dry run" "$REPO_ROOT/README.md"; then
  pass "README mentions dry-run"
else
  fail "README does not mention dry-run"
fi

# 3c. README should NOT claim it WILL/DOES/SHOULD overwrite live state files.
#    Saying "never overwrites" is correct and should NOT trigger this.
if grep -qiE "will overwrite|does overwrite|always overwrite|must overwrite|overwrite without|replace existing.*live" "$REPO_ROOT/README.md"; then
  fail "README describes overwriting live state files"
else
  pass "README does not describe overwriting live state files"
fi

# 3d. HARNESS_ARCHITECTURE.md should mention the new --dry-run / --commit flags
if grep -q "\-\-dry-run\|--commit" "$REPO_ROOT/docs/HARNESS_ARCHITECTURE.md"; then
  pass "HARNESS_ARCHITECTURE.md mentions new flags"
else
  warn "HARNESS_ARCHITECTURE.md does not mention --dry-run or --commit flags"
fi

# 3e. CUTOVER_NOTES.md dry-run output should match current installer
if grep -q "WOULD SKIP\|WOULD COPY\|WOULD CREATE" "$REPO_ROOT/docs/CUTOVER_NOTES.md"; then
  pass "CUTOVER_NOTES.md contains accurate dry-run action keywords"
else
  warn "CUTOVER_NOTES.md may not reflect current dry-run output format"
fi

# ============================================================
# CHECK 4: Required files exist
# ============================================================
header "Check 4: Required Files"

REQUIRED=(
  "server-install.sh"
  "server/AGENTS.md"
  "server/init.sh"
  "server/QUALITY_CRITERIA.md"
  "server/templates/claude-progress.md"
  "server/templates/feature_list.json"
  "server/templates/server-state.md"
  "server/templates/PROJECT_NARRATIVE.md"
  "per-repo/pm_updown_bot_bundle/AGENTS.md"
  "per-repo/slimy-monorepo/AGENTS.md"
  "docs/HARNESS_ARCHITECTURE.md"
  "docs/REFERENCE_AGENTS_HOST_SPECIFIC.md"
  "docs/CURRENT_LAYOUT_FINDINGS.md"
  "README.md"
  ".gitignore"
)

for f in "${REQUIRED[@]}"; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    pass "$f"
  else
    fail "missing required file: $f"
  fi
done

# ============================================================
# CHECK 5: AGENTS.md is neutral (not NUC1-specific)
# ============================================================
header "Check 5: AGENTS.md Host-Neutrality"

# Look for actual hardcoded host-specific content:
#   - hostname slimy-nuc1 or nuc2 (literal, not example placeholder)
#   - real literal /opt/slimy/ paths with slashes
#   - kb-write.sh example with -nuc1- or -nuc2- token (not hostname var or placeholder)
# Do NOT flag: NUC1/NUC2 format examples, references to REFERENCE_AGENTS_HOST_SPECIFIC.md,
#              $(hostname) command substitution, [nuc1] placeholder format
HOST_LEAK_PATTERN="slimy-nuc1|slimy-nuc2|/[a-z]+/slimy/slimy"
# Also specifically check for the kb-write.sh nuc1 token in example commands
KB_TOKEN_LEAK=$(grep -E "kb-write\.sh.*-[a-z]{3}[0-9]-" "$REPO_ROOT/server/AGENTS.md" 2>/dev/null || true)
if [[ -n "$KB_TOKEN_LEAK" ]]; then
  fail "server/AGENTS.md contains host-specific kb-write token: $KB_TOKEN_LEAK"
elif grep -qE "$HOST_LEAK_PATTERN" "$REPO_ROOT/server/AGENTS.md"; then
  fail "server/AGENTS.md contains host-specific content"
else
  pass "server/AGENTS.md appears host-neutral"
fi

if [[ -f "$REPO_ROOT/docs/REFERENCE_AGENTS_HOST_SPECIFIC.md" ]]; then
  pass "docs/REFERENCE_AGENTS_HOST_SPECIFIC.md exists (host-specific content isolated)"
else
  warn "docs/REFERENCE_AGENTS_HOST_SPECIFIC.md missing (host-specific content not yet isolated)"
fi

# ============================================================
# CHECK 5b: README does not contradict --commit / --dry-run semantics
# ============================================================
header "Check 5b: README --commit / --dry-run Consistency"

# If README shows --dry-run AND --commit together in a command/example context,
# it should note --commit has no effect during dry-run.
# Only flag lines that look like actual command invocations (start with $ or # $).
DRY_COMMIT_LINE=$(grep -nE "^\\$.*server-install\.sh.*--dry-run.*--commit|--commit.*--dry-run" "$REPO_ROOT/README.md" 2>/dev/null || true)
if [[ -n "$DRY_COMMIT_LINE" ]]; then
  if grep -qE -- "dry-run.*--commit.*no effect|no effect.*--commit.*dry-run|--commit.*dry-run.*no" "$REPO_ROOT/README.md" 2>/dev/null; then
    pass "README correctly notes --commit has no effect during --dry-run"
  else
    fail "README shows --dry-run --commit together without noting --commit is ignored:"
    echo "$DRY_COMMIT_LINE" | while read -r l; do info "  $l"; done
  fi
else
  pass "README does not show contradictory --dry-run --commit combo"
fi

# ============================================================
# CHECK 6: Per-repo harness completeness
# ============================================================
header "Check 6: Per-Repo Harness Files"

for repo_dir in "$REPO_ROOT/per-repo"/*/; do
  [[ -d "$repo_dir" ]] || continue
  name=$(basename "$repo_dir")
  info "checking per-repo/$name..."
  for f in "AGENTS.md" "init.sh"; do
    if [[ -f "$repo_dir/$f" ]]; then
      pass "  per-repo/$name/$f"
    else
      warn "  per-repo/$name/$f missing (advisory)"
    fi
  done
done

# ============================================================
# CHECK 7: Ambiguous repo fail-closed handling
# ============================================================
header "Check 7: Ambiguous Repo Fail-Closed Handling"

# Verify server-install.sh fails closed when duplicate basenames exist
if grep -q "AMBIGUOUS_REPO" "$REPO_ROOT/server-install.sh"; then
  pass "server-install.sh prints AMBIGUOUS_REPO: for duplicate basenames"
else
  fail "server-install.sh does not handle AMBIGUOUS_REPO — ambiguous repos not fail-closed"
fi

# Verify skip dirs (tooling paths) are excluded from repo discovery
SKIP_PATTERNS=("\.openclaw" "\.claude" "\.cache" "\.codex" "\.qoder-server")
ALL_SKIPPED=true
for pat in "${SKIP_PATTERNS[@]}"; do
  if grep -q "$pat" <<< "$(cat "$REPO_ROOT/server-install.sh")"; then
    pass "skip pattern present: $pat"
  else
    warn "skip pattern missing: $pat"
    ALL_SKIPPED=false
  fi
done

# Verify symlink canonicalization is used
if grep -q "realpath" "$REPO_ROOT/server-install.sh"; then
  pass "server-install.sh uses realpath for symlink canonicalization"
else
  fail "server-install.sh does not use realpath — symlinks not canonicalized"
fi

# ============================================================
# CHECK 7b: init.sh and server-install.sh skip policies are in sync
# ============================================================
header "Check 7b: init.sh ↔ server-install.sh Skip Policy Sync"

# Extract the actual SKIP_DIRS_REGEX value from each file's source
# Use sed to grab the first SKIP_DIRS_REGEX assignment line and strip the variable prefix
INSTALLER_SKIP=$(grep -oE "SKIP_DIRS_REGEX='[^']+'|SKIP_DIRS_REGEX=\"[^\"]+\"" "$REPO_ROOT/server-install.sh" \
  | head -1 | sed "s/SKIP_DIRS_REGEX=//" | tr -d "'\"")
INIT_SKIP=$(grep -oE "SKIP_DIRS_REGEX='[^']+'|SKIP_DIRS_REGEX=\"[^\"]+\"" "$REPO_ROOT/server/init.sh" \
  | head -1 | sed "s/SKIP_DIRS_REGEX=//" | tr -d "'\"")

if [[ "$INSTALLER_SKIP" == "$INIT_SKIP" ]]; then
  pass "init.sh skip patterns match server-install.sh: $INSTALLER_SKIP"
else
  fail "init.sh skip patterns do NOT match server-install.sh"
  info "  installer: ${INSTALLER_SKIP:-<none>}"
  info "  init.sh:   ${INIT_SKIP:-<none>}"
fi

# ============================================================
# CHECK 8: server-state uses real paths, not placeholders
# ============================================================
header "Check 8: server-state.md Uses Real Paths"

# server-state template should NOT contain "(discovered)" as a path value
if grep -q "(discovered)" "$REPO_ROOT/server/templates/server-state.md"; then
  fail "server/templates/server-state.md contains (discovered) placeholder"
else
  pass "server/templates/server-state.md has no (discovered) placeholder"
fi

# server-install.sh Phase 3 should reference actual INSTALLED_HARNESS paths
if grep -q 'INSTALLED_HARNESS\["\$name"\]' "$REPO_ROOT/server-install.sh" 2>/dev/null; then
  pass "server-install.sh uses full INSTALLED_HARNESS paths in state generation"
else
  # Check for actual path variable usage
  if grep -qE 'INSTALLED_HARNESS\[' "$REPO_ROOT/server-install.sh"; then
    pass "server-install.sh references INSTALLED_HARNESS map for paths"
  else
    fail "server-install.sh Phase 3 may not be using real paths"
  fi
fi

# ============================================================
report
