#!/usr/bin/env bash
# Slimy Chat — Agent Environment Init
# Run this at the start of every agent session: source init.sh
set -euo pipefail

echo "=== Slimy Chat Init ==="

if [ ! -f "compose.yml" ] || [ ! -f "Revolt.toml" ]; then
  echo "ERROR: Not in slimy-chat root. Run 'cd' to the repo root first."
  exit 1
fi

echo "[1/3] Checking Docker..."
docker --version >/dev/null 2>&1 || { echo "ERROR: Docker not found"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "ERROR: Docker Compose not found"; exit 1; }
echo "  Docker: OK, Compose: OK"

echo "[2/3] Validating compose config..."
docker compose config --quiet 2>/dev/null && echo "  Config: VALID" || echo "WARN: compose.yml has validation issues"

echo "[3/3] Checking service status..."
docker compose ps 2>/dev/null || echo "WARN: Could not get service status"

echo ""
echo "Key commands:"
echo "  docker compose up -d       → Start/restart all services"
echo "  docker compose ps          → Service status"
echo "  docker compose logs -f     → Follow logs"
echo "  docker compose config      → Validate config"
echo ""
echo "=== Init complete. ==="
