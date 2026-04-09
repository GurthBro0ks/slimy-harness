# SlimyAI Agent Harness System

## What This Is

This is a set of files you drop into each of your repos so that every Claude Code / Codex / OpenClaw session automatically:
- Knows what was done last time (no context loss)
- Knows exactly what to work on next (no manual steering)
- Follows the same standards (no quality drift)
- Leaves a clean trail for the next session (structured progress)

## How It Works (5-Minute Version)

Every agent session follows this loop:

```
START SESSION
  → Read AGENTS.md (short map, tells agent where everything is)
  → Read claude-progress.md (what happened last session)
  → Read feature_list.json (what's done, what's not)
  → Run init.sh (start dev environment)
  → Pick highest-priority incomplete feature
  → Work on ONE feature at a time
  → Test it end-to-end
  → Update feature_list.json (mark passes: true)
  → Update claude-progress.md
  → Git commit with descriptive message
END SESSION
```

## File Inventory

### Per-Repo Files (drop these in each repo root)

| File | Purpose |
|------|---------|
| `AGENTS.md` | Short map (~80 lines). Progressive disclosure — points to deeper docs, doesn't dump everything. |
| `feature_list.json` | Ground truth for what's built and what's not. JSON so agents treat it carefully. |
| `claude-progress.md` | Running log updated at end of every session. Survives context windows. |
| `init.sh` | One-command environment startup. Saves tokens every single session. |

### Why JSON for the Feature List

Models are empirically less likely to casually overwrite JSON than Markdown.
The rigid structure forces deliberate updates. Each feature has a `passes` field
that is either `true` or `false`. No ambiguity. No inference required.

## Installation

### slimy-monorepo
```bash
cp slimy-monorepo/AGENTS.md          /path/to/slimy-monorepo/AGENTS.md
cp slimy-monorepo/feature_list.json  /path/to/slimy-monorepo/feature_list.json
cp slimy-monorepo/claude-progress.md /path/to/slimy-monorepo/claude-progress.md
cp slimy-monorepo/init.sh            /path/to/slimy-monorepo/init.sh
chmod +x /path/to/slimy-monorepo/init.sh
```

### pm_updown_bot_bundle
```bash
# This REPLACES your existing AGENTS.md with an upgraded version
cp pm_updown_bot_bundle/AGENTS.md          /path/to/pm_updown_bot_bundle/AGENTS.md
cp pm_updown_bot_bundle/feature_list.json  /path/to/pm_updown_bot_bundle/feature_list.json
cp pm_updown_bot_bundle/claude-progress.md /path/to/pm_updown_bot_bundle/claude-progress.md
cp pm_updown_bot_bundle/init.sh            /path/to/pm_updown_bot_bundle/init.sh
chmod +x /path/to/pm_updown_bot_bundle/init.sh
```

## Codex-Specific Usage

When creating a Codex task, prepend this to the prompt:

```
Before starting work:
1. cat claude-progress.md
2. cat feature_list.json | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f['description']) for f in d['features'] if not f['passes']]"
3. source init.sh

Work on the first incomplete feature. When done:
4. Update feature_list.json (set passes: true for completed features)
5. Update claude-progress.md with what you did
6. git add -A && git commit -m "feat: <description>"
```

## Claude Code Usage

Add to your `.claude/settings.json` or system prompt:

```
Read AGENTS.md first. Follow the startup sequence. Work on one feature at a time.
Update claude-progress.md and feature_list.json before ending the session.
```

## OpenClaw / Other Agents

Same pattern — the files are agent-agnostic. Any agent that can read files and
run shell commands will benefit from this structure. The harness is the
environment, not the model.

## Maintaining the Harness

- **feature_list.json**: Add new features as you think of them. Never delete features — mark them `"deprecated": true` if obsolete.
- **claude-progress.md**: Don't edit old entries. It's append-only.
- **AGENTS.md**: Update when repo structure changes. Keep it under 100 lines.
- **init.sh**: Update when dev setup changes. Test it manually periodically.
