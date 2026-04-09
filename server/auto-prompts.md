# SlimyAI Server Harness — Auto Prompts
# 
# All prompts assume you're starting from /home/slimy/
# The agent reads the master harness, picks a project, and self-steers.


# ============================================================
# AUTO-WORK: Agent picks project + feature, fully autonomous
# ============================================================

MANDATORY STARTUP — do all 5 before writing any code:
1. cat /home/slimy/AGENTS.md
2. cat /home/slimy/claude-progress.md
3. python3 -c "
import json
d = json.load(open('/home/slimy/feature_list.json'))
incomplete = [f for f in d['features'] if not f['passes']]
for f in sorted(incomplete, key=lambda x: {'critical':0,'high':1,'medium':2,'low':3}.get(x['priority'],9)):
    print(f'{f[\"id\"]} [{f[\"project\"]}] [{f[\"priority\"]}] {f[\"description\"]}')
" 2>/dev/null || cat /home/slimy/feature_list.json
4. cat /home/slimy/server-state.md
5. source /home/slimy/init.sh

Pick the first CRITICAL incomplete feature across ALL projects.
cd into that project's directory. If it has its own init.sh, run it.
If it has its own AGENTS.md, read and follow its project-specific rules.
Work on that ONE feature only.

MANDATORY SHUTDOWN — do all 4 before ending:
1. Update /home/slimy/feature_list.json — set "passes": true ONLY for verified features
2. Prepend a new session entry to /home/slimy/claude-progress.md with: date, WHICH PROJECT, what you did, what broke, what's next
3. If you changed server state (services, packages), update /home/slimy/server-state.md
4. git commit in whatever project repo you worked in

Do not ask questions. Execute autonomously. Start now.


# ============================================================
# DIRECTED — You pick the project and task
# Replace [PROJECT] and [TASK] before pasting
# ============================================================

MANDATORY STARTUP:
1. cat /home/slimy/AGENTS.md
2. cat /home/slimy/claude-progress.md
3. source /home/slimy/init.sh

cd into the [PROJECT] repo (check server-state.md or AGENTS.md for path).
If it has its own AGENTS.md and init.sh, read and run them.

YOUR TASK: [TASK]

MANDATORY SHUTDOWN:
1. Update /home/slimy/claude-progress.md with what you did
2. Update /home/slimy/feature_list.json if relevant
3. git commit in the project repo

Execute autonomously. Start now.


# ============================================================
# FIX MODE — Find and repair breakage across any/all projects
# ============================================================

MANDATORY STARTUP:
1. cat /home/slimy/AGENTS.md
2. cat /home/slimy/claude-progress.md
3. source /home/slimy/init.sh

Something is broken. Your job:
1. cd into EACH project repo that exists (check server-state.md for paths)
2. Run that project's truth gate (lint/tests)
3. Identify all failures across all projects
4. Fix the most critical failures first, one at a time, smallest diffs
5. Re-run truth gate after each fix
6. Do NOT start new features

MANDATORY SHUTDOWN:
1. Update /home/slimy/claude-progress.md with what you fixed and where
2. Update /home/slimy/feature_list.json if any feature status changed
3. git commit in each project you touched

Execute autonomously. Start now.


# ============================================================
# HEALTH CHECK — Agent audits all projects, reports status
# No code changes, just information gathering
# ============================================================

MANDATORY STARTUP:
1. cat /home/slimy/AGENTS.md
2. cat /home/slimy/claude-progress.md
3. source /home/slimy/init.sh

Your job is STATUS REPORT ONLY. Do not change any code.

For EACH project found by init.sh:
1. cd into the project
2. git status and git log --oneline -5
3. Run the truth gate (lint/tests) and record pass/fail
4. Check if any services should be running (check server-state.md)
5. Note any obvious issues (uncommitted changes, failing tests, stale branches)

Then update /home/slimy/claude-progress.md with a full status report entry.
Update /home/slimy/feature_list.json with actual pass/fail status for features you could verify.
Update /home/slimy/server-state.md with current service/port info.

Do not make code changes. Report only. Start now.


# ============================================================
# CROSS-PROJECT TASK — Work that spans multiple repos
# Replace [DESCRIPTION] before pasting
# ============================================================

MANDATORY STARTUP:
1. cat /home/slimy/AGENTS.md
2. cat /home/slimy/claude-progress.md
3. source /home/slimy/init.sh

This task spans multiple projects: [DESCRIPTION]

Rules for cross-project work:
1. Work on the UPSTREAM project first (the one that produces data/APIs)
2. Run its truth gate and commit before moving to the next project
3. Then cd to the DOWNSTREAM project and integrate
4. Run that truth gate and commit
5. Update /home/slimy/feature_list.json for ALL affected features

MANDATORY SHUTDOWN:
1. Update /home/slimy/claude-progress.md — note ALL projects touched
2. Update /home/slimy/feature_list.json
3. git commit in EACH project you modified

Execute autonomously. Start now.


# ============================================================
# OPENCLAW / MINIMAX — Server-level auto-work
# More explicit instructions for non-Claude models
# ============================================================

You are an autonomous coding agent operating on a SlimyAI server.
The server hosts multiple code projects in different directories.

STEP 1 — Read these files and show their contents:
- /home/slimy/AGENTS.md (your operating manual — tells you where all projects are)
- /home/slimy/claude-progress.md (what happened in previous sessions)
- /home/slimy/feature_list.json (master list of what needs to be built across all projects)
- /home/slimy/server-state.md (which services are running, repo paths)

STEP 2 — Run this command:
source /home/slimy/init.sh

STEP 3 — From the feature list, find the highest-priority feature where "passes" is false.
Note which "project" field it belongs to. Navigate to that project's directory.
If the project has its own AGENTS.md file, read it for project-specific rules.
If the project has its own init.sh file, run it.

STEP 4 — Work on that ONE feature. Follow all rules from AGENTS.md.
Run tests and linting after every change.

STEP 5 — Before stopping, you MUST:
- Edit /home/slimy/feature_list.json: set "passes" to true ONLY for features you verified
- Edit /home/slimy/claude-progress.md: add a new entry at the TOP with date, which project, what you did, what's next
- Run: git add -A && git commit -m "feat: <description>" inside the project repo

Begin now. Do not ask questions.
