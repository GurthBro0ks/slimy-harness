#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"
VERSION_JSON="$REPO_ROOT/version.json"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"

if [ ! -f "$VERSION_FILE" ]; then
  echo "VERSION missing" >&2
  exit 1
fi

if [ ! -f "$VERSION_JSON" ]; then
  echo "version.json missing" >&2
  exit 1
fi

python3 - <<'PY' "$VERSION_FILE" "$VERSION_JSON" "$CHANGELOG_FILE"
import json
import sys
from pathlib import Path

version_file = Path(sys.argv[1])
version_json = Path(sys.argv[2])
changelog_file = Path(sys.argv[3])

version = version_file.read_text(encoding='utf-8').strip()
if not version:
    raise SystemExit('VERSION is empty')

data = json.loads(version_json.read_text(encoding='utf-8'))
if data.get('version') != version:
    raise SystemExit('VERSION does not match version.json')
if data.get('status') == 'complete':
    raise SystemExit('status must not be complete before manual QA')
public_url = str(data.get('public_report_url', ''))
if 'harness.slimyai.xyz' not in public_url:
    raise SystemExit('public_report_url must reference harness.slimyai.xyz')
if version not in changelog_file.read_text(encoding='utf-8'):
    raise SystemExit('CHANGELOG.md is missing the current version entry')

print(f'validate-version: OK ({version})')
PY
