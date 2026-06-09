# Harness Ops Snapshot Producer Plan

PHASE=OPS-7E_HABITAT_OPS_SNAPSHOT_PRODUCER_PLAN

## Goal

Plan the producer that creates sanitized `/ops` `latest.json` for Habitat to read.

This phase is planning-only. No producer is implemented. No scheduling is added.
No cron, timers, tmux, services, Caddy, or DNS are changed.

## Baseline

- OPS-7B is closed and accepted (fixture-only `/ops` UI).
- OPS-7C planning is closed and accepted (snapshot adapter plan).
- OPS-7D read-only snapshot adapter is closed and accepted (commit `7b2694c`).
- Habitat `/ops` loads from `/home/slimy/harness-logs/ops-snapshots/latest.json`.
- Habitat `/ops` falls back safely when no snapshot exists.
- The adapter is file-read only: no `child_process`, no `exec`, no `spawn`.
- No backend mutation routes exist.
- No live controls exist.

## Producer Location

Decision: The producer belongs in `/home/slimy/slimy-harness/ops/` alongside the
existing ops scripts.

Rationale:

1. The producer gathers data from `ops/harness-ops` CLI outputs.
2. All `ops/` scripts are owned by the harness repo.
3. The harness repo already has the shared `redact_text()` sanitization logic.
4. Keeping the producer near the data sources simplifies path references and
   allows reusing existing redaction functions.

Proposed file:

```
/home/slimy/slimy-harness/ops/snapshot-producer.sh
```

Supporting file:

```
/home/slimy/slimy-harness/ops/snapshot-redact.sh
```

The producer should be callable as:

```bash
bash ops/snapshot-producer.sh [--dry-run] [--output-dir DIR]
```

Or via the CLI:

```bash
ops/harness-ops snapshot produce [--dry-run]
```

## Snapshot Output Path

Primary output:

```
/home/slimy/harness-logs/ops-snapshots/latest.json
```

History archive:

```
/home/slimy/harness-logs/ops-snapshots/history/YYYYMMDDTHHMMSSZ.json
```

Permissions:

- Directory: `drwxr-x--- slimy slimy` (0700 or 0750)
- latest.json: `-rw-r----- slimy slimy` (0640)
- History files: same as latest.json
- No world-readable permissions
- Producer creates directories if missing

Ownership:

- Runs as `slimy` user (same user that owns harness and Habitat)
- No sudo required

## Data Sources

The producer will call the following existing read-only/dry-run CLI commands
and capture their text output:

### Source Commands

| # | Command | Classification | Rationale |
|---|---------|---------------|-----------|
| 1 | `ops/harness-ops notify status` | READ_ONLY | Produces notification health summary with redacted env keys |
| 2 | `ops/harness-ops schedule inventory` | READ_ONLY | Produces schedule inventory with built-in redaction |
| 3 | `ops/harness-ops schedule validate` | READ_ONLY | Produces validation result |
| 4 | `ops/harness-ops schedule plan harness-watchdog-cron` | READ_ONLY | Produces plan for primary harness schedule target |
| 5 | `ops/harness-ops schedule dry-run harness-watchdog-cron --action enable` | DRY_RUN_ONLY | WOULD_RUN output only, no mutation |
| 6 | `ops/harness-ops schedule run-once-dry-run harness-watchdog-cron` | DRY_RUN_ONLY | WOULD_RUN output only, no mutation |
| 7 | `ops/harness-ops schedule controls-validate` | READ_ONLY | Validates the controls stack |
| 8 | `ops/harness-ops tmux inventory` | READ_ONLY | Produces session metadata inventory with built-in redaction |
| 9 | `ops/harness-ops tmux validate` | READ_ONLY | Validates the tmux layer |
| 10 | `ops/harness-ops workspace plan harness` | READ_ONLY | Produces workspace plan for primary workspace |
| 11 | `ops/harness-ops workspace dry-run harness` | DRY_RUN_ONLY | WOULD_RUN output only, no mutation |
| 12 | `ops/harness-ops workspace validate` | READ_ONLY | Validates the workspace layer |

### Classification Definitions

- **READ_ONLY**: The command reads state and produces output. It never mutates.
  Safe for the producer to call unconditionally.
- **DRY_RUN_ONLY**: The command prints `WOULD_RUN` preview lines. It never
  executes the previewed actions. Safe for the producer to call unconditionally.
- **FORBIDDEN_FOR_PRODUCER**: The command performs live mutation or is
  inappropriate for automated snapshot generation. The producer must never
  call these. Currently empty in this plan because all existing commands are
  read-only or dry-run.
- **FUTURE_ONLY**: Commands that do not exist yet but may be added in future
  phases. The producer must not call unknown commands.

### Future Command Guard

The producer will use an explicit allowlist of command strings. Any command
not on the allowlist will be skipped. This prevents accidental invocation of
future mutation commands.

Allowlist for phase OPS-7E/7F:

```
notify status
schedule inventory
schedule validate
schedule plan
schedule dry-run
schedule run-once-dry-run
schedule controls-validate
tmux inventory
tmux validate
workspace plan
workspace dry-run
workspace validate
```

## Output Parsing Strategy

Each CLI command produces YAML-like text output. The producer will:

1. Capture stdout and stderr separately.
2. Parse text output into structured sections using line-prefix heuristics.
3. Extract key-value pairs from `key: value` lines.
4. Extract multi-line blocks (entries separated by `---`).
5. Count entries where appropriate (schedules, sessions, etc.).
6. Build structured JSON sections matching the `OpsSnapshot` schema from OPS-7C.

The parser will be defensive:

- Missing commands produce an empty section with an error note, not a failure.
- Unparseable output produces an empty section with a raw-truncation note.
- No raw output is included verbatim; everything is structured and redacted.

## Sanitization

See `sanitization-rules.md` for the full redaction specification.

Summary:

1. **Redact webhook URLs**: Match Discord webhook URL patterns, replace with
   `[REDACTED_WEBHOOK]`.
2. **Redact bearer tokens**: Match `Bearer <token>` patterns, replace with
   `Bearer [REDACTED]`.
3. **Redact env secrets**: Match `SECRET=...`, `TOKEN=...`, `KEY=...`,
   `PASSWORD=...`, `WEBHOOK=...`, `COOKIE=...`, `SESSION=...` assignments,
   replace values with `[REDACTED]`.
4. **Redact embedded credentials in URLs**: Match `://user:pass@host`,
   replace with `://[REDACTED]@host`.
5. **Redact query-string secrets**: Match `?token=...&key=...` in URLs,
   replace values with `[REDACTED]`.
6. **Strip pane content/scrollback**: The tmux inventory scripts already skip
   pane content. The producer will not call `tmux capture-pane`.
7. **Strip raw log lines**: No raw harness log content will be included.
8. **Fail closed on redaction failure**: If the post-redaction scan still
   detects forbidden patterns, the producer must NOT write `latest.json`.
   It should write an error log and exit non-zero.

The producer reuses the existing `redact_text()` function from the harness
ops scripts. A shared `ops/snapshot-redact.sh` will centralize the redaction
logic so it is not duplicated further.

## Atomic Write

The producer will use the following write sequence:

1. Create output directory if missing: `mkdir -p /home/slimy/harness-logs/ops-snapshots/history/`
2. Generate full JSON in memory (bash variable or temp file).
3. Write to temp file: `/home/slimy/harness-logs/ops-snapshots/.latest.json.tmp`
4. Validate temp file:
   a. `jq . < tempfile` must succeed (valid JSON).
   b. Schema version must be `1`.
   c. Required top-level keys must exist.
5. Run post-write redaction scan on temp file.
6. If redaction scan fails: delete temp file, log error, exit non-zero.
7. Set permissions: `chmod 0640 tempfile`.
8. Atomic move: `mv tempfile latest.json`.
9. Optionally archive copy: `cp latest.json history/YYYYMMDDTHHMMSSZ.json`
10. Set permissions on archive: `chmod 0640 history/YYYYMMDDTHHMMSSZ.json`.

The `mv` is atomic on the same filesystem. The previous `latest.json` is
preserved until the new one is validated and moved into place. If any step
fails, the old `latest.json` (if any) remains untouched.

## Failure Behavior

| Failure | Behavior |
|---------|----------|
| Command not found | Log warning. Produce empty section with error note. Continue. |
| Command exits non-zero | Log warning. Produce empty section with exit code note. Continue. |
| Partial data from command | Parse what is available. Mark section as partial. Continue. |
| Invalid CLI output | Produce empty section with truncation note. Continue. |
| Redaction failure on section | Drop the section's raw content. Keep the section with a redaction_failed note. Continue. |
| Redaction failure on final JSON | Do NOT write latest.json. Log error. Exit non-zero. Old snapshot preserved. |
| Write failure (disk/permissions) | Log error. Exit non-zero. Old snapshot preserved. |
| Missing output directory | Create directory. If creation fails, log error and exit non-zero. |
| jq validation fails | Delete temp file. Log error. Exit non-zero. Old snapshot preserved. |
| All commands fail | Still write a minimal snapshot with empty sections and error metadata. Habitat can display this as degraded rather than missing. |

Key invariant: **the producer never deletes or corrupts an existing `latest.json`
on failure**. The atomic write sequence guarantees this.

## Schema Versioning

The snapshot JSON includes a `schemaVersion` field (currently `1`).

Versioning rules:

- Minor additions (new optional fields) do not increment the version.
- Breaking changes (removed fields, changed types) increment the version.
- The Habitat adapter (`harness-ops-snapshot.ts`) validates `schemaVersion` is
  exactly `1` using `z.literal(1)`.
- A future version bump requires coordinated changes to both the producer and
  the adapter in separate approved phases.

## Freshness Metadata

The producer writes the following freshness fields:

```json
{
  "generatedAt": "2026-06-09T00:30:00Z",
  "freshness": {
    "state": "fresh",
    "maxAgeSeconds": 900,
    "ageSeconds": null,
    "staleAfter": "2026-06-09T00:45:00Z",
    "message": "Snapshot generated at 2026-06-09T00:30:00Z. Stale after 15 minutes."
  }
}
```

The `ageSeconds` is null at generation time (computed by the consumer).
The `state` is always `fresh` at generation time (may become `stale` when read).

## History

Timestamped archive copies are written to:

```
/home/slimy/harness-logs/ops-snapshots/history/YYYYMMDDTHHMMSSZ.json
```

History behavior:

- One archive copy per producer run.
- No automatic pruning in this phase.
- Future phase may add pruning (e.g., keep last 24 or 48 snapshots).
- History files use the same permissions and schema as `latest.json`.

## Scheduling

**This phase does not add scheduling.**

Proposed scheduling progression:

1. **OPS-7F (implementation)**: Manual run only. Operator calls the producer
   explicitly after changes or before reviewing `/ops`.
2. **Future approved phase**: Scheduled producer via cron or systemd timer.
   Must be a separate approved phase with its own safety review.
3. **Frequency proposal**: Every 5-10 minutes if scheduled, matching the
   `maxAgeSeconds = 900` (15-minute freshness window).

No cron entry, no systemd timer, no tmux session, no auto-run mechanism
will be added in this phase or the implementation phase.

## Test Plan

See `SNAPSHOT_PRODUCER_TEST_PLAN.md` for the full test specification.

## Validation

See the validation section below for commands that verify the producer output.

## Non-Goals

- No live mutation through the producer.
- No scheduling in this phase.
- No Discord notification as part of snapshot generation.
- No pane content capture.
- No raw log inclusion.
- No backend mutation routes.
- No live controls.
- No shell execution in the Habitat web app path.

## Recommended Next Step

Implement OPS-7F: the manual-only sanitized snapshot producer script, with no
scheduling and no live controls. The producer will be runnable by the operator
or by an approved harness command, and will write the `latest.json` that the
Habitat `/ops` page already knows how to read.
