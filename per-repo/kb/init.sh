#!/usr/bin/env bash
# Slimy KB — Agent Environment Init
# Run this at the start of every agent session: source init.sh
set -euo pipefail

echo "=== Slimy KB Init ==="

if [ ! -f "KB_AGENTS.md" ] || [ ! -d "tools" ]; then
  echo "ERROR: Not in slimy-kb root. Run 'cd' to the repo root first."
  exit 1
fi

echo "[1/4] Checking tools..."
git --version >/dev/null 2>&1 || { echo "ERROR: git not found"; exit 1; }
echo "  git: OK"

echo "[2/4] Pulling latest from remote..."
bash tools/kb-sync.sh pull 2>/dev/null || echo "WARN: kb-sync pull had issues"

echo "[3/4] Running KB lint..."
bash tools/kb-lint.sh 2>/dev/null && echo "  Lint: PASS" || echo "WARN: KB lint issues detected"

echo "[4/4] Environment ready."
echo ""
echo "Key commands:"
echo "  bash tools/kb-sync.sh pull     → Sync from remote"
echo "  bash tools/kb-sync.sh push     → Push to remote"
echo "  bash tools/kb-search.sh 'q'    → Search wiki"
echo "  bash tools/kb-write.sh <path>  → Write new content"
echo "  bash tools/kb-lint.sh          → Validate KB"
echo ""
echo "=== Init complete. Read KB_AGENTS.md next. ==="
