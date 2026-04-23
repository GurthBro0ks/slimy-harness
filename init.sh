#!/usr/bin/env bash
# Slimy Harness — Agent Environment Init
# Run this at the start of every agent session: source init.sh
set -euo pipefail

echo "=== Slimy Harness Init ==="

if [ ! -f "server-install.sh" ] || [ ! -d "per-repo" ]; then
  echo "ERROR: Not in slimy-harness root. Run 'cd' to the repo root first."
  exit 1
fi

echo "[1/3] Checking required tools..."
git --version >/dev/null 2>&1 || { echo "ERROR: git not found"; exit 1; }
bash --version >/dev/null 2>&1 || { echo "ERROR: bash not found"; exit 1; }
echo "  git: OK, bash: OK"

echo "[2/3] Running harness validation..."
if bash scripts/validate-harness.sh; then
  echo "  Validation: PASS"
else
  echo "WARN: Validation has issues — check before making changes"
fi

echo "[3/3] Environment ready."
echo ""
echo "Key commands:"
echo "  bash scripts/validate-harness.sh    → Validate harness integrity"
echo "  bash server-install.sh --dry-run    → Preview deployment"
echo "  bash server-install.sh --commit     → Deploy (use with caution)"
echo ""
echo "=== Init complete. Read README.md next. ==="
