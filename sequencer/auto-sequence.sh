#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
MAX_SESSIONS="${MAX_SESSIONS:-5}"
SEQUNCER_DIR="/home/slimy/slimy-harness/sequencer"
SESSION_REPORT="/home/slimy/session-report.json"
FEATURE_LIST="/home/slimy/feature_list.json"
NARRATIVE="/home/slimy/PROJECT_NARRATIVE.md"
STATE_FILE="/home/slimy/.sequencer-state.json"
KB_SESSIONS_DIR="/home/slimy/slimy-kb/raw/sessions"
QWEN_URL="${QWEN_URL:-http://localhost:11434/api/generate}"
QWEN_MODEL="${QWEN_MODEL:-qwen2.5:3b}"
ERROR_LOG="/home/slimy/sequencer-errors.log"
PENDING_APPROVAL="/home/slimy/pending-approval.json"
DISPATCH_OUTPUT="/tmp/qwen-dispatch-output.json"

log() { echo "[$(date -Iseconds)] [auto-sequence] $*"; }
err() { echo "[$(date -Iseconds)] [auto-sequence] ERROR: $*" >> "$ERROR_LOG"; }

if [ ! -f "$SESSION_REPORT" ]; then
  log "No session report at $SESSION_REPORT. Nothing to do."
  exit 0
fi

if [ ! -f "$FEATURE_LIST" ]; then
  err "feature_list.json not found at $FEATURE_LIST"
  exit 1
fi

TODAY=$(date +%Y-%m-%d)
NOW_ISO=$(date -Iseconds)

if [ -f "$STATE_FILE" ]; then
  STATE_DATE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('date',''))" 2>/dev/null || echo "")
  STATE_SESSIONS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('sessions_today',0))" 2>/dev/null || echo "0")
else
  STATE_DATE=""
  STATE_SESSIONS=0
fi

if [ "$STATE_DATE" != "$TODAY" ]; then
  STATE_SESSIONS=0
fi

if [ "$STATE_SESSIONS" -ge "$MAX_SESSIONS" ]; then
  log "Max sessions reached ($STATE_SESSIONS/$MAX_SESSIONS). Stopping."
  if command -v sr-notify &>/dev/null; then
    sr-notify "Sequencer: max sessions ($MAX_SESSIONS) reached today. Stopping." 2>/dev/null || true
  fi
  exit 0
fi

REPORT_TS=$(python3 -c "import json; print(json.load(open('$SESSION_REPORT')).get('timestamp','unknown'))" 2>/dev/null || echo "unknown")
mkdir -p "$KB_SESSIONS_DIR"
cp "$SESSION_REPORT" "$KB_SESSIONS_DIR/report-${REPORT_TS}.json" 2>/dev/null || true
log "Session report archived to KB."

SESSION_REPORT_JSON=$(python3 -c "
import json
with open('$SESSION_REPORT') as f:
    print(json.dumps(json.load(f)))
" 2>/dev/null || echo '{}')

AVAILABLE_FEATURES=$(python3 -c "
import json
with open('$FEATURE_LIST') as f:
    fl = json.load(f)
features = fl.get('features', [])
available = []
for feat in features:
    if feat.get('passes') is True:
        continue
    status = feat.get('status', 'open')
    if status in ('completed', 'abandoned'):
        continue
    blocked_by = feat.get('blocked_by', [])
    has_blocker = False
    for b in blocked_by:
        if isinstance(b, str) and b.startswith('manual:'):
            has_blocker = True
            break
        for other in features:
            if other.get('id') == b and other.get('status', 'open') != 'completed':
                has_blocker = True
                break
        if has_blocker:
            break
    if has_blocker:
        continue
    available.append({
        'id': feat.get('id'),
        'project': feat.get('project'),
        'description': feat.get('description', ''),
        'priority': feat.get('priority', 'medium'),
        'risk': feat.get('risk', 'medium'),
        'attempt_count': feat.get('attempt_count', 0),
        'status': status
    })
print(json.dumps(available))
")

if [ "$AVAILABLE_FEATURES" = "[]" ]; then
  log "No available features. Nothing to dispatch."
  exit 0
fi

NARRATIVE_SUMMARY=""
if [ -f "$NARRATIVE" ]; then
  NARRATIVE_SUMMARY=$(head -c 2000 "$NARRATIVE" | python3 -c "
import sys, json
text = sys.stdin.read()
print(json.dumps(text))
")
fi

LAST_PROJECT=$(python3 -c "
import json
report = json.loads('$SESSION_REPORT_JSON')
print(report.get('project', ''))
" 2>/dev/null || echo "")
LAST_DESC=$(python3 -c "
import json
report = json.loads('$SESSION_REPORT_JSON')
print(report.get('summary', ''))
" 2>/dev/null || echo "")

KB_CONTEXT=""
if [ -d "/home/slimy/slimy-kb" ] && [ -x "/home/slimy/slimy-kb/tools/kb-search.sh" ]; then
  KB_RESULT=$(bash /home/slimy/slimy-kb/tools/kb-search.sh "$LAST_PROJECT $LAST_DESC" 2>/dev/null | head -c 1000 || echo "")
  KB_CONTEXT=$(python3 -c "
import json
print(json.dumps('''$KB_RESULT'''))
" 2>/dev/null || echo '""')
fi

PROMPT=$(python3 -c "
import json, sys

session_report_json = '$SESSION_REPORT_JSON'
available_features_json = '$AVAILABLE_FEATURES'

try:
    report = json.loads(session_report_json) if session_report_json != '{}' else {}
except:
    report = {}
try:
    features = json.loads(available_features_json)
except:
    features = []

prio_order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}
features.sort(key=lambda x: (prio_order.get(x.get('priority','medium'), 9), x.get('attempt_count', 0)))
candidates = features[:10]

last_project = report.get('project', 'unknown')
last_status = report.get('status', 'unknown')

prompt = f\"\"\"You are a task dispatcher. Pick the best next task from this list. Output ONLY valid JSON.

Last session: project={last_project}, status={last_status}

Available tasks (sorted by priority):
{json.dumps(candidates, indent=2)}

Rules: Pick highest priority. Prefer same project as last session for context reuse. Do not retry failed features immediately.

Output this exact JSON format (respond with ONLY the JSON, nothing else):
{{\"next_feature_id\": \"id-here\", \"project\": \"project-name\", \"prompt_type\": \"A\", \"reasoning\": \"brief reason\", \"risk\": \"medium\", \"kb_context_for_agent\": \"\"}}
\"\"\"

print(prompt)
")

log "Calling $QWEN_MODEL on localhost..."
PROMPT_FILE="/tmp/qwen-dispatch-prompt.txt"
echo "$PROMPT" > "$PROMPT_FILE"

QWEN_RESPONSE=$(python3 -c "
import json, urllib.request, sys

with open('$PROMPT_FILE') as f:
    prompt = f.read()

payload = json.dumps({
    'model': '$QWEN_MODEL',
    'prompt': prompt,
    'stream': False,
    'options': {'temperature': 0.0, 'num_predict': 500}
}).encode()

req = urllib.request.Request(
    '$QWEN_URL',
    data=payload,
    headers={'Content-Type': 'application/json'}
)

try:
    with urllib.request.urlopen(req, timeout=180) as resp:
        result = json.load(resp)
        print(result.get('response', ''))
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || echo "")

if [ -z "$QWEN_RESPONSE" ]; then
  err "Qwen returned empty response."
  QWEN_RESPONSE=""
fi

VALID_DISPATCH=false
if [ -n "$QWEN_RESPONSE" ]; then
  echo "$QWEN_RESPONSE" > "$DISPATCH_OUTPUT"
  if bash "$SEQUNCER_DIR/validate-next.sh" "$DISPATCH_OUTPUT" 2>/dev/null; then
    VALID_DISPATCH=true
    log "Qwen dispatch validated."
  else
    VALIDATION_ERR=$(bash "$SEQUNCER_DIR/validate-next.sh" "$DISPATCH_OUTPUT" 2>&1 || true)
    err "Qwen dispatch validation failed: $VALIDATION_ERR"
  fi
fi

DISPATCH_FEATURE_ID=""
DISPATCH_PROJECT=""
DISPATCH_PROMPT_TYPE=""
DISPATCH_RISK=""
DISPATCH_REASONING=""
DISPATCH_KB_CONTEXT=""

if [ "$VALID_DISPATCH" = true ]; then
  DISPATCH_FEATURE_ID=$(python3 -c "import json; print(json.load(open('$DISPATCH_OUTPUT'))['next_feature_id'])")
  DISPATCH_PROJECT=$(python3 -c "import json; print(json.load(open('$DISPATCH_OUTPUT'))['project'])")
  DISPATCH_PROMPT_TYPE=$(python3 -c "import json; print(json.load(open('$DISPATCH_OUTPUT'))['prompt_type'])")
  DISPATCH_RISK=$(python3 -c "import json; print(json.load(open('$DISPATCH_OUTPUT'))['risk'])")
  DISPATCH_REASONING=$(python3 -c "import json; print(json.load(open('$DISPATCH_OUTPUT')).get('reasoning',''))")
  DISPATCH_KB_CONTEXT=$(python3 -c "import json; print(json.load(open('$DISPATCH_OUTPUT')).get('kb_context_for_agent',''))")
else
  log "Falling back to deterministic pick..."
  FALLBACK=$(python3 -c "
import json
with open('$FEATURE_LIST') as f:
    fl = json.load(f)
priority_order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}
candidates = []
for feat in fl.get('features', []):
    if feat.get('passes') is True:
        continue
    status = feat.get('status', 'open')
    if status in ('completed', 'abandoned'):
        continue
    blocked_by = feat.get('blocked_by', [])
    has_blocker = False
    for b in blocked_by:
        if isinstance(b, str) and b.startswith('manual:'):
            has_blocker = True
            break
    if has_blocker:
        continue
    candidates.append(feat)
if not candidates:
    print(json.dumps({}))
    exit()
candidates.sort(key=lambda f: (priority_order.get(f.get('priority','medium'), 2), f.get('attempt_count', 0)))
pick = candidates[0]
print(json.dumps({
    'next_feature_id': pick['id'],
    'project': pick.get('project',''),
    'prompt_type': 'A',
    'reasoning': 'Deterministic fallback: highest priority, lowest attempt_count',
    'risk': pick.get('risk','medium'),
    'kb_context_for_agent': ''
}))
")
  DISPATCH_FEATURE_ID=$(echo "$FALLBACK" | python3 -c "import json,sys; print(json.load(sys.stdin).get('next_feature_id',''))")
  DISPATCH_PROJECT=$(echo "$FALLBACK" | python3 -c "import json,sys; print(json.load(sys.stdin).get('project',''))")
  DISPATCH_PROMPT_TYPE=$(echo "$FALLBACK" | python3 -c "import json,sys; print(json.load(sys.stdin).get('prompt_type','A'))")
  DISPATCH_RISK=$(echo "$FALLBACK" | python3 -c "import json,sys; print(json.load(sys.stdin).get('risk','medium'))")
  DISPATCH_REASONING=$(echo "$FALLBACK" | python3 -c "import json,sys; print(json.load(sys.stdin).get('reasoning',''))")
  DISPATCH_KB_CONTEXT=""
  log "Fallback picked: $DISPATCH_FEATURE_ID ($DISPATCH_PROJECT)"
fi

if [ -z "$DISPATCH_FEATURE_ID" ]; then
  log "No feature to dispatch. Exiting."
  exit 0
fi

if [ "$DISPATCH_RISK" = "high" ]; then
  log "HIGH-risk feature detected. Writing pending-approval.json and pinging Discord."
  python3 -c "
import json, datetime
data = {
    'feature_id': '$DISPATCH_FEATURE_ID',
    'project': '$DISPATCH_PROJECT',
    'prompt_type': '$DISPATCH_PROMPT_TYPE',
    'risk': '$DISPATCH_RISK',
    'reasoning': '''$DISPATCH_REASONING''',
    'timestamp': datetime.datetime.now().isoformat(),
    'status': 'pending_approval'
}
with open('$PENDING_APPROVAL', 'w') as f:
    json.dump(data, f, indent=2)
"
  if command -v sr-notify &>/dev/null; then
    sr-notify "HIGH-RISK task requires approval: $DISPATCH_FEATURE_ID in $DISPATCH_PROJECT. Check $PENDING_APPROVAL" 2>/dev/null || true
  fi
  log "Waiting for human approval. Exiting."
  exit 0
fi

log "Dispatching: $DISPATCH_FEATURE_ID in $DISPATCH_PROJECT [risk=$DISPATCH_RISK]"

if [ "$DRY_RUN" = "1" ]; then
  log "DRY RUN: would dispatch feature=$DISPATCH_FEATURE_ID project=$DISPATCH_PROJECT prompt_type=$DISPATCH_PROMPT_TYPE risk=$DISPATCH_RISK"
  log "DRY RUN: reasoning=$DISPATCH_REASONING"
  NEW_SESSIONS=$((STATE_SESSIONS + 1))
  python3 -c "
import json, datetime
state = {
    'date': '$TODAY',
    'sessions_today': $NEW_SESSIONS,
    'last_dispatch': datetime.datetime.now().isoformat(),
    'last_feature': '$DISPATCH_FEATURE_ID'
}
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"
  log "DRY RUN: Done. Session $NEW_SESSIONS/$MAX_SESSIONS today (simulated)."
  exit 0
fi

if command -v slimy-run &>/dev/null; then
  log "Running slimy-run auto with generated prompt..."
  slimy-run auto --feature "$DISPATCH_FEATURE_ID" --project "$DISPATCH_PROJECT" --prompt-type "$DISPATCH_PROMPT_TYPE" 2>/dev/null || {
    err "slimy-run dispatch failed for $DISPATCH_FEATURE_ID"
  }
else
  log "slimy-run not found. Manual dispatch required."
  log "  Feature: $DISPATCH_FEATURE_ID"
  log "  Project: $DISPATCH_PROJECT"
  log "  Prompt type: $DISPATCH_PROMPT_TYPE"
  log "  KB context: $DISPATCH_KB_CONTEXT"
fi

NEW_SESSIONS=$((STATE_SESSIONS + 1))
python3 -c "
import json, datetime
state = {
    'date': '$TODAY',
    'sessions_today': $NEW_SESSIONS,
    'last_dispatch': datetime.datetime.now().isoformat(),
    'last_feature': '$DISPATCH_FEATURE_ID'
}
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"

if command -v sr-notify &>/dev/null; then
  sr-notify "Dispatched: $DISPATCH_FEATURE_ID in $DISPATCH_PROJECT [$DISPATCH_RISK]" 2>/dev/null || true
fi

log "Done. Session $NEW_SESSIONS/$MAX_SESSIONS today."
