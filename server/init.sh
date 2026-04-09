#!/usr/bin/env bash
# SlimyAI Server — Agent Environment Init
# Discovers all repos dynamically — no hardcoded paths
set -euo pipefail

echo "=== SlimyAI Server Init ==="

echo "[1/5] Purging stale Python bytecode..."
find /home/slimy -name "*.pyc" -delete 2>/dev/null || true
find /home/slimy -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
echo "  Done."

echo "[2/5] Discovering repos..."
# Skip tool/editor/mirror directories — must match server-install.sh skip list
SKIP_DIRS_REGEX='/\.openclaw/|/\.claude/|/\.cache/|/\.codex/|/\.qoder-server/'
REPOS=$(find /home/slimy -maxdepth 4 -name ".git" -type d 2>/dev/null \
  | sed 's/\/.git$//' \
  | grep -v "node_modules" \
  | grep -v ".OLD" \
  | while read -r repo; do
      # Skip tooling/editor paths (must match server-install.sh)
      if [[ "$repo" =~ $SKIP_DIRS_REGEX ]]; then
        continue
      fi
      # Canonicalize path (resolve symlinks, normalize)
      realpath "$repo" 2>/dev/null || echo "$repo"
    done \
  | sort)
REPO_COUNT=$(echo "$REPOS" | wc -l)
echo "  Found $REPO_COUNT repos"

while IFS= read -r repo; do
  name=$(basename "$repo")
  branch=$(git -C "$repo" branch --show-current 2>/dev/null || echo "?")
  dirty=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l)
  echo "  ✓ $name → $repo (branch: $branch, uncommitted: $dirty)"
  # Export as env vars for convenience (spaces/hyphens replaced with underscores)
  varname=$(echo "$name" | tr '-' '_' | tr '.' '_')
  export "REPO_$varname=$repo"
done <<< "$REPOS"

echo "[3/5] Checking system tools..."
for cmd in git node python3 pnpm docker; do
  command -v $cmd &>/dev/null && echo "  ✓ $cmd" || echo "  ✗ $cmd not found"
done

echo "[4/5] Checking services..."
docker ps --format "  ✓ docker: {{.Names}}" 2>/dev/null | head -5 || echo "  ~ docker not running"
pm2 list 2>/dev/null | grep -E "online|errored" | head -5 || echo "  ~ pm2 not running"

echo "[5/5] Server overview"
echo "  Harness: /home/slimy/{AGENTS.md, feature_list.json, claude-progress.md, server-state.md}"
echo "  To work on a repo: cd \$REPO_<name> && source init.sh"
echo "=== Init complete ==="
