# Acceptance Ledger V1 — Isolated Foundation

Status: Iteration 2 implementation candidate. Independent QA and owner review are required before acceptance. Production acceptance remains disabled.

This document narrows the accepted `RUN_RECORD_AND_ACCEPTANCE_LEDGER_SPEC.md` to the smallest testable ledger mechanics. It does not choose production storage, authenticate owner identity, or activate a durable root.

## Storage decision

The implementation reuses Iteration 1's safest primitives as one logical ledger:

- explicit isolated root under `/tmp`; the production root is refused;
- one validating writer lock;
- immutable, sequence-named, newline-terminated canonical JSON entry files;
- exclusive pending files, file fsync, atomic hard-link claim, and directory fsync;
- detectable pending partials and explicit quarantine;
- no update or delete command.

This avoids torn canonical in-place JSONL appends. A bounded scan (default maximum 10,000 entries) validates global sequence and supersession and answers current state. SQLite remains the named future alternative if real volume demonstrates that bounded immutable-entry scans are insufficient.

`STORAGE_DECISION_SCOPE=iteration2_isolated_acceptance_ledger_only`

## Authority contract

Iteration 2 accepts only canonical synthetic authority artifacts with `authority_type=test_fixture`. The caller must supply the exact artifact, reference, scope, and sha256 digest. The artifact must state:

- `authority_authentication=TEST_FIXTURE_ONLY`;
- `production_authority_verification=NOT_IMPLEMENTED`;
- `production_acceptance_enabled=false`.

The ledger rejects missing authority, actor-only authority, actor/ref equality, type/ref/scope/digest mismatch, a fixture that is not yet effective, and an expired fixture. Supporting a real authority type requires a later reviewed verifier; adding a name to the namespace is not verification.

## Evidence contract

Every decision requires one or more canonical evidence manifests. Each manifest binds a stable evidence reference and closed type to the exact Iteration 1 run record, subject, validation summary, creation time, artifact path, and artifact sha256. Append and cold validation recompute the referenced artifact digest. Vague `latest` references, missing evidence, unsupported types, run/subject mismatch, and digest drift fail closed.

## Decision and supersession semantics

- `ACCEPTED`: evidence- and fixture-authority-bound accepted decision.
- `CONDITIONALLY_ACCEPTED`: same, with at least one explicit limitation.
- `REJECTED`: same provenance, with an explicit reason.
- `SUPERSEDED`: an explicit historical decision with a reason and exact predecessor.
- Any later decision for the same subject and scope must cite the exact current `acceptance_id` in `supersedes_acceptance_id`.
- The predecessor file never changes. A missing, future, cross-subject, cross-scope, or non-current predecessor fails closed.
- Exact replay of one `acceptance_id` and identical canonical content is `EXISTS_IDENTICAL`; changed content with that identity is refused.

Global `record_sequence` is assigned only while holding the writer lock. Filenames and content must agree with a contiguous sequence starting at one. Ordering never depends on timestamps or filenames alone.

## One bounded query

`current` requires exact subject type, subject id, and scope. In one bounded ledger read it returns:

- whether a current accepted state exists;
- exact subject and source run;
- current decision and acceptance id;
- evidence and authority provenance;
- limitations, unresolved items, reason, and predecessor;
- effective/recorded time and sequence;
- `production_acceptance_enabled=false`.

It distinguishes `NO_DECISION`, `REJECTED`, `CONDITIONALLY_ACCEPTED`, `ACCEPTED`, and `SUPERSEDED`. Corrupt, ambiguous, duplicate, gapped, excessive, or out-of-order ledgers fail rather than guessing. `history` returns the complete relevant chain only within explicit bounds.

## CLI

```text
ops/acceptance-ledger generate-id
ops/acceptance-ledger append --root /tmp/... --run-record /tmp/... [authority/evidence arguments]
ops/acceptance-ledger validate --root /tmp/... [--quarantine-partials]
ops/acceptance-ledger validate-entry ENTRY.jsonl
ops/acceptance-ledger current --root /tmp/... --subject-type repository --subject-id REPO@SHA --scope SCOPE
ops/acceptance-ledger history --root /tmp/... --subject-type repository --subject-id REPO@SHA --scope SCOPE
```

Outputs default to one JSON object for append/query operations; `--format text` provides key/value output. Missing authority/evidence, mismatch, collision, conflict, lock timeout, corruption, torn pending write, future schema, or bound violation exits nonzero. Ledger commands have no network or notifier path.

## Deferred production gates

Production remains disabled until a later owner-reviewed phase chooses durable storage and evidence retention, implements real authority verification and revocation, proves backup/restore, defines cut-over, independently audits the ledger, and explicitly authorizes activation. Habitat/Run Workspace remains read-only and unimplemented.
