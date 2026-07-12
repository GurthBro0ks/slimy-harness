# Run Record & Acceptance Ledger Specification

**Document status:** SPECIFICATION DRAFT, `pending_post_edit_owner_review`.
**Implementation authorization:** NONE. This document defines; it does not build.
No schema, storage, route, service, or migration exists or is created by this
document. Implementation may begin only when every entry criterion in §J holds
and the owner authorizes it separately.

**Derives from:** [CONSTITUTION.md](CONSTITUTION.md). Traceability is noted per
section as `[Dn]`. This is the merged Iteration-1 + Iteration-2 specification
recommended by sHAB-002: the run record and the acceptance ledger are specified
together because the terminal-freeze / acceptance-pointer interface between them
is exactly where separately drafted specs would drift.

**Design stance (ratified direction):** one append-only transition log per run
plus one acceptance ledger with a locked single writer. **No general event bus in
the first implementation.** The transition log *is* the event log any future
consumer would tail; promotion to in-process event dispatch happens only when two
or more independent, implemented consumers need to react to transitions without
polling.

---

## A. Canonical identities `[D5, D8]`

Every identity below is assigned at creation and immutable thereafter. Identity
is never derived from content, title, or state — resemblance is not identity.

| Identity | Meaning | Rules |
|---|---|---|
| `RUN_ID` | One execution of one phase | Immutable, globally unique, assigned at creation (opaque unique suffix, e.g. timestamp + random component — exact format is an entry-criteria decision). Never reused, never renamed. Two runs with the same phase name are two runs (the C12 lesson). |
| `SUBJECT_ID` + `SUBJECT_TYPE` | What an acceptance is about | Closed initial namespace: `run`, `feature`, `policy`, `waiver`, `document`, `deviation`. Extending the namespace is an L2 supersession, not an ad-hoc string. A subject's identity is independent of its state. |
| `PROJECT_ID` | The project a run belongs to | Stable slug (e.g. `slimy-harness`, `slimy-monorepo`). |
| `REPOSITORY` | Code identity | Filesystem path + remote URL + HEAD SHA at run start; HEAD SHA again at evidence capture. |
| `MACHINE` | Where the run executed | `nuc1` \| `nuc2` + hostname. Required because evidence roots exist per machine. |
| `ACTOR` | Who/what executed | Model or agent or human identifier (e.g. `claude-fable-5`, `codex-gpt5`, `owner`). The actor field never confers authority (§F). |
| `AUTHORITY` | The grant under which a state-changing step happened | A citation, not a name: nonce id, owner QA record reference, or standing policy §ref. Distinct field from `ACTOR`, always. |
| `ATTEMPT_ID` | One attempt within a run's lineage | Carries `parent_run_id` / `continues_run_id` links. A retry or continuation is a new attempt with an explicit link — similarity between outputs never establishes continuity; only the recorded link does. |
| `ACCEPTANCE_ID` | One acceptance ledger entry | Immutable; the referent for supersession and currency queries. |

## B. Run lifecycle `[D2, D4]`

Closed vocabulary — states are not added without demonstrated need (adding one is
an L2 supersession of this spec):

`CREATED → AUTHORIZED → ACTIVE → (INTERRUPTED ↔ ACTIVE) → EVIDENCED → REVIEWED →
RECOMMENDED → CONDITIONALLY_ACCEPTED | ACCEPTED | REJECTED`, with
`SUPERSEDED`, `FAILED`, and `CANCELLED` as additional terminals.

Five state axes are recorded separately and never conflated:

| Axis | Lives in | Examples |
|---|---|---|
| Run execution state | Run record | `ACTIVE`, `INTERRUPTED`, `FAILED`, `CANCELLED` |
| Evidence state | Run record fields | proof dir present, digests captured, mirror status |
| Review state | Run record fields | validation results, operator QA status |
| Acceptance state | **Acceptance ledger only** | `ACCEPTED`, `CONDITIONALLY_ACCEPTED`, `REJECTED`, `SUPERSEDED` |
| Notification state | Run record fields | sent/not-sent, dedupe result, report URL |

A run being `EVIDENCED` or `REVIEWED` says nothing about acceptance; acceptance
exists only as a ledger entry (D2: doing ≠ done). `INTERRUPTED` is a first-class,
explicit state — an interrupted run is never silently treated as failed or
complete (D4).

## C. Append-only transition model `[D4, D5]`

- **No general event bus.** One append-only transition log per run record;
  ledger appends form their own single ordered log. Nothing subscribes; readers
  read.
- **Append-only:** transitions are never edited or deleted. Current state is a
  projection of the log (last valid transition per axis).
- **Idempotent append contract:** every transition carries a deterministic
  transition identity (`RUN_ID` + sequence number + type + payload digest). An
  append that would duplicate an existing transition identity is a no-op that
  reports success. Retried closeouts and duplicate concurrent runs must not
  double-append (the dedupe-marker pattern is the estate's proven precedent).
- **Ordering:** per-record monotonic sequence numbers, assigned by the writer;
  wall-clock timestamps are recorded but never trusted for ordering. Ledger
  append order is global order for acceptance (single writer).
- **Duplicate prevention:** a second claimant of an existing `RUN_ID` fails
  closed — it is refused and must create a new run with a continuation link; it
  never merges into or overwrites the first.
- **Terminal freeze:** once a terminal state (`ACCEPTED`, `REJECTED`,
  `SUPERSEDED`, `FAILED`, `CANCELLED`) is appended, the record is frozen. The
  only legal subsequent appends are annotation entries (adding information) and
  supersession pointers; no append may change what was true.
- **Correction/supersession:** errors are corrected by appending a new entry that
  references what it corrects and why. Rewriting history is never legal, even for
  genuine mistakes (D5).
- **Partial-write recovery:** the write contract must make a torn append
  detectable (e.g. length/digest framing or write-then-atomic-rename — mechanism
  chosen at implementation). On recovery, a detected partial trailing entry is
  quarantined and recorded as an explicit anomaly — never silently dropped or
  silently completed (D4).
- **Schema versioning:** every record, transition, and ledger entry carries a
  `v:` schema-version field from the first write. Version bumps are recorded
  supersessions of this spec.

## D. Acceptance ledger `[D1, D2, D8]`

The ledger is the primary product: the single home of accepted state. Every entry
must answer, in one bounded query (the **one-query test**, §J):

1. What subject was accepted? (`SUBJECT_TYPE` + `SUBJECT_ID`)
2. Under which scope? (declared scope string of the accepted claim)
3. Based on which evidence? (evidence references + digests, §E)
4. Under which authority? (authority citation, §F)
5. With which limitations? (explicit conditions/waivers; empty means none)
6. What did it supersede? (prior `ACCEPTANCE_ID` or none)
7. What remains unresolved? (explicit unknowns carried, e.g. "C13c excluded")
8. When did it become effective? (timestamp + effective condition if conditional)
9. Is it still current? (derivable: current unless a later entry supersedes it)

Schema rider (constitutional): **no acceptance without subject + evidence +
authority.** An entry missing any of the three is invalid and must be refused by
the writer. "The system feels healthy" is not an acceptance.

Existing stores (feature list, snapshots, progress log) become projections or
inputs of the ledger over time; the cut-over rule is in §J. The ledger starts at
cut-over and backfills per item, explicitly, if ever — it never bulk-imports
assumed history.

## E. Evidence references `[D1, D7]`

Each ledger entry and evidenced run record carries:

- **Durable proof location** — the proof directory under the durable evidence
  root. The root itself is an entry-criteria decision (§J); `/tmp` is boot-wiped
  and is not durable. Until cut-over, `/tmp` paths remain what they are:
  historical pointers, recorded as such.
- **Digest/integrity reference** — sha256 (or equivalent) of the evidence
  artifacts, captured **after the final amend** of the evidence (the C13c/G12
  lesson: a digest taken before the last edit certifies nothing).
- **Validation summary** — what gates ran, results, and what could not run
  (WARN, explicitly).
- **Operator QA** — the owner/operator QA record or its pending status.
- **Secret-scan result** — pass/fail of the scoped scan over evidence and diffs.
- **Git state** — repo, branch, HEAD before/after, diff status.
- **Report URL** — the protected report projection, if generated.
- **Notification result** — sent/not-sent, dedupe key result.
- **Retention/redaction (by contract):** all records, evidence, and projections
  pass the existing redaction and secret-scan discipline **before** render or
  notify. Webhook URLs and secrets are never stored in records, evidence,
  transitions, or ledger entries — on any machine. Retention: evidence referenced
  by a current or superseded acceptance is never deleted; unreferenced evidence
  follows the (separate) evidence-root retention policy.

## F. Authority `[D3]`

- Authority is always a **citation to a grant**, never an inference from
  capability or actor identity. `ACTOR` and `AUTHORITY` are separate fields in
  every record, always.
- **Owner-authorized grants:** explicit, recorded, revocable. Grants may be
  per-crossing (a nonce, an owner QA record) or **standing policies** (cited by
  stable §ref). Standing grants are still explicit and revocable — a standing
  grant is not silence.
- **Revocation and expiry:** grants may carry expiry; revocation is an appended
  record that takes effect at append time. Acceptances made under a later-revoked
  grant remain valid history (revocation is not retroactive rewriting) but are
  flagged queryable.
- **Emergency provisional actions:** an action taken beyond recorded authority to
  prevent harm is recorded immediately as `provisional`, and must be either
  owner-ratified retroactively or reversed; a provisional entry that ages without
  ratification stays visibly provisional forever (D4 — it never ripens into
  authority).
- **Delegated roles:** delegation is itself a recorded grant rooted in an
  accountable human. A delegate's acceptances cite the delegation.
- **No self-granted authority:** no writer may create, widen, or reinterpret the
  authority under which it writes. This is protected-floor (Constitution) and the
  ledger writer must refuse entries whose authority citation cannot be resolved
  to an existing recorded grant.

## G. Recovery `[D4, D7]`

- **Acceptance survives reboot:** the ledger and run records live on persistent
  storage under the durable evidence root, covered by the existing backup posture
  (slimy-backup-pull timer; coverage confirmed at entry criteria).
- **Interrupted runs are reconstructable:** the run record alone (stage, next
  gate, blockers, links) must let a cold agent continue or close out the run —
  the **stranger test** (§J).
- **Ambiguity stays explicit:** reconstruction never guesses. What cannot be
  determined from the record is recorded as unknown; unknowns never default to
  the happy path.
- **Duplicates and collisions fail closed:** `RUN_ID` collision refuses the
  second writer (§C); ambiguous recovery states block with reasons rather than
  auto-resolving.
- **Serialization:** one locked, validating writer per store (the proven
  `feature-list-append-locked` pattern). No global lock is needed at birth; the
  run's own record has exactly one writer — the run.
- **Backup and restore:** restore expectations are part of entry criteria; a
  restore drill (read a backed-up ledger on a clean machine and answer the
  one-query test) is a named QA step before the ledger becomes authoritative.

## H. Machine boundary `[D6]`

- **NUC1** is the production/public edge and the sole owner of the Discord
  webhook secret.
- **NUC2 must never store, read, or print the webhook URL.** No record, evidence
  file, transition, or projection may contain it — on either machine.
- NUC2-originated notifications **relay through NUC1** via the governed notifier
  path; the relay result is what NUC2 records.
- Every record preserves **source machine and execution environment identity**
  (§A `MACHINE`), because evidence roots and capabilities are per-machine.
- **Record residency at birth:** canonical records and the ledger live on NUC1.
  NUC2 phases proof-relay as today; NUC2-resident records are an explicitly
  deferred decision, to be made when a real NUC2-resident run needs one.

## I. Projection boundary `[D6, D8]`

- The Habitat / Run Workspace is a **read-only projection** initially. Reports
  are projections; **projections are never canonical truth** — the record and
  ledger are.
- Raw JSON / debug views remain **owner-gated**.
- **No dashboard mutation API** exists in this phase; nothing in the workspace
  writes to records or the ledger.
- **Logged-out users must never see report or record content.** The existing
  owner-gate on `harness.slimyai.xyz/reports/...` is the floor; every future
  projection route inherits it.

## J. First implementation entry criteria

Implementation of any part of this spec may begin only when ALL of the following
hold, each recorded as a one-line owner decision or a checkable fact:

- [ ] **Schema reviewed** — both schemas (run record, ledger entry) with `v:`
      fields, reviewed by the owner against §A–§F.
- [ ] **Storage choice justified** — engine chosen with evidence at
      implementation time. **PROPOSED (not accepted):** append-only JSONL files
      with one locked validating writer per store — the estate has this pattern
      proven (`feature-list-append-locked`), it is greppable, git-backupable, and
      needs no new runtime. SQLite is the named alternative if bounded queries
      (§D) prove impractical over JSONL at real volume. This paragraph is a
      recommendation, not a decision.
- [ ] **Migration/backfill plan** — cut-over date; ledger starts empty;
      per-item explicit backfill only; existing stores become projections on a
      stated schedule.
- [ ] **Proof retention decision** — durable evidence root named (one sentence),
      `/tmp` precedence rule stated, bulk archive of existing proof dirs
      executed and verified (additive, count+hash checked, nothing deleted).
- [ ] **Namespace decision** — subject namespace (§A) confirmed or amended by
      the owner.
- [ ] **Collision tests** — automated tests for `RUN_ID` collision refusal and
      idempotent re-append (§C) written into the implementation plan.
- [ ] **Interrupted-closeout atomicity test** — a closeout killed mid-write
      leaves a detectable, quarantinable partial entry and a reconstructable
      record; named QA test.
- [ ] **Auth/owner-gate review** — projection routes reviewed against §I;
      logged-out access verified blocked.
- [ ] **NUC1/NUC2 boundary review** — §H verified against the implementation
      plan; no webhook material outside NUC1.
- [ ] **Rollback plan** — how the estate operates if the ledger is wrong or
      corrupted (fall back to existing stores; ledger is additive until
      cut-over, so rollback is "stop trusting it," not "restore the world").
- [ ] **Operator QA plan** — named tests: the **stranger test** (cold agent
      continues a run from the record alone), the **one-query test** (§D, all
      nine questions from one bounded query), the **interrupted-closeout test**
      (above), and the **iPhone walk-through** (owner follows one run live →
      evidenced → accepted on a phone, logged-in; logged-out blocked).

## What this spec deliberately does not include

A general event bus, subscriptions, or dispatch; projection-rebuild tooling; a
dashboard mutation API; cross-machine clock synchronization; a formal owner
identity system; NUC2 record residency; any storage engine decision. Each is
either deferred behind a named trigger or explicitly out of scope until a
demonstrated engineering failure justifies it.
