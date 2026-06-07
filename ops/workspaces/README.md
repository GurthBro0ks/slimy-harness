# Workspace Planner

This directory adds the Ops-6A dry-run-only tmux workspace planner layer for
the Slimy Harness Ops Manager.

## Purpose

Provide read-only planning and dry-run previews for future tmux workspaces
without creating or mutating tmux sessions in this pass.

## Files

- `workspace-registry.json`
  - allowlisted workspaces and canonical session names
  - target machine, target paths, windows, and copy-only commands
  - `live_create_allowed=false` and `live_reuse_allowed=false` for all entries
- `workspace-plan.sh`
  - prints workspace metadata and copy-only command guidance
- `workspace-dry-run.sh`
  - prints exact future tmux commands as `WOULD_RUN:` previews only
- `validate-workspaces.sh`
  - validates syntax, registry JSON, target paths, and dry-run-only safety

## CLI

```bash
ops/harness-ops help
ops/harness-ops workspace plan <workspace>
ops/harness-ops workspace dry-run <workspace>
ops/harness-ops workspace validate
```

All workspace commands in Ops-6A are read-only.

## Safety Notes

- No `workspace create` command exists in this pass.
- No `workspace reuse` command exists in this pass.
- No tmux mutation commands are executed in this pass.
- Any tmux creation commands appear only as `WOULD_RUN:` preview text.
- Agent-start commands remain copy-only by default.
