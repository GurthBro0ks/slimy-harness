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

### AGENTS.md protected section (SkillOpt intelligence layer)

`/home/slimy/AGENTS.md` is a **bounded skill** — agents may NOT silently
modify its content. The bottom of AGENTS.md is wrapped in
`PROTECTED_HARNESS_SECTION_START` / `PROTECTED_HARNESS_SECTION_END`
markers. The **Core Agent Discipline** section (Karpathy's 4 Rules) is
intentionally above the protected section so it stays visible.

**Rule:** You may append to `claude-progress.md` freely. You must NOT
modify content between `PROTECTED_HARNESS_SECTION` markers in
`AGENTS.md`. If you believe AGENTS.md needs a change, write your proposed
edit to `/home/slimy/proposed-agents-edits.json` instead using the
schema documented there. A human will run
`/home/slimy/slimy-harness/sequencer/consolidate-agents.sh` to review
and apply (or dismiss) proposals.

#### proposed-agents-edits.json schema

```json
{
  "version": 1,
  "proposals": [
    {
      "timestamp": "ISO8601",
      "session_id": "string",
      "feature_id": "string",
      "op": "append|insert_after|replace|delete",
      "target": "string (existing text if replace/delete, heading if insert_after)",
      "content": "string (new content)",
      "rationale": "string (why this improves agent behavior)"
    }
  ],
  "applied": [],
  "dismissed": []
}
```

- `op`:
  - `append` — append `content` to the bottom of the protected section
  - `insert_after` — insert `content` directly after the heading named in `target`
  - `replace` — replace the text in `target` with `content`
  - `delete` — delete the text in `target`
- `target` is matched as a **substring** (not a full string match) so
  you can refer to a few words or a full heading.
- All edits happen INSIDE the protected section. The Core Agent
  Discipline section and everything above it is **out of scope** for
  proposals.

This guarantees:
1. AGENTS.md content cannot be silently corrupted by a runaway agent
2. Every change is reviewed by a human before it lands
3. There is a paper trail (session_id + timestamp + rationale) for
   every accepted edit
4. The 4 Core Agent Discipline rules are non-negotiable and not
   subject to proposal review
