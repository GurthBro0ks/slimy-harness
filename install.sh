#!/usr/bin/env bash
# SlimyAI Harness Auto-Installer
# Run from inside any slimyai repo root on nuc1 or nuc2
# Usage: bash /home/slimy/harness-kit/install.sh
set -euo pipefail

KIT="/home/slimy/harness-kit"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${GREEN}=== SlimyAI Harness Installer ===${NC}"

# Detect which repo we're in
if [ -f "pnpm-workspace.yaml" ] && [ -f "package.json" ]; then
  REPO="slimy-monorepo"
elif [ -f "runner.py" ] && [ -d "strategies" ]; then
  REPO="pm_updown_bot_bundle"
elif [ -f "mission-control.sh" ] || [ -f "taskboard.json" ]; then
  REPO="mission-control"
else
  echo -e "${RED}ERROR: Can't detect repo. Run this from inside a slimyai repo root.${NC}"
  echo "Supported: slimy-monorepo, pm_updown_bot_bundle, mission-control"
  exit 1
fi

echo -e "Detected repo: ${YELLOW}${REPO}${NC}"

SRC="${KIT}/${REPO}"

# Check if harness kit exists for this repo
if [ ! -d "$SRC" ]; then
  # Fall back to shared template for repos without custom harness files
  echo -e "${YELLOW}No custom harness for ${REPO} — using shared template${NC}"
  SRC="${KIT}/shared"
fi

# Backup existing AGENTS.md if present
if [ -f "AGENTS.md" ]; then
  cp AGENTS.md AGENTS.md.bak
  echo -e "Backed up existing AGENTS.md → AGENTS.md.bak"
fi

# Copy harness files
for f in AGENTS.md feature_list.json claude-progress.md init.sh; do
  if [ -f "${SRC}/${f}" ]; then
    cp "${SRC}/${f}" "./${f}"
    echo -e "${GREEN}✓${NC} Installed ${f}"
  else
    echo -e "${YELLOW}⚠${NC} ${f} not found in kit — skipping"
  fi
done

# Make init.sh executable
[ -f "init.sh" ] && chmod +x init.sh

# Git add + commit
if git rev-parse --is-inside-work-tree &>/dev/null; then
  git add AGENTS.md feature_list.json claude-progress.md init.sh 2>/dev/null || true
  git commit -m "chore: install agent harness files for ${REPO}" 2>/dev/null && \
    echo -e "${GREEN}✓${NC} Committed harness files" || \
    echo -e "${YELLOW}⚠${NC} Nothing to commit (files unchanged or already tracked)"
fi

# Verify init.sh
echo ""
echo -e "${GREEN}=== Verifying init.sh ===${NC}"
source init.sh 2>&1 || echo -e "${YELLOW}⚠ init.sh had warnings — review above${NC}"

echo ""
echo -e "${GREEN}=== Install complete for ${REPO} ===${NC}"
echo "Next: start a Claude Code or OpenClaw session and use the harness prompts."
