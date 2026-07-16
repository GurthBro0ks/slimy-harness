# Agent Notification Closeout

This runbook defines the explicit process boundary between Discord completion
notifications and NUC2 report-artifact synchronization.

## Safety contract

`sequencer/notify-proof-dir-complete.sh` has no implicit action. The caller
must choose exactly one mode:

| Mode | Discord | NUC2 sync | Required authorization |
|---|---:|---:|---|
| `discord-only` | yes | no | `--discord-authorized` |
| `sync-only` | no | yes | `--sync-authorized` |
| `both` | yes | yes | both authorization flags |

With no `--mode`, the adapter returns `STATE=NO_ACTION` and exits 64 before
creating a report, reading notification configuration, invoking a helper, or
writing a dedupe marker. Modes are never inferred from webhook availability,
hostname, relay configuration, or NUC2 availability.

Real external actions require direct owner approval. A mode flag describes the
requested process path; its corresponding authorization flag records that the
caller has the separate approval for that action. `--dry-run` is redacted
preflight only and performs no Discord transport, SSH, rsync, or marker write.

NUC1 owns and loads the Discord webhook at the latest possible point, inside
`notify-session-complete.sh`. NUC2 never receives webhook material.
`discord-only` never invokes the sync helper, SSH, rsync, SCP, or a NUC2 relay.
`sync-only` never loads the webhook environment or invokes the Discord notifier
or curl. `both` is explicit and records the two results separately.

## Exact-file sync allowlist

Sync modes require one or more `--sync-file PATH` arguments. The sync helper:

- accepts at most eight regular `.json` files;
- requires every file to be a direct child of the approved local sessions root;
- resolves and verifies real paths;
- rejects missing files, symlinks, directories, wildcards/globs, duplicates,
  duplicate destination basenames, invalid JSON, and paths outside the root;
- sends only the exact arguments to the fixed NUC2 sessions destination;
- does not discover a directory, recurse, use `--delete`, or log file content;
- logs only each basename and SHA-256 digest.

The normal allowlist is the exact report JSON and exact
`harness-session-index.json`. An unrelated third JSON file is not selected.

## Examples

Redacted Discord-only preflight:

```bash
bash sequencer/notify-proof-dir-complete.sh \
  --dry-run \
  --mode discord-only \
  --proof-dir /tmp/proof_example
```

Separately authorized Discord-only action:

```bash
bash sequencer/notify-proof-dir-complete.sh \
  --mode discord-only \
  --discord-authorized \
  --proof-dir /tmp/proof_example
```

Separately authorized exact-file sync:

```bash
bash sequencer/notify-proof-dir-complete.sh \
  --mode sync-only \
  --sync-authorized \
  --sync-file /home/slimy/slimy-kb/raw/sessions/report-proof-proof_example.json \
  --sync-file /home/slimy/slimy-kb/raw/sessions/harness-session-index.json \
  --proof-dir /tmp/proof_example
```

`both` uses the same exact allowlist plus `--discord-authorized`,
`--sync-authorized`, and `--mode both`. Selecting `both` never makes one action
a fallback for the other.

## Dedupe and results

Discord dedupe remains `sha256(absolute report path + mtime + size)` with
`<key>.sent` markers. Sync dedupe is independent: it hashes the fixed
destination plus the ordered canonical allowlist and content hashes, then uses
`<key>.sync-sent`. `--force` bypasses only Discord dedupe;
`--force-sync` bypasses only sync dedupe.

Every invocation reports:

```text
DISCORD_SENT=
DISCORD_RESULT=
NOTIFY_MODE=
DEDUPE_RESULT=
SYNC_ATTEMPTED=
SYNC_RESULT=
NUC2_ACCESSED=
REPORT_URL=
```

Stable states include `NO_ACTION`, `PREFLIGHT_OK`, `DISCORD_SENT`,
`DISCORD_DEDUPED`, `SYNC_COMPLETE`, `SYNC_DEDUPED`, `DISCORD_FAILED`,
`SYNC_FAILED`, `DISCORD_OK_SYNC_FAILED`, `SYNC_OK_DISCORD_FAILED`,
`REFUSED_UNAUTHORIZED_MODE`, and `REFUSED_INVALID_ALLOWLIST`.

Exit codes are 0 for complete/deduped/preflight, 64 for missing/invalid mode or
usage, 65 for an invalid allowlist, 69 for missing action authorization, 70 for
a Discord failure, 71 for a sync failure, and 72 for a mixed `both` result.

## Why this boundary exists

In July 2026, an authorized Discord-only closeout unexpectedly triggered an
undocumented full-directory NUC2 sync. The incident was disclosed as a real
process-boundary violation. This contract prevents recurrence by making both
actions explicit, independently authorized, exactly bounded, and testable with
process stubs.

Never print webhook URLs, dump environment files, store webhook material on
NUC2, or use raw webhook sends. If webhook material appears in output, stop and
request rotation without repeating the value.
