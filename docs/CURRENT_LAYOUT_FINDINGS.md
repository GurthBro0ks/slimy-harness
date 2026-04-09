# Current Layout Findings — 2026-04-09

## Source Locations Used

| File | Source | Destination in Repo |
|------|--------|---------------------|
| server-install.sh | /home/slimy/harness-kit/server-install.sh | /server-install.sh |
| install.sh | /home/slimy/harness-kit/install.sh | /install.sh |
| HARNESS_GUIDE.md | /home/slimy/harness-kit/HARNESS_GUIDE.md | /HARNESS_GUIDE.md |
| PROMPT_TEMPLATES.md | /home/slimy/harness-kit/PROMPT_TEMPLATES.md | /PROMPT_TEMPLATES.md |
| auto-prompts.sh | /home/slimy/harness-kit/auto-prompts.sh | /auto-prompts.sh |
| server/AGENTS.md | /home/slimy/AGENTS.md (LIVE — more current) | /server/AGENTS.md |
| server/init.sh | /home/slimy/init.sh (LIVE — more current) | /server/init.sh |
| server/QUALITY_CRITERIA.md | /home/slimy/QUALITY_CRITERIA.md (LIVE) | /server/QUALITY_CRITERIA.md |
| server/auto-prompts.md | /home/slimy/harness-kit/server/auto-prompts.md | /server/auto-prompts.md |
| per-repo/pm_updown_bot_bundle/ | /home/slimy/harness-kit/pm_updown_bot_bundle/ | /per-repo/pm_updown_bot_bundle/ |
| per-repo/slimy-monorepo/ | /home/slimy/harness-kit/slimy-monorepo/ | /per-repo/slimy-monorepo/ |

## Files NOT Copied (live state — must not be in git)

- `/home/slimy/claude-progress.md` — live operational session log
- `/home/slimy/feature_list.json` — live operational feature state
- `/home/slimy/server-state.md` — live operational service state
- `/home/slimy/sprint-contract.md` — ad-hoc session contract

## Files Created as Templates

- `server/templates/claude-progress.md` — blank template with session entry format
- `server/templates/feature_list.json` — minimal structure with empty features array
- `server/templates/server-state.md` — blank template with all sections
- `server/templates/PROJECT_NARRATIVE.md` — TODO-based placeholder

## Files That Did NOT Exist (created as placeholders)

- `PROJECT_NARRATIVE.md` — did not exist anywhere; template created

## Discrepancies Found

1. **Two AGENTS.md sources differ**: Live `/home/slimy/AGENTS.md` has 9-project map.
   harness-kit/server/AGENTS.md has only 3-project map. Used live version as source.

2. **Two init.sh differ**: Live uses `find /home/slimy -maxdepth 4 -name ".git"` (dynamic).
   harness-kit/server/init.sh hardcodes 3 repos. Used live version as source.

3. **No per-repo harness for mission-control** in harness-kit — only slimy-monorepo
   and pm_updown_bot_bundle have per-repo harness. Mission-control's AGENTS.md
   and init.sh would need to be sourced from live system if they exist.

4. **`{slimy-monorepo,pm_updown_bot_bundle,shared}` directory** is empty — ignore.

5. **Live server-state.md** (at /home/slimy/server-state.md) is more complete than
   the harness-kit template. Should be used as reference when writing the
   live-system server-state.md post-install.

## Missing Sources

- `/home/slimy/harness-kit/mission-control/` — does not exist (no per-repo harness)
- `PROJECT_NARRATIVE.md` — does not exist anywhere
- Live `/home/slimy/sprint-contract.md` — ad-hoc file, not part of harness
