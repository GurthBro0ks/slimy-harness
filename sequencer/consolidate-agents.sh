#!/usr/bin/env bash
# consolidate-agents.sh — human-facing review tool for AGENTS.md proposals
#                       and SkillOpt failed-approach review.
#
# SkillOpt intelligence layer: epoch-wise consolidation of bounded skill
# updates. This is a HUMAN tool — it does NOT run in the auto-sequence
# loop.
#
# Usage:
#   bash consolidate-agents.sh              # rank and print proposals
#   bash consolidate-agents.sh --apply N    # apply proposal N to AGENTS.md
#   bash consolidate-agents.sh --dismiss N  # dismiss proposal N
#   bash consolidate-agents.sh --help       # usage
#
# Proposal file: /home/slimy/proposed-agents-edits.json
# Failed-approaches file: /home/slimy/failed-approaches.json
# Last-consolidation marker: /home/slimy/.last-consolidation
# Session reports: ~/kb/raw/sessions/  (or ~/slimy-kb/raw/sessions/)
#
# Edits ALWAYS land inside the PROTECTED_HARNESS_SECTION block. The Core
# Agent Discipline section and everything above is out of scope.
set -euo pipefail

PROPOSALS_FILE="/home/slimy/proposed-agents-edits.json"
FAILED_APPROACHES="/home/slimy/failed-approaches.json"
AGENTS_FILE="/home/slimy/AGENTS.md"
LAST_CONSOLIDATION="/home/slimy/.last-consolidation"
SESSIONS_DIR_PRIMARY="/home/slimy/kb/raw/sessions"
SESSIONS_DIR_SECONDARY="/home/slimy/slimy-kb/raw/sessions"

log() { echo "[$(date -Iseconds)] [consolidate] $*"; }
err() { echo "[$(date -Iseconds)] [consolidate] ERROR: $*" >&2; }

usage() {
  cat << 'USAGE'
consolidate-agents.sh — SkillOpt intelligence layer consolidator

Usage:
  bash consolidate-agents.sh              rank proposals, show summary
  bash consolidate-agents.sh --apply N    apply proposal N to AGENTS.md (protected section)
  bash consolidate-agents.sh --dismiss N  dismiss proposal N
  bash consolidate-agents.sh --help       this help

Edits are restricted to the PROTECTED_HARNESS_SECTION in /home/slimy/AGENTS.md.
The Core Agent Discipline section and content above it is OUT OF SCOPE.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

# Validate input files
if [ ! -f "$PROPOSALS_FILE" ]; then
  err "$PROPOSALS_FILE not found. Run a session first to generate proposals."
  exit 1
fi
if [ ! -f "$AGENTS_FILE" ]; then
  err "$AGENTS_FILE not found."
  exit 1
fi

# Find sessions directory
SESSIONS_DIR=""
if [ -d "$SESSIONS_DIR_PRIMARY" ]; then
  SESSIONS_DIR="$SESSIONS_DIR_PRIMARY"
elif [ -d "$SESSIONS_DIR_SECONDARY" ]; then
  SESSIONS_DIR="$SESSIONS_DIR_SECONDARY"
fi

# Find protected section markers in AGENTS.md
START_MARKER="<!-- PROTECTED_HARNESS_SECTION_START -->"
END_MARKER="<!-- PROTECTED_HARNESS_SECTION_END -->"

if ! grep -qF "$START_MARKER" "$AGENTS_FILE" || ! grep -qF "$END_MARKER" "$AGENTS_FILE"; then
  err "AGENTS.md does not contain PROTECTED_HARNESS_SECTION markers."
  err "Run the SkillOpt install step to add them, or edit AGENTS.md manually."
  exit 1
fi

# ---------------------------------------------------------------------------
# Subcommand: --apply N
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--apply" ]; then
  APPLY_N="${2:-}"
  if [ -z "$APPLY_N" ]; then
    err "--apply requires a proposal number"
    usage
    exit 1
  fi

  log "Applying proposal #$APPLY_N"

  python3 << PYEOF
import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone

proposals_path = "$PROPOSALS_FILE"
agents_path = "$AGENTS_FILE"
start_marker = "$START_MARKER"
end_marker = "$END_MARKER"
last_consolidation = "$LAST_CONSOLIDATION"
n = int("$APPLY_N")

with open(proposals_path) as f:
    data = json.load(f)

proposals = data.get("proposals", [])
if n < 1 or n > len(proposals):
    print(f"[consolidate] ERROR: proposal #{n} not found (have {len(proposals)} active)", file=sys.stderr)
    sys.exit(1)

proposal = proposals[n - 1]
op = proposal.get("op")
target = proposal.get("target", "")
content = proposal.get("content", "")

with open(agents_path) as f:
    agents_text = f.read()

# Find protected section bounds
start_idx = agents_text.find(start_marker)
end_idx = agents_text.find(end_marker)
if start_idx < 0 or end_idx < 0 or end_idx <= start_idx:
    print("[consolidate] ERROR: PROTECTED_HARNESS_SECTION markers not in order", file=sys.stderr)
    sys.exit(1)

# Body of the protected section (between markers, exclusive)
protected_body_start = start_idx + len(start_marker)
# advance past the newline if present
if protected_body_start < len(agents_text) and agents_text[protected_body_start] == "\n":
    protected_body_start += 1
# protected_body is the content between the START marker line and the END marker line,
# NOT including the END marker line itself (which is preserved by the slice).
protected_body = agents_text[protected_body_start:end_idx]

new_protected = protected_body
applied_diff = ""

if op == "append":
    new_protected = protected_body.rstrip("\n") + "\n\n" + content.lstrip("\n")
    if not new_protected.endswith("\n"):
        new_protected += "\n"
    applied_diff = f"APPEND to end of protected section:\n  + {content[:200]}{'...' if len(content) > 200 else ''}"
elif op == "insert_after":
    if not target:
        print("[consolidate] ERROR: insert_after requires 'target' (heading name)", file=sys.stderr)
        sys.exit(1)
    # Find target heading inside protected body
    heading_pattern = re.compile(r"(^##?\s+.*" + re.escape(target) + r".*$)", re.MULTILINE)
    m = heading_pattern.search(protected_body)
    if not m:
        # Fall back to substring search on the heading line
        lines = protected_body.splitlines(keepends=True)
        new_lines = []
        inserted = False
        for line in lines:
            new_lines.append(line)
            if not inserted and target in line:
                new_lines.append("\n" + content.rstrip("\n") + "\n")
                inserted = True
        if not inserted:
            print(f"[consolidate] ERROR: target '{target}' not found in protected section", file=sys.stderr)
            sys.exit(1)
        new_protected = "".join(new_lines)
    else:
        insert_pos = m.end()
        new_protected = (
            protected_body[:insert_pos]
            + "\n" + content.rstrip("\n") + "\n"
            + protected_body[insert_pos:]
        )
    applied_diff = f"INSERT_AFTER '{target}':\n  + {content[:200]}{'...' if len(content) > 200 else ''}"
elif op == "replace":
    if not target:
        print("[consolidate] ERROR: replace requires 'target' (text to replace)", file=sys.stderr)
        sys.exit(1)
    if target not in protected_body:
        print(f"[consolidate] ERROR: replace target not found in protected section", file=sys.stderr)
        print(f"[consolidate] Target was: {target[:200]}", file=sys.stderr)
        sys.exit(1)
    new_protected = protected_body.replace(target, content, 1)
    applied_diff = f"REPLACE:\n  - {target[:200]}{'...' if len(target) > 200 else ''}\n  + {content[:200]}{'...' if len(content) > 200 else ''}"
elif op == "delete":
    if not target:
        print("[consolidate] ERROR: delete requires 'target' (text to delete)", file=sys.stderr)
        sys.exit(1)
    if target not in protected_body:
        print(f"[consolidate] ERROR: delete target not found in protected section", file=sys.stderr)
        sys.exit(1)
    new_protected = protected_body.replace(target, "", 1)
    applied_diff = f"DELETE:\n  - {target[:200]}{'...' if len(target) > 200 else ''}"
else:
    print(f"[consolidate] ERROR: unknown op '{op}'", file=sys.stderr)
    sys.exit(1)

# Reassemble AGENTS.md
new_agents = agents_text[:protected_body_start] + new_protected + agents_text[end_idx:]

# Backup before write
backup_path = agents_path + ".bak." + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
shutil.copy2(agents_path, backup_path)
print(f"[consolidate] AGENTS.md backed up to {backup_path}")

# Atomic write
tmp = agents_path + ".tmp"
with open(tmp, "w") as f:
    f.write(new_agents)
os.replace(tmp, agents_path)
print(f"[consolidate] AGENTS.md updated")

# Move proposal from proposals to applied
applied_entry = dict(proposal)
applied_entry["applied_at"] = datetime.now(timezone.utc).isoformat()
applied_entry["applied_proposal_number"] = n
data.setdefault("applied", []).append(applied_entry)
del data["proposals"][n - 1]

# Atomic write proposals
tmp_p = proposals_path + ".tmp"
with open(tmp_p, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp_p, proposals_path)
print(f"[consolidate] Moved proposal #{n} to 'applied'")

# Update last-consolidation
with open(last_consolidation, "w") as f:
    f.write(datetime.now(timezone.utc).isoformat() + "\n")
print(f"[consolidate] Updated {last_consolidation}")

# Print diff
print()
print("=" * 70)
print(applied_diff)
print("=" * 70)
PYEOF

  exit 0
fi

# ---------------------------------------------------------------------------
# Subcommand: --dismiss N
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--dismiss" ]; then
  DISMISS_N="${2:-}"
  if [ -z "$DISMISS_N" ]; then
    err "--dismiss requires a proposal number"
    usage
    exit 1
  fi

  log "Dismissing proposal #$DISMISS_N"

  python3 << PYEOF
import json
import os
import sys
from datetime import datetime, timezone

proposals_path = "$PROPOSALS_FILE"
n = int("$DISMISS_N")

with open(proposals_path) as f:
    data = json.load(f)

proposals = data.get("proposals", [])
if n < 1 or n > len(proposals):
    print(f"[consolidate] ERROR: proposal #{n} not found (have {len(proposals)} active)", file=sys.stderr)
    sys.exit(1)

proposal = proposals[n - 1]
dismissed_entry = dict(proposal)
dismissed_entry["dismissed_at"] = datetime.now(timezone.utc).isoformat()
dismissed_entry["dismissed_proposal_number"] = n
data.setdefault("dismissed", []).append(dismissed_entry)
del data["proposals"][n - 1]

tmp = proposals_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, proposals_path)

print(f"[consolidate] Moved proposal #{n} to 'dismissed'")
print(f"[consolidate] Rationale was: {proposal.get('rationale', '(none)')}")
PYEOF

  exit 0
fi

# ---------------------------------------------------------------------------
# Default: rank and summarize
# ---------------------------------------------------------------------------
log "Ranking proposals and summarizing"

python3 << PYEOF
import json
import os
import re
from datetime import datetime, timezone
from collections import defaultdict, Counter

proposals_path = "$PROPOSALS_FILE"
failed_path = "$FAILED_APPROACHES"
last_consolidation = "$LAST_CONSOLIDATION"
sessions_dir = "$SESSIONS_DIR"

with open(proposals_path) as f:
    data = json.load(f)

proposals = data.get("proposals", [])
applied = data.get("applied", [])
dismissed = data.get("dismissed", [])

# Load failed-approaches (last 20)
failed_approaches = []
if os.path.isfile(failed_path):
    try:
        with open(failed_path) as f:
            fa = json.load(f)
        failed_approaches = fa.get("entries", [])
    except Exception:
        failed_approaches = []
failed_approaches_recent = failed_approaches[-20:]
fa_by_feature = Counter(e.get("feature_id") for e in failed_approaches_recent)

# Last consolidation timestamp
last_ts = None
if os.path.isfile(last_consolidation):
    try:
        with open(last_consolidation) as f:
            last_ts = f.read().strip()
    except Exception:
        pass

# Session reports since last consolidation
session_reports = []
if sessions_dir and os.path.isdir(sessions_dir):
    files = sorted(
        [os.path.join(sessions_dir, fn) for fn in os.listdir(sessions_dir) if fn.endswith(".json")],
        key=os.path.getmtime,
        reverse=True,
    )
    files = files[:20]
    for fp in files:
        try:
            with open(fp) as f:
                rep = json.load(f)
            rep["_file"] = os.path.basename(fp)
            session_reports.append(rep)
        except Exception:
            continue

# Filter to sessions since last consolidation
def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None

last_dt = parse_ts(last_ts) if last_ts else None
if last_dt:
    since_sessions = [r for r in session_reports if (parse_ts(r.get("timestamp", "")) or datetime.min.replace(tzinfo=timezone.utc)) > last_dt]
else:
    since_sessions = session_reports
passed_count = sum(1 for r in since_sessions if r.get("status") == "completed" and r.get("tests", {}).get("passed"))
failed_count = sum(1 for r in since_sessions if r.get("status") in ("failed", "partial") or (r.get("status") == "completed" and not r.get("tests", {}).get("passed")))
blocked_count = sum(1 for r in since_sessions if r.get("status") == "blocked")

# Group proposals by similarity (Jaccard word overlap > 0.5)
def word_set(s):
    return set(re.findall(r"\w+", s.lower()))

def jaccard(a, b):
    wa, wb = word_set(a), word_set(b)
    if not wa or not wb:
        return 0.0
    return len(wa & wb) / len(wa | wb)

groups = []  # list of {"indices": [i], "proposals": [p]}
for i, p in enumerate(proposals):
    placed = False
    target = (p.get("content", "") + " " + p.get("rationale", ""))
    for g in groups:
        g_target = " ".join(
            (gp.get("content", "") + " " + gp.get("rationale", "")) for gp in g["proposals"]
        )
        if jaccard(target, g_target) > 0.5:
            g["indices"].append(i)
            g["proposals"].append(p)
            placed = True
            break
    if not placed:
        groups.append({"indices": [i], "proposals": [p]})

# Print header
print()
print("=" * 70)
print("SkillOpt Intelligence Layer — Consolidation Report")
print("=" * 70)
print(f"Last consolidation: {last_ts or '(never)'}")
print(f"Sessions since last consolidation: {len(since_sessions)} (passed={passed_count}, failed={failed_count}, blocked={blocked_count})")
print(f"Failed approaches logged (last 20): {len(failed_approaches_recent)}")
for fid, cnt in fa_by_feature.most_common(5):
    print(f"    {fid}: {cnt} failure(s)")
print(f"Active proposals: {len(proposals)}  (applied: {len(applied)}, dismissed: {len(dismissed)})")
print()

# Print ranked list
print("Ranked Proposals (grouped by similarity):")
print("-" * 70)
rank = 0
for g in groups:
    rank += 1
    n_sessions = len(set(p.get("session_id", "") for p in g["proposals"] if p.get("session_id")))
    p = g["proposals"][0]
    op = p.get("op", "?")
    target = p.get("target", "")
    content_preview = p.get("content", "")[:120]
    if len(g["proposals"]) > 1:
        meta = f"({len(g['proposals'])} similar proposals merged)"
    else:
        meta = f"(proposed by session {p.get('session_id', '?')[:19]})"
    print(f"[{rank}] {meta}")
    print(f"    op:     {op}")
    if op in ("replace", "delete", "insert_after") and target:
        print(f"    target: {target[:80]}{'...' if len(target) > 80 else ''}")
    print(f"    content: {content_preview}{'...' if len(p.get('content', '')) > 120 else ''}")
    print(f"    rationale: {p.get('rationale', '(none)')[:120]}")
    print()

# Summary
print("=" * 70)
print(f"SUMMARY: {len(proposals)} proposals queued, {len(failed_approaches)} failed approaches logged, {len(since_sessions)} sessions since last consolidation")
print()
print("To apply:   bash consolidate-agents.sh --apply N")
print("To dismiss: bash consolidate-agents.sh --dismiss N")
print("=" * 70)
PYEOF

exit 0
