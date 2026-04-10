#!/usr/bin/env bash
# ============================================================
# slimy-harness — Sync State Checker
#
# Prints a concise sync verdict for slimy-harness vs origin/main.
# Safe to run anytime; read-only (git fetch + status).
#
# Usage:
#   bash scripts/check-sync-state.sh
#   bash scripts/check-sync-state.sh [--fetch]
#
# Exit codes:
#   0  = in sync or ahead only
#   1  = behind or diverged (needs attention before push)
#   2  = no origin available / not a git repo
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FETCH_FIRST=false
if [[ "${1:-}" == "--fetch" ]]; then
  FETCH_FIRST=true
fi

# Colour helpers
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Check this is a git repo with an origin
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo -e "${RED}[ERROR]${NC} Not a git repo: $REPO_ROOT"
  exit 2
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo -e "${RED}[ERROR]${NC} No origin remote configured"
  exit 2
fi

# Optionally fetch first
if [[ "$FETCH_FIRST" == "true" ]]; then
  git fetch origin --quiet 2>/dev/null || {
    echo -e "${YELLOW}[WARN]${NC} Could not fetch origin (network/credentials issue)"
    echo -e "       Running with cached data. Use --fetch to refresh."
  }
fi

# Compare local HEAD to origin/main
LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null)
UPSTREAM_HEAD=$(git rev-parse origin/main 2>/dev/null)

if [[ -z "$UPSTREAM_HEAD" ]]; then
  echo -e "${YELLOW}[WARN]${NC} origin/main not available (first push or no network)"
  echo -e "       Local HEAD: ${LOCAL_HEAD:0:8}"
  exit 2
fi

if [[ "$LOCAL_HEAD" == "$UPSTREAM_HEAD" ]]; then
  echo -e "${GREEN}[OK]${NC}   In sync with origin/main"
  echo -e "       HEAD: ${LOCAL_HEAD:0:8}"
  exit 0
fi

# Check for divergence: both have commits the other doesn't
LOCAL_AHEAD=$(git rev-list --count "$UPSTREAM_HEAD..$LOCAL_HEAD" 2>/dev/null || echo "?")
UPSTREAM_AHEAD=$(git rev-list --count "$LOCAL_HEAD..$UPSTREAM_HEAD" 2>/dev/null || echo "?")

LOCAL_DESC=$(git log --oneline -n 1 "$LOCAL_HEAD" 2>/dev/null | cut -d' ' -f2-)
UPSTREAM_DESC=$(git log --oneline -n 1 "$UPSTREAM_HEAD" 2>/dev/null | cut -d' ' -f2-)

if [[ "$LOCAL_AHEAD" -gt 0 ]] && [[ "$UPSTREAM_AHEAD" -gt 0 ]]; then
  echo -e "${RED}[DIVERGED]${NC}  Local and origin/main have split histories"
  echo ""
  echo -e "  Local (ahead $LOCAL_AHEAD, your commits):"
  echo -e "    $LOCAL_DESC"
  echo ""
  echo -e "  origin/main (ahead $UPSTREAM_AHEAD, other commits):"
  echo -e "    $UPSTREAM_DESC"
  echo ""
  echo -e "  ${RED}ACTION REQUIRED${NC}: Merge or rebase before pushing."
  echo -e "  DO NOT force-push when others may have pushed."
  exit 1
fi

if [[ "$LOCAL_AHEAD" -gt 0 ]]; then
  echo -e "${YELLOW}[AHEAD]${NC}  Local is $LOCAL_AHEAD commit(s) ahead of origin/main"
  echo -e "  Local HEAD: ${LOCAL_HEAD:0:8} — $LOCAL_DESC"
  echo -e "  origin/main: ${UPSTREAM_HEAD:0:8} — $UPSTREAM_DESC"
  echo -e "  ${YELLOW}ACTION${NC}: Safe to push if ready. Fetch+rebase recommended."
  exit 0
fi

# Behind only
echo -e "${YELLOW}[BEHIND]${NC} Local is $UPSTREAM_AHEAD commit(s) behind origin/main"
echo -e "  Local HEAD: ${LOCAL_HEAD:0:8} — $LOCAL_DESC"
echo -e "  origin/main: ${UPSTREAM_HEAD:0:8} — $UPSTREAM_DESC"
echo -e "  ${YELLOW}ACTION${NC}: Pull or reset --hard origin/main before working."
exit 1
