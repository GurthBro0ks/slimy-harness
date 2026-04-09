#!/usr/bin/env bash
# ============================================================
# SlimyAI Harness — Full Server Install (Repo-Based)
#
# Usage:
#   bash slimy-harness/server-install.sh [--dry-run] [--commit]
#
# Flags:
#   --dry-run  Preview what would be installed. No files written.
#   --commit   After installing, git commit in each target repo.
#              Without this flag: install only, never auto-commits.
#
# This does:
#   1. Installs server-level harness files (AGENTS.md, init.sh, etc.)
#      from this repo to /home/slimy/ — ONLY for files that don't exist there
#   2. Installs per-repo harness from per-repo/ into any found matching repos
#      — only for files that don't already exist in the target repo
#   3. Creates server-state.md from discovered paths — only if it doesn't exist
#   4. Runs init.sh to verify (unless --dry-run)
#
# NOTE: Live state files (claude-progress.md, feature_list.json,
# server-state.md) are NEVER overwritten — only created from templates
# when missing.
# ============================================================
set -euo pipefail

DRY_RUN=false
DO_COMMIT=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=true ;;
    --commit)   DO_COMMIT=true ;;
  esac
done

# Detect script location (this repo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
KIT="$REPO_ROOT"
HOME_DIR="/home/slimy"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

log()      { echo -e "$1"; }
log_done() { log "  ${GREEN}✓${NC}  $1"; }
log_skip() { log "  ${YELLOW}⚠${NC}  $1"; }
log_info() { log "  ~ $1"; }

# ---------------------------------------------------------------------------
# install_file SRC DST
#   Copy SRC to DST if DST does not already exist.
#   Dry-run: print WOULD SKIP if exists, WOULD COPY if missing.
#   Never any writes during dry-run.
# ---------------------------------------------------------------------------
install_file() {
  local src="$1"; local dst="$2"
  if [[ -f "$dst" ]]; then
    log_skip "already exists — $dst"
  elif [[ -f "$src" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      log_info "WOULD COPY: $src → $dst"
    else
      cp "$src" "$dst"
      log_done "installed: $dst"
    fi
  else
    log_skip "not found in repo: $src"
  fi
}

# ---------------------------------------------------------------------------
# install_template SRC DST
#   Copy SRC to DST if DST does not already exist.
#   Used for live-state template files (claude-progress, feature_list, etc.)
# ---------------------------------------------------------------------------
install_template() {
  local src="$1"; local dst="$2"
  if [[ -f "$dst" ]]; then
    log_skip "already exists — $dst"
  elif [[ -f "$src" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      log_info "WOULD CREATE from template: $dst"
    else
      cp "$src" "$dst"
      log_done "created from template: $dst"
    fi
  else
    log_skip "template not found: $src"
  fi
}

# ---------------------------------------------------------------------------
# try_chmod FILE
#   Sets executable bit. No-op during dry-run.
# ---------------------------------------------------------------------------
try_chmod() {
  local file="$1"
  [[ "$DRY_RUN" == true ]] && return 0
  chmod +x "$file" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# try_git_commit DIR MSG
#   Git add + commit in DIR if it is a git repo and --commit was passed.
# ---------------------------------------------------------------------------
try_git_commit() {
  local dir="$1"; local msg="$2"
  [[ "$DO_COMMIT" != true ]] && return 0
  [[ "$DRY_RUN" == true ]] && return 0
  git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null || return 0
  git -C "$dir" add "AGENTS.md" "feature_list.json" "claude-progress.md" "init.sh" 2>/dev/null || true
  git -C "$dir" commit -m "$msg" &>/dev/null && log_done "committed in $dir" || log_skip "nothing to commit in $dir"
}

# ---------------------------------------------------------------------------
echo ""
log "${GREEN}=== SlimyAI Harness — Server Install ===${NC}"
[[ "$DRY_RUN" == true ]] && log "${YELLOW}[DRY RUN MODE] No files will be written${NC}"
[[ "$DRY_RUN" == false && "$DO_COMMIT" == false ]] && log "${YELLOW}[Install mode — no auto-commit. Pass --commit to also commit.${NC}"
[[ "$DRY_RUN" == false && "$DO_COMMIT" == true ]] && log "${GREEN}[Install + commit mode]${NC}"
echo ""

# ---- PHASE 1: Server-level harness files ----
log "${GREEN}[Phase 1] Server-level harness files${NC}"

# Core harness files — only installed if missing at destination
for f in "AGENTS.md" "QUALITY_CRITERIA.md" "init.sh"; do
  install_file "$KIT/server/$f" "$HOME_DIR/$f"
done

# Live-state template files — only installed if missing at destination
for f in "claude-progress.md" "feature_list.json" "server-state.md"; do
  install_template "$KIT/server/templates/$f" "$HOME_DIR/$f"
done

# PROJECT_NARRATIVE.md — only installed if missing
install_template "$KIT/server/templates/PROJECT_NARRATIVE.md" "$HOME_DIR/PROJECT_NARRATIVE.md"

# chmod init.sh (only if not dry-run and file was installed or already exists)
[[ "$DRY_RUN" == false ]] && try_chmod "$HOME_DIR/init.sh"
echo ""

# ---- PHASE 2: Discover repos and per-repo harness ----
log "${GREEN}[Phase 2] Discovering repos and per-repo harness${NC}"

# Build list of repos we have harness templates for
declare -A HARNESS_TEMPLATES
for dir in "$KIT/per-repo"/*/; do
  [[ -d "$dir" ]] || continue
  name=$(basename "$dir")
  HARNESS_TEMPLATES["$name"]="$dir"
done

# ---------------------------------------------------------------------------
# canonicalize_path PATH
#   Resolves symlinks and returns the real path. Skips tool/editor dirs.
#   Returns empty string (and prints AMBIGUOUS_REPO: if duplicate basenames found.
# ---------------------------------------------------------------------------
declare -A CANONICAL_PATHS   # basename → canonical path
declare -A SEEN_BASENAME     # basename → 1 (to detect duplicates)
declare -A AMBIGUOUS_REPOS   # basename → 1 (if multiple non-skipped candidates)

# Skip entire subtrees that are editor/agent/tooling directories
SKIP_DIRS_REGEX="/\.openclaw/|/\.claude/|/\.cache/|/\.codex/|/\.qoder-server/"

# Discover all git repos under $HOME_DIR
RAW_REPOS=$(find "$HOME_DIR" -maxdepth 4 -name ".git" -type d 2>/dev/null | sed 's/\/.git$//' | grep -v "node_modules" | sort)

REPO_COUNT=$(echo "$RAW_REPOS" | wc -l)
log_info "Found $REPO_COUNT raw git repos under $HOME_DIR"

# First pass: canonicalize each path, build basename map
for repo_path in $RAW_REPOS; do
  # Skip tool/editor/mirror directories
  if [[ "$repo_path" =~ $SKIP_DIRS_REGEX ]]; then
    log_skip "tooling path skipped: $repo_path"
    continue
  fi

  # Resolve symlinks to get canonical path
  real_path=$(realpath "$repo_path" 2>/dev/null || echo "$repo_path")
  name=$(basename "$real_path")

  if [[ -n "${SEEN_BASENAME[$name]:-}" ]]; then
    # Duplicate basename found
    AMBIGUOUS_REPOS["$name"]=1
    log "${RED}AMBIGUOUS_REPO:${NC} $name (duplicate basename — candidates: ${CANONICAL_PATHS[$name]:-}, $real_path)"
  else
    SEEN_BASENAME[$name]=1
    CANONICAL_PATHS[$name]="$real_path"
  fi
done

echo ""

# Second pass: install harness for unambiguous repos with matching templates
declare -A INSTALLED_HARNESS
for name in "${!CANONICAL_PATHS[@]}"; do
  if [[ -n "${AMBIGUOUS_REPOS[$name]:-}" ]]; then
    log "${RED}AMBIGUOUS_REPO:${NC} $name — skipping all candidates (fail-closed)"
    continue
  fi

  template_dir="${HARNESS_TEMPLATES[$name]:-}"
  if [[ -z "$template_dir" ]]; then
    log_skip "no harness template for: $name"
    continue
  fi

  repo_path="${CANONICAL_PATHS[$name]}"
  log "${GREEN}  Installing harness for:${NC} $name → $repo_path"

  # Per-file install — respect "only if missing" rule for each file
  install_file "$template_dir/AGENTS.md"         "$repo_path/AGENTS.md"
  install_file "$template_dir/init.sh"           "$repo_path/init.sh"
  install_file "$template_dir/feature_list.json" "$repo_path/feature_list.json"
  install_file "$template_dir/claude-progress.md" "$repo_path/claude-progress.md"

  # chmod init.sh if installed (only in real run)
  [[ "$DRY_RUN" == false && -f "$repo_path/init.sh" ]] && try_chmod "$repo_path/init.sh"

  # Optionally commit
  try_git_commit "$repo_path" "chore: install agent harness"

  INSTALLED_HARNESS["$name"]="$repo_path"
done

echo ""

# ---- PHASE 3: Create server-state.md from discovered paths ----
log "${GREEN}[Phase 3] server-state.md${NC}"

STATE_FILE="$HOME_DIR/server-state.md"
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
OS_INFO=$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "unknown")

# Build repo table rows from actual INSTALLED_HARNESS paths
REPO_ROWS=""
for name in "${!INSTALLED_HARNESS[@]}"; do
  path="${INSTALLED_HARNESS[$name]}"
  REPO_ROWS="${REPO_ROWS}| $name | ${path} | installed |"$'\n'
done

# If no harness installed, show a placeholder row
if [[ -z "$REPO_ROWS" ]]; then
  REPO_ROWS="| (no repos with harness templates found) | — | — |"$'\n'
fi

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

> Populated by server-install.sh from discovered repos with harness templates.

| Repo | Path | Status |
|------|------|--------|
${REPO_ROWS}| (repo) | (path) | unknown |

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

if [[ -f "$STATE_FILE" ]]; then
  log_skip "already exists — $STATE_FILE"
else
  if [[ "$DRY_RUN" == true ]]; then
    log_info "WOULD CREATE: $STATE_FILE with discovered repo paths"
  else
    echo "$STATE_CONTENT" > "$STATE_FILE"
    log_done "created: $STATE_FILE"
  fi
fi
echo ""

# ---- PHASE 4: Verify ----
if [[ "$DRY_RUN" == false ]]; then
  log "${GREEN}[Phase 4] Verifying installation...${NC}"
  cd "$HOME_DIR"
  if [[ -f "init.sh" ]]; then
    source init.sh 2>&1 || log "${YELLOW}init.sh had warnings${NC}"
  fi
  echo ""
fi

log "${GREEN}=== Install complete ===${NC}"
[[ "$DRY_RUN" == true ]] && log "${YELLOW}[DRY RUN] No files were written.${NC}"
echo ""
echo "Next: Review this repo at https://github.com/GurthBro0ks/slimy-harness"
