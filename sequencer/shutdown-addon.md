## SEQUENCER SHUTDOWN (do this LAST, after all other shutdown steps)

Write /home/slimy/session-report.json with this structure:
{
  "session_id": "[current ISO-8601 timestamp]",
  "agent": "[your agent type: claude-code, opencode, minimax]",
  "nuc": "[nuc1 or nuc2]",
  "project": "[repo you worked in]",
  "feature_id": "[feature ID from feature_list.json, or null if ad-hoc]",
  "prompt_type": "[which prompt type was used: A, B, C, C2, P, etc.]",
  "status": "[completed|partial|failed|blocked]",
  "summary": "[1-2 sentences: what you did]",
  "changes": ["list", "of", "files", "changed"],
  "tests": {
    "ran": [true|false],
    "passed": [true|false],
    "details": "[truth gate output summary]"
  },
  "blockers": [
    {"type": "manual|dependency|bug|question", "description": "...", "blocks_feature": "..."}
  ],
  "recommendation": {
    "next_feature_id": "[your suggestion or null]",
    "reasoning": "[why]",
    "risk_notes": "[any caution]"
  },
  "kb_learnings": ["anything worth capturing for the knowledge base"],
  "duration_minutes": [approximate session duration],
  "timestamp": "[current ISO-8601]"
}

Validate the JSON before writing:
python3 -c "import json; json.load(open('/home/slimy/session-report.json')); print('session-report.json: valid')"

### Blocker Reporting

If you encounter something you CANNOT complete because it requires
human action (manual testing, Discord verification, API key, phone
access, etc.), set status to "blocked" and fill the blockers array:

"blockers": [
  {
    "type": "manual",
    "description": "Needs manual Discord verification of /leaderboard command",
    "blocks_feature": "leaderboard-mysql-limit-fix-001"
  }
]

Do NOT set passes:true for blocked features. The sequencer will
handle blocker tracking and notify the human.
