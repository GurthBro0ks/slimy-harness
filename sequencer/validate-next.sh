#!/usr/bin/env bash
set -euo pipefail

FEATURE_LIST="/home/slimy/feature_list.json"
INPUT_FILE="${1:-}"

if [ -z "$INPUT_FILE" ]; then
  echo "Usage: validate-next.sh <qwen-output.json>" >&2
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
  echo "FAIL: file not found: $INPUT_FILE" >&2
  exit 1
fi

if [ ! -f "$FEATURE_LIST" ]; then
  echo "FAIL: feature_list.json not found at $FEATURE_LIST" >&2
  exit 1
fi

VALID_PROMPT_TYPES="A B C C2 D E F G H I P"
VALID_RISKS="low medium high"

python3 -c "
import json, sys

input_file = sys.argv[1]
feature_list_file = sys.argv[2]
valid_prompt_types = sys.argv[3].split()
valid_risks = sys.argv[4].split()

try:
    with open(input_file) as f:
        data = json.load(f)
except json.JSONDecodeError as e:
    print(f'FAIL: invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)

required = ['next_feature_id', 'project', 'prompt_type', 'reasoning', 'risk', 'kb_context_for_agent']
for key in required:
    if key not in data:
        print(f'FAIL: missing required field: {key}', file=sys.stderr)
        sys.exit(1)

feature_id = data['next_feature_id']
prompt_type = data['prompt_type']
project = data['project']
risk = data['risk']

if prompt_type not in valid_prompt_types:
    print(f'FAIL: invalid prompt_type \"{prompt_type}\", must be one of: {valid_prompt_types}', file=sys.stderr)
    sys.exit(1)

if risk not in valid_risks:
    print(f'FAIL: invalid risk \"{risk}\", must be one of: {valid_risks}', file=sys.stderr)
    sys.exit(1)

with open(feature_list_file) as f:
    fl = json.load(f)

features = fl.get('features', [])
target = None
for feat in features:
    if feat.get('id') == feature_id:
        target = feat
        break

if target is None:
    print(f'FAIL: feature_id \"{feature_id}\" not found in feature_list.json', file=sys.stderr)
    sys.exit(1)

if target.get('passes') is True:
    print(f'FAIL: feature \"{feature_id}\" already passes:true', file=sys.stderr)
    sys.exit(1)

status = target.get('status', 'open')
if status in ('completed', 'abandoned'):
    print(f'FAIL: feature \"{feature_id}\" has status \"{status}\"', file=sys.stderr)
    sys.exit(1)

fl_project = target.get('project', '')
if project != fl_project:
    print(f'FAIL: project mismatch: dispatch says \"{project}\" but feature_list says \"{fl_project}\"', file=sys.stderr)
    sys.exit(1)

print('PASS')
" "$INPUT_FILE" "$FEATURE_LIST" "$VALID_PROMPT_TYPES" "$VALID_RISKS"
