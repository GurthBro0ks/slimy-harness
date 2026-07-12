# Run Record Creation v1

This is the bounded Growth Iteration 1 implementation note. It does not amend
the Constitution or accept the storage recommendation in the Run Record &
Acceptance Ledger specification.

## Decisions surfaced for owner review

- `RUN_ID` is `run_<UTC YYYYMMDDTHHMMSSffffffZ>_<128-bit random lowercase hex>`.
- The proposed NUC1 canonical root is `/home/slimy/harness-logs/run-records`.
  Tests and this implementation phase do not write to that live root.
- Storage is still **PROPOSED**: one canonical JSONL creation file per run, a
  locked writer, same-filesystem pending file, file `fsync`, atomic no-overwrite
  claim, directory `fsync`, and deterministic re-read validation.
- Exact byte-for-byte creation replay is an idempotent success. The same
  `RUN_ID` with any different canonical content is a collision and is refused.
- The store begins empty. Migration and backfill are deferred; no existing
  history is inferred or imported.
- Rollback is additive: stop invoking or trusting this store. Existing state
  sources remain authoritative until a later accepted cut-over.

## Boundary

`ops/run-record-create` provides `generate-id`, `create`, `validate`, and
`validate-store`. Creation records carry schema identity, subject identity,
project/repository identity, source machine and hostname, actor, authority
citation, and canonical UTC creation time. Actor and authority are separate.
The writer validates that an authority citation is present; grant resolution is
deferred because no authority or acceptance ledger exists in this iteration.

Canonical records are never rewritten. A killed writer may leave only a
detectable file in `pending/`; `validate-store` fails closed on it, and the
explicit `--quarantine-partials` action moves it to `quarantine/`. Malformed or
digest-mismatched canonical records are reported and never repaired silently.

## QA and deferred gates

Automated tests cover generated identity shape/uniqueness, schema round-trip,
subject normalization and namespace refusal, missing authority refusal, exact
replay, conflicting and concurrent collision refusal, malformed/corrupt record
detection, and killed-mid-write quarantine.

The slice-level stranger test is: provide only the store root to a cold process,
run `validate-store`, and read the canonical record. The minimal owner walk-
through is: create in an isolated root, validate it, inspect its identities,
retry the exact request, then attempt a conflict.

Deferred to later iterations: acceptance ledger and one-query acceptance test,
proof-retention policy and historical proof archival, acceptance migration and
backfill, projection/auth routes and iPhone projection QA, Habitat mutation,
NUC2 record residency, autonomous execution, notifications, and a general event
bus. The known `pending_post_edit_owner_review` status line in
`docs/CONSTITUTION.md` is preserved unchanged.
