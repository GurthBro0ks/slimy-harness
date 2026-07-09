# Shared State Concurrency Guard

`/home/slimy/feature_list.json` is shared state. Interactive sessions must not hand-edit it directly.

Use `ops/feature-list-append-locked` for closeout-only feature entry writes after operator QA has passed. The helper:

- takes an exclusive `flock` for the full read/validate/write cycle
- parses JSON before writing
- rejects duplicate feature IDs before and after the append
- writes a temp file in the same directory, fsyncs it, and atomically replaces the target
- preserves either top-level list shape or top-level `{"features": [...]}` shape

Validate the live file without writing:

```bash
/home/slimy/slimy-harness/ops/feature-list-append-locked \
  --feature-list /home/slimy/feature_list.json \
  --validate-only
```

Append from an approved closeout entry:

```bash
/home/slimy/slimy-harness/ops/feature-list-append-locked \
  --feature-list /home/slimy/feature_list.json \
  --entry-json /path/to/approved-feature-entry.json
```

For tests, proof dirs, and dry runs, pass fixture paths with `--feature-list`, `--entry-json`, and optionally `--lock-file`.

Non-closeout sessions should write proposed state notes into their proof directory instead of changing shared files. Second-opinion sessions should produce corroboration notes/proof, not duplicate accepted feature entries.

`claude-progress.md` and `server-state.md` remain advisory Markdown state until a later broader helper exists. If a session's current context shows another session already wrote an entry for the same phase, merge or cross-reference rather than creating a near-duplicate entry.
