#!/usr/bin/env bash
# Ned Clawd — Agent Environment Init
# Run this at the start of every agent session: source init.sh
set -euo pipefail

echo "=== Ned Clawd Init ==="

if [ ! -f "SOUL.md" ] || [ ! -d "ops" ]; then
  echo "ERROR: Not in ned-clawd root. Run 'cd' to the repo root first."
  exit 1
fi

echo "[1/3] Checking environment..."
python3 --version >/dev/null 2>&1 || echo "WARN: Python3 not found"
git --version >/dev/null 2>&1 || { echo "ERROR: git not found"; exit 1; }
echo "  python3: OK, git: OK"

echo "[2/3] Checking ops databases..."
for db in ops/ops.db ops/decisions.db ops/triggers.db; do
  if [ -f "$db" ]; then
    echo "  $db: OK ($(stat -f%z "$db" 2>/dev/null || stat -c%s "$db" 2>/dev/null) bytes)"
  else
    echo "  $db: MISSING"
  fi
done

echo "[3/3] Environment ready."
echo ""
echo "Key directories:"
echo "  skills/    → Agent skills"
echo "  tools/     → Utility tools"
echo "  ops/       → Operational databases"
echo "  tasks/     → Task board"
echo "  actionbook/ → Actionbook sub-repo"
echo ""
echo "=== Init complete. Read in-repo AGENTS.md next. ==="
