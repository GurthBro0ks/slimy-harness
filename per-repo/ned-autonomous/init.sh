#!/usr/bin/env bash
# Ned Autonomous — Agent Environment Init
# Run this at the start of every agent session: source init.sh
set -euo pipefail

echo "=== Ned Autonomous Init ==="

if [ ! -d "scripts" ] || [ ! -d "config" ]; then
  echo "ERROR: Not in ned-autonomous root. Run 'cd' to the repo root first."
  exit 1
fi

echo "[1/3] Checking environment..."
python3 --version >/dev/null 2>&1 || { echo "ERROR: Python3 not found"; exit 1; }
git --version >/dev/null 2>&1 || { echo "ERROR: git not found"; exit 1; }
echo "  python3: OK, git: OK"

echo "[2/3] Checking core scripts..."
for script in scripts/agent-loop.py scripts/task-router.py scripts/agent-health.py; do
  if [ -f "$script" ]; then
    python3 -m py_compile "$script" 2>/dev/null && echo "  $script: OK" || echo "WARN: $script has syntax errors"
  else
    echo "  $script: MISSING"
  fi
done

echo "[3/3] Environment ready."
echo ""
echo "NOTE: This repo is STALE (last active ~Apr 7). No running services."
echo ""
echo "Key scripts:"
echo "  scripts/agent-loop.py       → Main orchestrator loop"
echo "  scripts/task-router.py      → Task routing"
echo "  scripts/federation-router.py → NUC federation"
echo ""
echo "=== Init complete. ==="
