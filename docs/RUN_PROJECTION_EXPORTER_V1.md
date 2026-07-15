# Run Projection Exporter — RW2-A isolated foundation

Status: isolated implementation candidate. Production use, lifecycle wiring,
source assembly, Habitat changes, reports, notifications, and Acceptance Ledger
calls are not implemented or authorized by this phase.

`ops/write-run-projection` writes one explicit fixture-only
`run-projection.v1` candidate and a bounded `run-projection-index.v1` beneath an
explicit, pre-existing, normalized, non-symlink directory below `/tmp`.
`/home/slimy/harness-logs/run-projections`, `/tmp` itself, relative paths,
non-`/tmp` paths, missing roots, and symlinked roots are refused.

## Commands

```text
ops/write-run-projection write --root /tmp/EXPLICIT_ROOT --input /tmp/candidate.json
ops/write-run-projection validate-store --root /tmp/EXPLICIT_ROOT [--format json]
```

There is no production-enable option, caller-controlled timestamp, directory
creation, scan-all/backfill, repair, quarantine, delete, notifier, network, or
ledger command.

## Safety contract

- Candidates must pass the accepted `run-projection.v1` validator and carry
  fixture-only, production-storage-disabled, production-acceptance-disabled
  flags plus an honest empty acceptance block.
- The writer assigns `generated_at`, `generated_by`, `source_machine`, and the
  canonical Workspace path. `integrity.digest` is SHA-256 of canonical JSON
  with that digest temporarily set to null.
- A root-wide regular no-follow lock serializes writers. The bounded wait is
  local only.
- Both pending files are same-directory, unique, mode 0640, fully written,
  fsynced, and validated before replacement.
- The run file is replaced and directory-fsynced before `index.json`. This
  prevents an index from pointing at a missing new detail.
- Run and index replacements are individually atomic, not falsely described as
  one transaction. A failure between them returns `RUN_VALID_INDEX_LKG`; retry
  repairs the index safely.
- All pre-run-rename failures leave prior run/index bytes unchanged. Invalid
  existing output blocks rather than being overwritten.
- The index is unique by RUN_ID, sorted by run creation time, and capped at 50.
  Older detail files are retained.
- Pending crash leftovers are reported by `validate-store` and never deleted or
  quarantined automatically.
- Secret-like values and sensitive artifact filenames fail before replacement.

This store is derived fixture data only. It is not a Run Record, proof, frozen
report, Acceptance Ledger, accepted-state source, or authorization mechanism.
