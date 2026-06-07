# Tmux Inventory

This directory adds the Ops-5 read-only tmux inventory layer for the Slimy
Harness Ops Manager.

## Purpose

Inventory tmux sessions, windows, panes, sizes, current commands, active state,
 and working directories where tmux exposes them, without changing tmux state.

This pass does not:

- create sessions
- kill sessions, windows, or panes
- rename tmux objects
- attach or detach
- send keys
- resize panes
- capture pane contents by default

## Files

- `tmux-inventory.sh`
  - read-only tmux metadata inventory
  - redacts secret-looking values
  - inventories local tmux surfaces and optional shallow read-only NUC2 tmux
    visibility
- `validate-tmux.sh`
  - validates syntax, tool presence, mutation-scan safety, and no
    pane-content-capture behavior for the Ops-5 layer

## CLI

```bash
ops/harness-ops help
ops/harness-ops tmux inventory
ops/harness-ops tmux validate
```

Both tmux commands are read-only.

## Safety Notes

- Inventory uses metadata-only tmux commands such as `list-sessions`,
  `list-windows`, and `list-panes`.
- Pane scrollback/content is not captured by default.
- NUC2 inspection is optional and only attempted through existing safe SSH
  host `nuc2` when already configured.
- No Discord messages are sent by this layer.
