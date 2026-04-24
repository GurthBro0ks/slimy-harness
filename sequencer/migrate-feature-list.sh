#!/usr/bin/env bash
set -euo pipefail

FEATURE_LIST="/home/slimy/feature_list.json"
BACKUP="/home/slimy/feature_list.pre-migration-$(date +%Y%m%d-%H%M%S).json"

log() { echo "[$(date -Iseconds)] [migrate] $*"; }

if [ ! -f "$FEATURE_LIST" ]; then
  log "ERROR: feature_list.json not found at $FEATURE_LIST"
  exit 1
fi

cp "$FEATURE_LIST" "$BACKUP"
log "Backup saved to $BACKUP"

python3 << 'PYEOF'
import json
import re

feature_list_path = "/home/slimy/feature_list.json"

with open(feature_list_path) as f:
    fl = json.load(f)

features = fl.get("features", [])
migrated = 0
auto_blocked = 0
auto_blocked_ids = []

manual_patterns = re.compile(
    r"manual|Manual|discord|Discord|phone|verification|human|SUPERSEDED|superseded",
    re.IGNORECASE
)

for feat in features:
    changed = False

    if "blocked_by" not in feat:
        feat["blocked_by"] = []
        changed = True
    if "last_attempted" not in feat:
        feat["last_attempted"] = None
        changed = True
    if "attempt_count" not in feat:
        feat["attempt_count"] = 0
        changed = True
    if "status" not in feat:
        if feat.get("passes") is True:
            feat["status"] = "completed"
        else:
            feat["status"] = "open"
        changed = True

    notes = feat.get("notes", "")
    existing_blockers = feat.get("blocked_by", [])

    if manual_patterns.search(notes):
        notes_lower = notes.lower()
        blocker_entry = None

        if "superseded" in notes_lower:
            blocker_entry = "superseded:see-notes"
        elif "discord" in notes_lower and "verification" in notes_lower:
            blocker_entry = "manual:discord-verification"
        elif "phone" in notes_lower:
            blocker_entry = "manual:phone-testing"
        elif "manual" in notes_lower or "human" in notes_lower:
            blocker_entry = "manual:human-action-required"
        else:
            blocker_entry = "manual:see-notes"

        if blocker_entry and blocker_entry not in existing_blockers:
            feat["blocked_by"] = existing_blockers + [blocker_entry]
            if feat.get("status") not in ("completed",):
                feat["status"] = "blocked"
            auto_blocked += 1
            auto_blocked_ids.append((feat.get("id"), blocker_entry))
            changed = True

    if changed:
        migrated += 1

with open(feature_list_path, "w") as f:
    json.dump(fl, f, indent=2)

print(f"\n=== Migration Summary ===")
print(f"Total features: {len(features)}")
print(f"Features migrated (fields added): {migrated}")
print(f"Auto-blocked features: {auto_blocked}")
for fid, blocker in auto_blocked_ids:
    print(f"  {fid}: {blocker}")

PYEOF

python3 -c "import json; json.load(open('$FEATURE_LIST')); print('[migrate] feature_list.json validated OK')"
log "Migration complete."
