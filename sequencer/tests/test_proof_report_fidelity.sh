#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCHIVER="$REPO_ROOT/sequencer/archive-proof-dir-session.sh"
FIXTURE="$REPO_ROOT/sequencer/tests/fixtures/report-fidelity-proof.json"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

python3 - "$FIXTURE" "$TEMP" <<'PY'
import json
import sys
from pathlib import Path

fixture = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
proof = Path(sys.argv[2]) / fixture["proof_basename"]
proof.mkdir()
for name in fixture["artifact_files"]:
    (proof / name).write_text("fixture artifact\n", encoding="utf-8")
(proof / "RESULT.md").write_text(fixture["result"], encoding="utf-8")
for name, content in fixture["contents"].items():
    (proof / name).write_text(content, encoding="utf-8")
PY

proof="$TEMP/$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["proof_basename"])' "$FIXTURE")"
sessions="$TEMP/sessions"
mkdir -p "$sessions"
"$ARCHIVER" --proof-dir "$proof" --repo-path "$REPO_ROOT" --repo-name slimy-harness \
  --agent codex --sessions-dir "$sessions" --index-output "$sessions/harness-session-index.json" >/dev/null
report="$(find "$sessions" -maxdepth 1 -type f -name 'report-proof-*.json' | head -1)"

python3 - "$report" "$REPO_ROOT/sequencer/session-report.schema.json" <<'PY'
import json
import sys
from pathlib import Path

import jsonschema

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
schema = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
jsonschema.validate(report, schema)

assert report["status"] == "pass"
assert report["tests"]["label"] == "TESTS PASS"
assert report["tests"]["ran"] is True
assert report["tests"]["passed"] is True
assert "Focused tests: 33/33 PASS" in report["tests"]["details"]
assert "Full tests: 83/83 PASS" in report["tests"]["details"]
assert "Harness validation: 145/0 PASS" in report["tests"]["details"]
for marker in ("Collision: 1/1 PASS", "Concurrency: 1/1 PASS", "Torn-write: 1/1 PASS"):
    assert marker in report["tests"]["details"], marker
assert report["duration_minutes"] == 9
assert report["duration_source"].startswith("RESULT.md:STARTED_AT")
assert report["artifacts"]["directory_files_total"] == 47
assert report["artifacts"]["proof_files_total"] == 44
assert report["artifacts"]["displayed_count"] == 44
assert len(report["artifacts"]["displayed_files"]) == 44
assert report["artifacts"]["excluded_count"] == 3
assert report["run_id"].startswith("run_20260713T113521654589Z_")
assert report["subject_id"].startswith("slimy-harness@646097f6")
assert report["pushed"] is False
assert report["production_storage_state"] == "inactive"
assert report["underlying_functional_qa"] == "PASS"
assert report["manual_qa_status"] == "pending_owner_review"
assert report["operator_qa"] == "pending_owner_review"
assert report["next_action"].startswith("Owner reviews the protected QA report.")
assert report["blockers"] == []
assert "TESTS NOT RUN" not in json.dumps(report)
PY

echo "PASS proof report fidelity fixture"
