#!/usr/bin/env bash
# ============================================================
# SlimyAI Harness — Auto Prompts
# ============================================================
# This file contains ready-to-paste prompts for Claude Code CLI
# and OpenClaw. Each prompt is fully self-contained.
#
# HOW TO USE:
#   1. cd into the repo you want to work on
#   2. Open Claude Code CLI or OpenClaw
#   3. Copy-paste the relevant prompt block below
#   4. Walk away — the agent handles startup, work, and shutdown
#
# ON NUC1 or NUC2:
#   Install first (one-time per repo):
#     cd /path/to/repo && bash /home/slimy/harness-kit/install.sh
# ============================================================


# ============================================================
# INSTALL PROMPT (run once per repo)
# Paste this into Claude Code CLI while inside a repo directory
# ============================================================

cat << 'INSTALL_PROMPT'
Run this command:
bash /home/slimy/harness-kit/install.sh

Show me the full output. If there are any errors, fix them.
Then read AGENTS.md and confirm the harness is installed correctly.
INSTALL_PROMPT


# ============================================================
# CLAUDE CODE — AUTO WORK (picks from feature list)
# Paste this as your first message. Agent self-steers.
# Works for ANY repo that has harness files installed.
# ============================================================

cat << 'CC_AUTO'
MANDATORY STARTUP — do all 5 before writing any code:
1. cat AGENTS.md
2. cat claude-progress.md
3. python3 -c "import json; d=json.load(open('feature_list.json')); [print(f'{f[\"id\"]}: [{f[\"priority\"]}] {f[\"description\"]}') for f in d['features'] if not f['passes']]" 2>/dev/null || cat feature_list.json
4. git log --oneline -10
5. source init.sh

Pick the first CRITICAL incomplete feature. If all critical pass, pick highest-priority.
Work on that ONE feature only. Follow the rules in AGENTS.md.

MANDATORY SHUTDOWN — do all 3 before ending:
1. Update feature_list.json — set "passes": true ONLY for features you verified with the truth gate
2. Prepend a new session entry to claude-progress.md with: date, what you did, what broke, what's next, git state
3. git add -A && git commit -m "feat: <concise description of what you did>"

Do not ask me questions. Execute autonomously. Start now.
CC_AUTO


# ============================================================
# CLAUDE CODE — DIRECTED TASK (you tell it what to do)
# Replace [YOUR TASK HERE] with your actual task.
# ============================================================

cat << 'CC_DIRECTED'
MANDATORY STARTUP — do all 4 before writing any code:
1. cat AGENTS.md
2. cat claude-progress.md
3. git log --oneline -10
4. source init.sh

YOUR TASK: [YOUR TASK HERE]

Follow the rules in AGENTS.md. When done:
1. Update claude-progress.md with what you did
2. If your task maps to a feature in feature_list.json, update its passes status
3. git add -A && git commit -m "feat: <description>"

Execute autonomously. Start now.
CC_DIRECTED


# ============================================================
# CLAUDE CODE — FIX/DEBUG MODE
# Agent reads progress, finds what's broken, fixes it.
# ============================================================

cat << 'CC_FIX'
MANDATORY STARTUP — do all 4 before writing any code:
1. cat AGENTS.md
2. cat claude-progress.md
3. git log --oneline -10
4. source init.sh

Something is broken. Your job:
1. Run the truth gate (tests/lint) and identify all failures
2. Read the most recent claude-progress.md entry for context
3. Fix failures one at a time, smallest diff possible
4. Re-run truth gate after each fix to confirm
5. Do NOT start new features — only fix what's broken

MANDATORY SHUTDOWN:
1. Update claude-progress.md with what you fixed
2. Update feature_list.json if any feature status changed
3. git add -A && git commit -m "fix: <what you fixed>"

Execute autonomously. Start now.
CC_FIX


# ============================================================
# CLAUDE CODE — REFACTOR MODE
# Agent cleans up code without changing behavior.
# ============================================================

cat << 'CC_REFACTOR'
MANDATORY STARTUP — do all 4 before writing any code:
1. cat AGENTS.md
2. cat claude-progress.md
3. git log --oneline -10
4. source init.sh

Your job is REFACTOR ONLY. Rules:
1. Run truth gate first — all tests must pass BEFORE you change anything
2. Make small, incremental refactors. Run truth gate after EACH change.
3. If truth gate fails after a change, revert it immediately: git checkout -- .
4. Zero behavior changes. Only structure, readability, dead code removal.
5. Stop after 3-5 refactors. Don't try to refactor everything.

MANDATORY SHUTDOWN:
1. Run truth gate one final time — must still pass
2. Update claude-progress.md with what you refactored
3. git add -A && git commit -m "refactor: <description>"

Execute autonomously. Start now.
CC_REFACTOR


# ============================================================
# CLAUDE CODE — ADD FEATURES TO TRACKING
# Give it a list of features, it adds them to feature_list.json
# ============================================================

cat << 'CC_ADD_FEATURES'
Read feature_list.json. Add these new features at the END of the features array.
NEVER remove or edit existing features. Use the next available id number.
Set all new features to "passes": false.

New features to add:
- [DESCRIBE FEATURE 1]
- [DESCRIBE FEATURE 2]
- [DESCRIBE FEATURE 3]

For each feature, write:
- A clear description (what the user sees/does)
- 3-5 verification steps
- A priority: critical, high, medium, or low

After editing, validate the JSON: python3 -c "import json; json.load(open('feature_list.json')); print('JSON valid')"

git add feature_list.json && git commit -m "chore: add new features to tracking"
CC_ADD_FEATURES


# ============================================================
# OPENCLAW / MINIMAX — AUTO WORK
# Same as Claude Code auto but more explicit for non-Claude models
# ============================================================

cat << 'OC_AUTO'
You are an autonomous coding agent. This repository has structured harness files that you MUST follow.

STEP 1 — READ THESE FILES (show contents):
- Read the file AGENTS.md (your operating manual)
- Read the file claude-progress.md (history of previous sessions)
- Read the file feature_list.json (what needs to be built)

STEP 2 — ORIENT:
- Run: git log --oneline -10
- Run: source init.sh
- Identify the highest-priority feature where "passes" is false

STEP 3 — WORK:
- Work on that ONE feature only
- Follow all rules described in AGENTS.md
- Run tests/lint after every change
- Keep changes small and focused

STEP 4 — SHUTDOWN (you MUST do this before stopping):
- Edit feature_list.json: set "passes" to true ONLY for features you fully verified
- Edit claude-progress.md: add a new entry at the TOP with today's date, what you did, what needs to happen next
- Run: git add -A && git commit -m "feat: <description>"

Begin now. Do not ask questions. Execute autonomously.
OC_AUTO


# ============================================================
# OPENCLAW / MINIMAX — DIRECTED TASK
# ============================================================

cat << 'OC_DIRECTED'
You are an autonomous coding agent. This repository has structured harness files.

STEP 1 — ORIENT (do this first):
- Read AGENTS.md
- Read claude-progress.md
- Run: git log --oneline -10
- Run: source init.sh

STEP 2 — YOUR TASK:
[YOUR TASK HERE]

STEP 3 — SHUTDOWN (mandatory):
- Edit claude-progress.md: add entry at TOP with what you did
- If relevant, update feature_list.json
- Run: git add -A && git commit -m "feat: <description>"

Begin now.
OC_DIRECTED


# ============================================================
# STATUS CHECK — paste into Claude chat (here) to get a summary
# First: cat claude-progress.md in your terminal, copy output
# Then paste this + the output into chat
# ============================================================

cat << 'STATUS_CHECK'
Here's my claude-progress.md from [REPO NAME]:

[PASTE CONTENTS HERE]

Give me:
1. A 3-sentence summary of current state
2. What the last session accomplished
3. The top 3 things that need to happen next
4. Any red flags or recurring issues you see in the log
STATUS_CHECK
