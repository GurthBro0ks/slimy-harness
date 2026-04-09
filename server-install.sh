#!/usr/bin/env bash
# ============================================================
# SlimyAI Harness — Full Server Install (Repo-Based)
#
# Usage:
#   bash slimy-harness/server-install.sh [--dry-run]
#
# With --dry-run: shows what would be installed/changed, makes no writes.
# Without --dry-run: installs harness from this repo to /home/slimy/
#
# This does:
#   1. Copies server-level harness files from this repo to /home/slimy/
#   2. Finds all slimyai repos on the machine
#   3. Installs per-repo harness files from this repo into each one
#   4. Creates server-state.md from template (never overwrites live)
#   5. Verifies with init.sh
#
# NOTE: This script is staged in slimy-harness git repo. It is NOT yet
# the active installer. Live installation still uses harness-kit/.
# Cutover to this script will happen in a future session.
# ============================================================
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Detect script location (this repo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
KIT="$REPO_ROOT"  # server/ and per-repo/ dirs live under this repo root
HOME_DIR="/home/slimy"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

log() { echo -e "$1"; }
log_skip() { log "  ${YELLOW}⚠${NC}  $1 (skipping)"; }
log_done() { log "  ${GREEN}✓${NC}  $1"; }
log_info() { log "  ~ $1"; }

install_file() {
  local src="$1"; local dst="$2"
  if [[ "$DRY_RUN" == true ]]; then
    log_info "WOULD COPY: $src → $dst"
  else
    if [[ -f "$dst" ]]; then
      log_skip "Already exists: $dst (not overwriting live state)"
    else
      cp "$src" "$dst"
      log_done "Installed: $dst"
    fi
  fi
}

install_template() {
  local src="$1"; local dst="$2"
  if [[ "$DRY_RUN" == true ]]; then
    log_info "WOULD CREATE from template: $dst"
  else
    if [[ -f "$dst" ]]; then
      log_skip "Already exists: $dst (not overwriting live state)"
    else
      cp "$src" "$dst"
      log_done "Created from template: $dst"
    fi
  fi
}

echo ""
log "${GREEN}=== SlimyAI Harness — Server Install ===${NC}"
if [[ "$DRY_RUN" == true ]]; then
  log "${YELLOW}[DRY RUN MODE] No files will be written${NC}"
fi
echo ""

# ---- PHASE 1: Server-level harness (templates, not live state) ----
log "${GREEN}[Phase 1] Server-level harness files${NC}"

SERVER_FILES=("AGENTS.md" "QUALITY_CRITERIA.md" "init.sh")
for f in "${SERVER_FILES[@]}"; do
  src="$KIT/server/$f"
  dst="$HOME_DIR/$f"
  if [[ -f "$src" ]]; then
    install_file "$src" "$dst"
  else
    log_skip "Not found in repo: server/$f"
  fi
done

# Live state files: use TEMPLATES, never overwrite live
for f in "claude-progress.md" "feature_list.json" "server-state.md"; do
  src="$KIT/server/templates/$f"
  dst="$HOME_DIR/$f"
  if [[ -f "$src" ]]; then
    install_template "$src" "$dst"
  else
    log_skip "Template not found: server/templates/$f"
  fi
done

# PROJECT_NARRATIVE.md: only install if missing
PNARR="$KIT/server/templates/PROJECT_NARRATIVE.md"
if [[ -f "$PNARR" ]]; then
  install_template "$PNARR" "$HOME_DIR/PROJECT_NARRATIVE.md"
else
  log_skip "PROJECT_NARRATIVE.md template not found"
fi

chmod +x "$HOME_DIR/init.sh" 2>/dev/null || true
echo ""

# ---- PHASE 2: Find repos ----
log "${GREEN}[Phase 2] Discovering repos...${NC}"

declare -A REPO_PATHS

find_repo() {
  local name="$1"; local marker="$2"
  for dir in "$HOME_DIR/repos/$name" "$HOME_DIR/$name" "$HOME_DIR/projects/$name" "$HOME_DIR/code/$name"; do
    if [[ -d "$dir" ]] && [[ -f "$dir/$marker" ]]; then
      REPO_PATHS["$name"]="$dir"
      log_done "$name → $dir"
      return 0
    fi
  done
  local result
  result=$(find "$HOME_DIR" -maxdepth 4 -name "$marker" -path "*/$name/*" -type f 2>/dev/null | head -1)
  if [[ -n "$result" ]]; then
    local dir
    dir=$(dirname "$result")
    REPO_PATHS["$name"]="$dir"
    log_done "$name → $dir"
    return 0
  fi
  log_skip "$name ($marker) — not found on this machine"
  return 1
}

find_repo "slimy-monorepo" "pnpm-workspace.yaml" || true
find_repo "pm_updown_bot_bundle" "runner.py" || true
find_repo "mission-control" "mission-control.sh" || true
echo ""

# ---- PHASE 3: Install per-repo harness ----
log "${GREEN}[Phase 3] Per-repo harness files${NC}"

install_repo_harness() {
  local name="$1"; local dir="$2"
  local src="$KIT/per-repo/$name"

  if [[ ! -d "$src" ]]; then
    log_skip "No per-repo harness in this repo for: $name"
    return 0
  fi

  log_info "Installing into $dir..."

  if [[ -f "$dir/AGENTS.md" ]]; then
    log_info "AGENTS.md already exists — not overwriting"
  else
    install_file "$src/AGENTS.md" "$dir/AGENTS.md"
  fi

  for f in "feature_list.json" "claude-progress.md" "init.sh"; do
    if [[ -f "$src/$f" ]]; then
      if [[ -f "$dir/$f" ]]; then
        log_skip "$f already exists in $dir (not overwriting live state)"
      else
        install_file "$src/$f" "$dir/$f"
      fi
    fi
  done

  chmod +x "$dir/init.sh" 2>/dev/null || true

  if [[ "$DRY_RUN" == false ]]; then
    if git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
      git -C "$dir" add "AGENTS.md" "feature_list.json" "claude-progress.md" "init.sh" 2>/dev/null || true
      git -C "$dir" commit -m "chore: install agent harness" 2>/dev/null && \
        log_done "Committed" || \
        log_info "Already committed or nothing to commit"
    fi
  else
    log_info "WOULD commit harness files in $dir"
  fi
}

for name in "${!REPO_PATHS[@]}"; do
  install_repo_harness "$name" "${REPO_PATHS[$name]}"
done
echo ""

# ---- PHASE 4: Create server-state.md from discovered paths ----
log "${GREEN}[Phase 4] server-state.md${NC}"

STATE_FILE="$HOME_DIR/server-state.md"
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
OS_INFO=$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "unknown")

STATE_CONTENT=$(cat << EOF
# Server State — SlimyAI

> Update this file whenever you start/stop services, install packages,
> or change server configuration. Agents read this to know what's running.

## Machine Info

- **Hostname:** ${HOSTNAME}
- **OS:** ${OS_INFO}
- **User:** slimy
- **Home:** /home/slimy

## Repo Locations

| Repo | Path | Status |
|------|------|--------|
| slimy-monorepo | ${REPO_PATHS[slimy-monorepo]:-not found} | $([ -n "${REPO_PATHS[slimy-monorepo]:-}" ] && echo "installed" || echo "missing") |
| pm_updown_bot_bundle | ${REPO_PATHS[pm_updown_bot_bundle]:-not found} | $([ -n "${REPO_PATHS[pm_updown_bot_bundle]:-}" ] && echo "installed" || echo "missing") |
| mission-control | ${REPO_PATHS[mission-control]:-not found} | $([ -n "${REPO_PATHS[mission-control]:-}" ] && echo "installed" || echo "missing") |

## Running Services

| Service | Port | PID | Status | Started By |
|---------|------|-----|--------|------------|
| (check with: ss -tlnp or docker ps) | | | | |

## Installed System Packages (agent-installed)

| Package | Date | Why |
|---------|------|-----|
| (none yet) | | |

## Cron Jobs / Scheduled Tasks

| Schedule | Command | Purpose |
|----------|---------|---------|
| (none yet) | | |
EOF
)

if [[ "$DRY_RUN" == true ]]; then
  log_info "WOULD CREATE/UPDATE: $STATE_FILE with discovered repo paths"
else
  if [[ -f "$STATE_FILE" ]]; then
    log_skip "server-state.md already exists — not overwriting live state"
  else
    echo "$STATE_CONTENT" > "$STATE_FILE"
    log_done "Created server-state.md"
  fi
fi
echo ""

# ---- PHASE 5: Verify ----
if [[ "$DRY_RUN" == false ]]; then
  log "${GREEN}[Phase 5] Verifying installation...${NC}"
  cd "$HOME_DIR"
  if [[ -f "init.sh" ]]; then
    source init.sh 2>&1 || log "${YELLOW}init.sh had warnings${NC}"
  fi
  echo ""
fi

log "${GREEN}=== Install complete ===${NC}"
if [[ "$DRY_RUN" == true ]]; then
  log "${YELLOW}[DRY RUN] No files were written. Run without --dry-run to install.${NC}"
fi
echo ""
echo "What to do next:"
echo "  1. Review this repo: https://github.com/GurthBro0ks/slimy-harness"
echo "  2. Run without --dry-run to install on a fresh system"
echo "  3. After live cutover, harness will auto-update via git pull"
