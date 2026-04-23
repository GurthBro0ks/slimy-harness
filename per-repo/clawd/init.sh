#!/usr/bin/env bash
# Clawd — Agent Environment Init
# Run this at the start of every agent session: source init.sh
set -euo pipefail

echo "=== Clawd Init ==="

if [ ! -f "SOUL.md" ] || [ ! -d "agents" ]; then
  echo "ERROR: Not in clawd root. Run 'cd' to the repo root first."
  exit 1
fi

echo "[1/3] Checking environment..."
python3 --version >/dev/null 2>&1 || echo "WARN: Python3 not found"
git --version >/dev/null 2>&1 || { echo "ERROR: git not found"; exit 1; }
echo "  python3: OK, git: OK"

echo "[2/3] Checking repo health..."
git status --porcelain | head -5
echo "  (uncommitted changes shown above if any)"

echo "[3/3] Environment ready."
echo ""
echo "Key directories:"
echo "  agents/    → Agent definitions"
echo "  skills/    → Skill modules"
echo "  config/    → Configuration (agents.yaml)"
echo "  scripts/   → Utility scripts"
echo ""
echo "=== Init complete. Read in-repo AGENTS.md next. ==="
