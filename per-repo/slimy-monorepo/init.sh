#!/usr/bin/env bash
# SlimyAI Monorepo — Agent Environment Init
# Run this at the start of every agent session: source init.sh
set -euo pipefail

echo "=== SlimyAI Monorepo Init ==="

# 1. Confirm we're in the right directory
if [ ! -f "pnpm-workspace.yaml" ]; then
  echo "ERROR: Not in slimy-monorepo root. Run 'cd' to the repo root first."
  exit 1
fi

# 2. Install dependencies (fast if node_modules exists)
echo "[1/4] Installing dependencies..."
pnpm install --frozen-lockfile 2>/dev/null || pnpm install

# 3. Generate Prisma clients
echo "[2/4] Generating Prisma clients..."
pnpm prisma:generate 2>/dev/null || echo "WARN: Prisma generate failed — check schema"

# 4. Quick lint check (fail fast if codebase is broken)
echo "[3/4] Running quick lint check..."
pnpm lint 2>/dev/null && echo "Lint: PASS" || echo "WARN: Lint issues detected — fix before new work"

# 5. Summary
echo "[4/4] Environment ready."
echo ""
echo "Available commands:"
echo "  pnpm dev:web        → Web app on :3000"
echo "  pnpm dev:admin-api  → Admin API on :3080"
echo "  pnpm dev:admin-ui   → Admin UI on :3081"
echo "  pnpm test:all       → Run all tests"
echo "  pnpm lint           → Lint everything"
echo ""
echo "=== Init complete. Read claude-progress.md and feature_list.json next. ==="
