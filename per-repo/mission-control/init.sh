#!/usr/bin/env bash
# Mission Control — Agent Environment Init
# Run this at the start of every agent session: source init.sh
set -euo pipefail

echo "=== Mission Control Init ==="

# 1. Confirm we're in the right directory
if [ ! -f "package.json" ] || ! grep -q '"mission-control"' package.json 2>/dev/null; then
  echo "ERROR: Not in mission-control root. Run 'cd' to the repo root first."
  exit 1
fi

# 2. Check Node.js
echo "[1/4] Checking Node.js environment..."
node --version || { echo "ERROR: Node.js not found"; exit 1; }
pnpm --version 2>/dev/null || { echo "WARN: pnpm not found — trying npm"; }

# 3. Install dependencies
echo "[2/4] Installing dependencies..."
if [ -f "pnpm-lock.yaml" ]; then
  pnpm install --frozen-lockfile 2>/dev/null || pnpm install
elif [ -f "package-lock.json" ]; then
  npm install 2>/dev/null || echo "WARN: npm install had issues"
else
  echo "No lock file found — skipping lockfile-based install"
fi

# 4. Quick lint check (fail fast if codebase is broken)
echo "[3/4] Running quick lint check..."
pnpm lint 2>/dev/null && echo "Lint: PASS" || echo "WARN: Lint issues detected — fix before new work"

# 5. Summary
echo "[4/4] Environment ready."
echo ""
echo "Available commands:"
echo "  pnpm dev        → Dev server on :3838"
echo "  pnpm build      → Production build"
echo "  pnpm start      → Start production server"
echo "  pnpm lint       → Lint everything"
echo ""
echo "=== Init complete. Read claude-progress.md and feature_list.json next. ==="
