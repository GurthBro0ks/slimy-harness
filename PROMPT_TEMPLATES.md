# Agent Prompt Templates

Copy-paste these when starting agent sessions. Pick the right one for the repo.

---

## CODEX — slimy-monorepo

```
STARTUP (mandatory, do all 5 before any code):
1. cat claude-progress.md
2. cat feature_list.json | python3 -c "import json,sys; d=json.load(sys.stdin); incomplete=[f for f in d['features'] if not f['passes']]; [print(f'{f[\"id\"]}: {f[\"description\"]} [{f[\"priority\"]}]') for f in incomplete]"
3. git log --oneline -10
4. source init.sh
5. Pick the first incomplete CRITICAL feature. If all critical pass, pick highest-priority.

RULES:
- Work on ONE feature only.
- Run `pnpm lint` after every file change.
- Run `pnpm test:all` before marking anything as passing.
- Small commits: `git add -A && git commit -m "feat: <what you did>"`

SHUTDOWN (mandatory, do all 3 before ending):
1. Update feature_list.json — set "passes": true ONLY for features you verified.
2. Append a new entry to the TOP of claude-progress.md with: what you did, what broke, what's next.
3. git add -A && git commit -m "chore: session progress update"
```

---

## CODEX — pm_updown_bot_bundle

```
STARTUP (mandatory, do all 5 before any code):
1. cat claude-progress.md
2. cat feature_list.json | python3 -c "import json,sys; d=json.load(sys.stdin); incomplete=[f for f in d['features'] if not f['passes']]; [print(f'{f[\"id\"]}: {f[\"description\"]} [{f[\"priority\"]}]') for f in incomplete]"
3. git log --oneline -10
4. source init.sh
5. Pick the first incomplete CRITICAL feature.

RULES:
- Work on ONE feature only.
- Keep diffs small and surgical.
- NEVER touch .env*, secrets/, wallet/key/seed material.
- Run ./scripts/run_tests.sh before marking anything as passing.
- Do NOT auto-commit. Leave changes staged.

SHUTDOWN (mandatory, do all 3 before ending):
1. Update feature_list.json — set "passes": true ONLY for features verified by truth gate.
2. Append a new entry to the TOP of claude-progress.md.
3. Write a buglog entry under docs/buglog/ if you fixed a bug.
```

---

## CLAUDE CODE — Universal (works with any repo that has the harness files)

```
Read AGENTS.md first. Follow the startup sequence exactly.
Work on ONE incomplete feature from feature_list.json at a time.
Before ending this session:
- Update feature_list.json with pass/fail status
- Update claude-progress.md with what you did and what's next
- Commit with a descriptive message
```

---

## OPENCLAW / MINIMAX — Universal

```
You are working in a repo with structured agent harness files.

FIRST: Read these files in order:
1. AGENTS.md — your operating manual
2. claude-progress.md — what happened last session
3. feature_list.json — what needs to be done

THEN: Follow the startup sequence in AGENTS.md.
THEN: Work on the highest-priority incomplete feature.

BEFORE STOPPING: Update claude-progress.md and feature_list.json.
```
