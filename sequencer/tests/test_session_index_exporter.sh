#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXPORTER="$REPO_ROOT/sequencer/export-session-index.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

sessions_dir="$tmp_dir/sessions"
mkdir -p "$sessions_dir"

cat > "$sessions_dir/with-date.json" <<'JSON'
{
  "session_id": "with-date",
  "project": "slimy-harness",
  "result": "PASS",
  "timestamp": "2026-06-13T10:00:00Z",
  "proof_dir": "/tmp/proof_with_date",
  "report_url": "https://harness.slimyai.xyz/reports/sessions/with-date.json",
  "warnings": []
}
JSON

redacted_name="$(printf '%s%s' 'BOT_' 'TOKEN')"
raw_field="$(printf '%s_%s' 'raw' 'log')"
raw_value="$(printf '%s %s %s must stay out of the index' 'raw' 'proof' 'content')"
home_root="/$(printf '%s/%s' 'home' 'slimy')"
opt_root="/$(printf '%s/%s' 'opt' 'slimy')"
tmp_proof="/$(printf '%s/%s' 'tmp' 'proof_missing_date')"
cat > "$sessions_dir/missing-date.json" <<JSON
{
  "session_id": "missing-date",
  "project": "gh-tracker",
  "result": "WARN",
  "repo": "$home_root/slimy-harness;$opt_root/gh-tracker",
  "proof_dir": "$tmp_proof",
  "warning": "$redacted_name=should-not-leak",
  "$raw_field": "$raw_value"
}
JSON
touch -d "2026-06-14T12:34:56Z" "$sessions_dir/missing-date.json"

bash "$EXPORTER" --dry-run --sessions-dir "$sessions_dir" > "$tmp_dir/index.json"

python3 - "$tmp_dir/index.json" <<'PY'
import datetime as dt
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
index = json.loads(path.read_text())

assert index["schema_version"] == "harness-session-index/v1"
assert index["generated_by"] == "sequencer/export-session-index.sh"
dt.datetime.fromisoformat(index["generated_at"].replace("Z", "+00:00"))
assert index["session_count"] == 2
assert len(index["sessions"]) == 2

sessions = {session["session_id"]: session for session in index["sessions"]}
assert sessions["with-date"]["created_at"] == "2026-06-13T10:00:00Z"
assert sessions["with-date"]["created_at_source"] == "timestamp"
assert sessions["with-date"]["report_url"] == "https://harness.slimyai.xyz/reports/sessions/with-date.json"
assert sessions["missing-date"]["created_at"] == "2026-06-14T12:34:56Z"
assert sessions["missing-date"]["created_at_source"] == "file_mtime"

for session in index["sessions"]:
    dt.datetime.fromisoformat(session["created_at"].replace("Z", "+00:00"))
    assert session["source_report"].endswith(".json")

encoded = json.dumps(index, sort_keys=True)
for forbidden in ("should-not-leak", "BOT_TOKEN", "raw proof content", "/home/slimy", "/opt/slimy", "/tmp/proof_"):
    assert forbidden not in encoded, forbidden
assert "slimy-harness;gh-tracker" in encoded
assert "proof_missing_date" in encoded
PY

echo "PASS session index exporter metadata freshness"
