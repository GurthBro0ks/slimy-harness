#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
MAX_SESSIONS="${MAX_SESSIONS:-5}"
LOOP_MODE=0
STOP_FILE="/home/slimy/.harness-stop"
LOOP_LOG_DIR="/home/slimy/harness-logs"
HARNESS_ENV_FILE="/home/slimy/.slimy-harness.env"
SEQUNCER_DIR="/home/slimy/slimy-harness/sequencer"
SESSION_REPORT="/home/slimy/session-report.json"
FEATURE_LIST="/home/slimy/feature_list.json"
FAILED_APPROACHES="/home/slimy/failed-approaches.json"
NARRATIVE="/home/slimy/PROJECT_NARRATIVE.md"
STATE_FILE="/home/slimy/.sequencer-state.json"
KB_SESSIONS_DIR="/home/slimy/slimy-kb/raw/sessions"
QWEN_URL="${QWEN_URL:-http://localhost:11434/api/generate}"
QWEN_MODEL="${QWEN_MODEL:-qwen2.5:3b}"
ERROR_LOG="/home/slimy/sequencer-errors.log"
PENDING_APPROVAL="/home/slimy/pending-approval.json"
DISPATCH_OUTPUT="/tmp/qwen-dispatch-output.json"
DISPATCH_RESULT=""

if [ -f "$HARNESS_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$HARNESS_ENV_FILE"
  set +a
fi

HARNESS_REPORT_BASE_URL="${HARNESS_REPORT_BASE_URL:-http://nuc2:3838}"
HARNESS_REPORT_BASE_URL="${HARNESS_REPORT_BASE_URL%/}"

for arg in "$@"; do
  case "$arg" in
    --loop) LOOP_MODE=1 ;;
  esac
done

log() { echo "[$(date -Iseconds)] [auto-sequence] $*" >&2; }
err() { echo "[$(date -Iseconds)] [auto-sequence] ERROR: $*" >> "$ERROR_LOG"; }
loop_log() { echo "[$(date -Iseconds)] [loop] $*" >> "${LOOP_LOG_DIR}/loop-$(date +%Y%m%d).log"; }

run_dispatch() {
  DISPATCH_RESULT=""

  if [ -f "$STOP_FILE" ]; then
    log "Stop file detected ($STOP_FILE). Exiting loop."
    DISPATCH_RESULT="stopped"
    return 0
  fi

  if [ ! -f "$SESSION_REPORT" ]; then
    log "No session report at $SESSION_REPORT. Nothing to do."
    DISPATCH_RESULT="no_report"
    return 0
  fi

  if [ ! -f "$FEATURE_LIST" ]; then
    err "feature_list.json not found at $FEATURE_LIST"
    echo "error" >&2
    DISPATCH_RESULT="error"
    return 1
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
  _WH_URL="https://discord.com/api/webhooks/1490483635218944132/5IMm4_6okNjARRtwnf7SfAGV1IJDEzNGGOR4JWdkir8TWGGQLPq0B82rC1r876vRPRpj"
  curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" \
    -d "{\"content\":\"Sequencer: max sessions ($MAX_SESSIONS) reached today. Stopping.\"}" "$_WH_URL" 2>/dev/null || true
  DISPATCH_RESULT="budget"
  return 0
fi

REPORT_TS=$(python3 -c "import json; print(json.load(open('$SESSION_REPORT')).get('timestamp','unknown'))" 2>/dev/null || echo "unknown")
mkdir -p "$KB_SESSIONS_DIR"
cp "$SESSION_REPORT" "$KB_SESSIONS_DIR/report-${REPORT_TS}.json" 2>/dev/null || true
log "Session report archived to KB."

log "Syncing session reports to NUC2..."
bash "$SEQUNCER_DIR/sync-session-reports-to-nuc2.sh" 2>&1 || warn "Session report sync to NUC2 failed (non-fatal)"

log "Running auto-close to update feature_list.json from session report..."
bash "$SEQUNCER_DIR/auto-close.sh" 2>&1 || err "auto-close.sh failed"

log "Generating blocker report..."
bash "$SEQUNCER_DIR/blocker-report.sh" 2>&1 || err "blocker-report.sh failed"

SESSION_REPORT_JSON=$(python3 -c "
import json
with open('$SESSION_REPORT') as f:
    print(json.dumps(json.load(f)))
" 2>/dev/null || echo '{}')

AVAILABLE_FEATURES_FILE="/tmp/sequencer-available-features.json"
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
    if feat.get('blocked_by') and len(feat.get('blocked_by', [])) > 0:
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
echo "$AVAILABLE_FEATURES" > "$AVAILABLE_FEATURES_FILE"

if [ "$AVAILABLE_FEATURES" = "[]" ]; then
  log "No available features. Nothing to dispatch."
  bash "$SEQUNCER_DIR/notify-blockers.sh" 2>&1 || true
  DISPATCH_RESULT="no_work"
  return 0
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
with open('$SESSION_REPORT') as f:
    report = json.load(f)
print(report.get('project', ''))
" 2>/dev/null || echo "")
LAST_DESC=$(python3 -c "
import json
with open('$SESSION_REPORT') as f:
    report = json.load(f)
print(report.get('summary', ''))
" 2>/dev/null || echo "")

KB_CONTEXT=""
if [ -d "/home/slimy/slimy-kb" ] && [ -x "/home/slimy/slimy-kb/tools/kb-search.sh" ]; then
  KB_RESULT=$(bash /home/slimy/slimy-kb/tools/kb-search.sh "$LAST_PROJECT $LAST_DESC" 2>/dev/null | head -c 1000 || echo "")
  KB_CONTEXT=$(echo "$KB_RESULT" | python3 -c "
import sys, json
text = sys.stdin.read()
print(json.dumps(text))
" 2>/dev/null || echo '""')
fi

PROMPT=$(python3 -c "
import json, sys, os

try:
    with open('$SESSION_REPORT') as f:
        report = json.load(f)
except:
    report = {}
try:
    with open('$AVAILABLE_FEATURES_FILE') as f:
        features = json.load(f)
except:
    features = []

# SkillOpt: load failed-approaches.json so Qwen can see what NOT to recommend
failed_approaches = []
failed_path = '$FAILED_APPROACHES'
if os.path.isfile(failed_path):
    try:
        with open(failed_path) as f:
            fa = json.load(f)
        failed_approaches = fa.get('entries', [])
    except Exception:
        failed_approaches = []

prio_order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}
features.sort(key=lambda x: (prio_order.get(x.get('priority','medium'), 9), x.get('attempt_count', 0)))
candidates = features[:10]

# Build failed-approaches context block filtered to the candidate features
candidate_ids = {f.get('id') for f in candidates if f.get('id')}
matching_fa = [e for e in failed_approaches if e.get('feature_id') in candidate_ids]
matching_fa.sort(key=lambda e: e.get('timestamp', ''), reverse=True)
matching_fa = matching_fa[:5]

if matching_fa:
    fa_lines = []
    for e in matching_fa:
        fa_lines.append(
            f\"- [{e.get('feature_id')}] attempt #{e.get('attempt_number', '?')} ({e.get('timestamp', '?')}):\\n\"\n            f\"    approach: {e.get('approach_description', '(none)')}\\n\"\n            f\"    failure:  {e.get('failure_reason', '(none)')}\"
        )
    failed_approaches_context = '\\n'.join(fa_lines)
else:
    failed_approaches_context = '(no prior failed approaches recorded for these candidates)'

last_project = report.get('project', 'unknown')
last_status = report.get('status', 'unknown')

prompt = f\"\"\"You are a task dispatcher. Pick the best next task from this list. Output ONLY valid JSON.

Last session: project={last_project}, status={last_status}

Available tasks (sorted by priority):
{json.dumps(candidates, indent=2)}

FAILED APPROACHES (do NOT recommend a feature that the buffer says failed on the most recent attempt unless you have specific new information):
{failed_approaches_context}

Rules: Pick highest priority. Prefer same project as last session for context reuse. Do not retry failed features immediately. Prefer features with fewer attempts (lower attempt_count). Treat FAILED APPROACHES as hard signals.

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
    if blocked_by and len(blocked_by) > 0:
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
  DISPATCH_RESULT="no_work"
  return 0
fi

if [ "$DISPATCH_RISK" = "high" ]; then
  log "HIGH-risk feature detected. Writing pending-approval.json and pinging Discord."
  _DR="$DISPATCH_REASONING" python3 -c "
import json, datetime, os
data = {
    'feature_id': '$DISPATCH_FEATURE_ID',
    'project': '$DISPATCH_PROJECT',
    'prompt_type': '$DISPATCH_PROMPT_TYPE',
    'risk': '$DISPATCH_RISK',
    'reasoning': os.environ.get('_DR', ''),
    'timestamp': datetime.datetime.now().isoformat(),
    'status': 'pending_approval'
}
with open('$PENDING_APPROVAL', 'w') as f:
    json.dump(data, f, indent=2)
"
  _WH_URL="https://discord.com/api/webhooks/1490483635218944132/5IMm4_6okNjARRtwnf7SfAGV1IJDEzNGGOR4JWdkir8TWGGQLPq0B82rC1r876vRPRpj"
  curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" \
    -d "{\"content\":\"HIGH-RISK task requires approval: $DISPATCH_FEATURE_ID in $DISPATCH_PROJECT. Check $PENDING_APPROVAL\"}" "$_WH_URL" 2>/dev/null || true
  log "Waiting for human approval. Exiting."
  DISPATCH_RESULT="approval"
  return 0
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
  DISPATCH_RESULT="dry_run"
  return 0
fi

DISPATCH_PROMPT_FILE="/tmp/next-task-prompt.txt"

python3 -c "
import json
import os

SHUTDOWN_ADDON = '''
## SEQUENCER SHUTDOWN (do this LAST, after all other shutdown steps)

Write /home/slimy/session-report.json with this structure:
{
  \"session_id\": \"[current ISO-8601 timestamp]\",
  \"agent\": \"opencode\",
  \"nuc\": \"nuc1\",
  \"project\": \"$DISPATCH_PROJECT\",
  \"feature_id\": \"$DISPATCH_FEATURE_ID\",
  \"prompt_type\": \"$DISPATCH_PROMPT_TYPE\",
  \"status\": \"[completed|partial|failed|blocked]\",
  \"summary\": \"[1-2 sentences: what you did]\",
  \"changes\": [\"list\", \"of\", \"files\", \"changed\"],
  \"tests\": {\"ran\": false, \"passed\": false, \"details\": \"\"},
  \"blockers\": [],
  \"recommendation\": {\"next_feature_id\": null, \"reasoning\": \"\", \"risk_notes\": \"\"},
  \"kb_learnings\": [],
  \"duration_minutes\": 0,
  \"timestamp\": \"[current ISO-8601]\"
}

Validate the JSON before writing:
python3 -c \"import json; json.load(open('/home/slimy/session-report.json')); print('session-report.json: valid')\"
'''

# SkillOpt: load failed approaches for the selected feature only (up to 5)
failed_approaches_block = ''
fa_path = '$FAILED_APPROACHES'
if os.path.isfile(fa_path):
    try:
        with open(fa_path) as f:
            fa = json.load(f)
        all_entries = fa.get('entries', [])
        matching = [e for e in all_entries if e.get('feature_id') == '$DISPATCH_FEATURE_ID']
        matching.sort(key=lambda e: e.get('timestamp', ''), reverse=True)
        matching = matching[:5]
        if matching:
            lines = ['', '## FAILED APPROACHES (SkillOpt intelligence layer)', '']
            lines.append('The following approaches for THIS feature have been tried and FAILED. Do NOT repeat them.')
            lines.append('If a similar approach is unavoidable, document in your session-report.json summary')
            lines.append('exactly what is different and why you believe it will work this time.')
            lines.append('')
            for e in matching:
                lines.append(f\"- attempt #{e.get('attempt_number','?')} ({e.get('timestamp','?')}):\")
                lines.append(f\"  approach: {e.get('approach_description','(none)')}\")
                lines.append(f\"  failure:  {e.get('failure_reason','(none)')}\")
                lines.append('')
            failed_approaches_block = '\\n'.join(lines)
    except Exception as e:
        failed_approaches_block = ''

prompt = f'''You are an autonomous agent dispatched by the SlimyAI sequencer.

MANDATORY STARTUP (do all before writing any code):
1. cat /home/slimy/AGENTS.md
2. cat /home/slimy/claude-progress.md
3. cat /home/slimy/feature_list.json
4. cat /home/slimy/server-state.md
5. source /home/slimy/init.sh

YOUR TASK: Fix feature $DISPATCH_FEATURE_ID in project $DISPATCH_PROJECT.
Description from feature list: look up this feature ID in feature_list.json.
Read the feature steps and implement them.

Priority: $DISPATCH_RISK
Reasoning for selection: $DISPATCH_REASONING
{failed_approaches_block}
BEFORE CODING: write /home/slimy/sprint-contract.md with 3-7 testable done criteria.

MANDATORY SHUTDOWN:
1. Update /home/slimy/claude-progress.md
2. Do NOT set passes:true (leave for QA)
3. git commit in the project repo
4. Run truth gate (lint/tests) and verify
{SHUTDOWN_ADDON}

Do not ask questions. Execute autonomously. Start now.
'''

with open('$DISPATCH_PROMPT_FILE', 'w') as f:
    f.write(prompt)
"

log "Dispatch prompt written to $DISPATCH_PROMPT_FILE"

PROJECT_DIR=$(python3 -c "
import json
with open('$FEATURE_LIST') as f:
    fl = json.load(f)
for feat in fl.get('features', []):
    if feat.get('id') == '$DISPATCH_FEATURE_ID':
        print(feat.get('path', '/home/slimy'))
        break
else:
    print('/home/slimy')
")

DISPATCH_LOG="/home/slimy/harness-logs/dispatch-${DISPATCH_FEATURE_ID}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p /home/slimy/harness-logs

SESSION_NAME=""
if command -v opencode &>/dev/null && command -v tmux &>/dev/null; then
  SESSION_NAME="seq-$(date +%Y%m%d-%H%M%S)"
  log "Dispatching via opencode run in tmux session '$SESSION_NAME'..."
  log "Working dir: $PROJECT_DIR"
  log "Prompt: $DISPATCH_PROMPT_FILE"
  log "Log: $DISPATCH_LOG"
  tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_DIR" \
    "opencode run --dir '$PROJECT_DIR' --dangerously-skip-permissions \"\$(cat $DISPATCH_PROMPT_FILE)\" 2>&1 | tee '$DISPATCH_LOG'; echo 'DISPATCH_FINISHED exit=\$?' >> '$DISPATCH_LOG'"
  log "Dispatched to tmux session: $SESSION_NAME (PID: \$(tmux list-panes -t '$SESSION_NAME' -F '#{pane_pid}' 2>/dev/null || echo 'unknown'))"
  log "Monitor: tmux attach -t $SESSION_NAME"
  log "Logs: tail -f $DISPATCH_LOG"
elif command -v opencode &>/dev/null; then
  log "Dispatching via opencode run (foreground) in $PROJECT_DIR..."
  opencode run --dir "$PROJECT_DIR" --dangerously-skip-permissions "$(cat "$DISPATCH_PROMPT_FILE")" 2>&1 | tee "$DISPATCH_LOG" || {
    err "opencode dispatch failed for $DISPATCH_FEATURE_ID"
  }
elif command -v slimy-run &>/dev/null; then
  log "opencode not found. Falling back to slimy-run auto..."
  slimy-run auto 2>/dev/null || {
    err "slimy-run dispatch failed for $DISPATCH_FEATURE_ID"
  }
else
  log "Neither opencode nor slimy-run found. Manual dispatch required."
  log "  Feature: $DISPATCH_FEATURE_ID"
  log "  Project: $DISPATCH_PROJECT"
  log "  Prompt: $DISPATCH_PROMPT_FILE"
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

DISPATCH_WEBHOOK_URL="https://discord.com/api/webhooks/1490483635218944132/5IMm4_6okNjARRtwnf7SfAGV1IJDEzNGGOR4JWdkir8TWGGQLPq0B82rC1r876vRPRpj"
DISPATCH_REPORT_FILE=$(ls -t "$KB_SESSIONS_DIR"/report-*.json 2>/dev/null | head -1)
DISPATCH_REPORT_LINK=""
if [ -n "$DISPATCH_REPORT_FILE" ]; then
  DISPATCH_REPORT_LINK="$HARNESS_REPORT_BASE_URL/reports/sessions/$(basename "$DISPATCH_REPORT_FILE")"
fi
DISPATCH_MSG="Dispatched: $DISPATCH_FEATURE_ID in $DISPATCH_PROJECT [$DISPATCH_RISK]"
if [ -n "$DISPATCH_REPORT_LINK" ]; then
  DISPATCH_MSG="$DISPATCH_MSG
Report: $DISPATCH_REPORT_LINK"
else
  DISPATCH_MSG="$DISPATCH_MSG
Reports: $HARNESS_REPORT_BASE_URL/reports"
fi
curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" \
  -d "{\"content\":\"$DISPATCH_MSG\"}" "$DISPATCH_WEBHOOK_URL" 2>/dev/null || true

bash "$SEQUNCER_DIR/notify-blockers.sh" 2>&1 || true

  log "Done. Session $NEW_SESSIONS/$MAX_SESSIONS today."
  if [ -n "$SESSION_NAME" ]; then
    DISPATCH_RESULT="dispatched:$SESSION_NAME"
  else
    DISPATCH_RESULT="dispatched:foreground"
  fi
}

if [ "$LOOP_MODE" = "1" ]; then
  mkdir -p "$LOOP_LOG_DIR"
  loop_log "=== Harness loop started ==="

  while true; do
    if [ -f "$STOP_FILE" ]; then
      loop_log "Stop file detected. Exiting loop."
      loop_log "Exit reason: stopped"
      break
    fi

    loop_log "Starting dispatch iteration..."
    run_dispatch || true
    RESULT="${DISPATCH_RESULT:-error}"
    loop_log "Dispatch result: $RESULT"

    case "$RESULT" in
      stopped)
        loop_log "Exit reason: stopped"
        break
        ;;
      budget)
        loop_log "Exit reason: budget exhausted"
        break
        ;;
      no_work)
        loop_log "Exit reason: no available features"
        break
        ;;
      no_report)
        loop_log "No session report. Will retry on next iteration."
        sleep 60
        continue
        ;;
      error)
        loop_log "Exit reason: error"
        break
        ;;
      approval)
        loop_log "Exit reason: high-risk approval required"
        break
        ;;
      dry_run)
        loop_log "DRY RUN completed. Exiting loop."
        break
        ;;
    esac

    AGENT_SESSION=$(echo "$RESULT" | sed 's/dispatched://')
    if [ -z "$AGENT_SESSION" ] || [ "$AGENT_SESSION" = "foreground" ]; then
      loop_log "Agent ran in foreground (already completed). Continuing to next iteration."
      if [ -f "$SESSION_REPORT" ]; then
        loop_log "Running auto-close for foreground dispatch..."
        bash "$SEQUNCER_DIR/auto-close.sh" 2>&1 >> "${LOOP_LOG_DIR}/loop-$(date +%Y%m%d).log" || {
          loop_log "WARNING: auto-close.sh failed"
        }
      fi
      sleep 10
      continue
    fi

    loop_log "Waiting for agent session '$AGENT_SESSION' to finish..."
    while tmux has-session -t "$AGENT_SESSION" 2>/dev/null; do
      sleep 30
    done
    loop_log "Agent session '$AGENT_SESSION' finished."

    if [ -f "$SESSION_REPORT" ]; then
      loop_log "Running auto-close..."
      bash "$SEQUNCER_DIR/auto-close.sh" 2>&1 >> "${LOOP_LOG_DIR}/loop-$(date +%Y%m%d).log" || {
        loop_log "WARNING: auto-close.sh failed"
      }
    fi

    loop_log "Iteration complete. Checking for next dispatch..."
  done

  loop_log "=== Harness loop exited ==="
else
  run_dispatch || true
fi
