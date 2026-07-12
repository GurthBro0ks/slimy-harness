# The Slimy Harness Constitution

**Document status:** Methodology and invariant direction RATIFIED by explicit owner
decision, 2026-07-12. This reconciled text is `pending_post_edit_owner_review`
(the owner reviews this document; a separate closeout records that QA).

**Implementation authorization:** NONE. Ratifying this Constitution implements
nothing. Every organ it implies (run identity, durable evidence root, acceptance
ledger, workspace) remains unbuilt until a specification passes its own entry
criteria and the owner authorizes implementation separately.

**Supersession:** This document changes only by owner ratification, recorded as an
explicit supersession entry. It supersedes the unratified draft
`proof_shab001_ecosystem_genesis_20260711T163703Z/DNA.md` as the canonical home of
the invariants; that draft and all prior packages are preserved as history.

---

## What this document is

This is the single durable architecture anchor of the Slimy Harness. It holds the
smallest set of invariants that make autonomous work trustworthy, and nothing
else. Engineering detail lives in specifications; current truth lives in the
accepted-state ledger; lessons live in the knowledge base. If a rule is not an
invariant, it does not belong here.

## The methodology

The whole methodology is five artifacts in one line:

```
Constitution (≤8 durable invariants)
    ↓
Engineering Specifications / ADR-style decisions
    ↓
Implementation
    ↓
Durable Evidence
    ↓
Accepted-State Ledger
    ↓
Observation and proposed improvement (feeds back to the top)
```

There are no other layers. No scientific-method track, no natural-laws layer, no
field journal, no research track. Falsification is a phase type (adversarial
review, QA separation), not a document tree.

### The evolution rule

Change happens through one loop:

> **observe → challenge → simplify → ratify → specify → implement → observe**

Observations and proposals ride the run record and closeout. In-scope, reversible
improvements may simply be done and evidenced; anything standing, policy-shaped,
or binding on others is proposed and ratified before it takes effect; anything
ambiguous is out of scope (fail closed). New methodology layers may be added only
to prevent a demonstrated engineering failure — never speculatively.

## The eight invariants

1. **D1 — Evidence before belief.** No claim enters accepted state without a
   persistent, inspectable evidence artifact. Acceptance binds to evidenced
   provenance, never to resemblance: an artifact that merely looks like the
   accepted one is not the accepted one. *Violation looks like:* accepting a
   rebased commit because its diff matches the reviewed one (the C13c refusal).

2. **D2 — Acceptance is explicit and separate from execution.** Doing is not
   done; the builder is not the judge. Every acceptance has an identified
   referent — a named subject, specific evidence, and a specific authority.
   Evidence and authority are distinct: proof that work is good is never, by
   itself, the authority to accept it as true. *Violation looks like:* the
   superseded v2 design where the builder marked its own work `passes: true`.

3. **D3 — Authority is owner-rooted and never self-granted.** Neither technical
   ability nor actor identity establishes authority. Autonomous work becomes
   trusted state only through an explicit, evidence-bearing, **owner-authorized**
   acceptance boundary (grants may be standing and delegated, but are always
   explicit, recorded, revocable, and rooted in an accountable human). The system
   may adapt its capabilities within existing authority; it may not create,
   enlarge, or reinterpret its own authority. *Violation looks like:* the
   injection incident — replayable text treated as authorization.

4. **D4 — Fail closed.** Ambiguity or missing evidence yields no action and no
   acceptance — never best-effort acceptance. Unresolved uncertainty remains
   explicit and recorded; it never silently becomes certainty. *Violation looks
   like:* drift — a stale snapshot or unrecorded state change quietly treated as
   current truth.

5. **D5 — History is append-only; truth changes only by recorded supersession.**
   Identity and state are distinct: every subject and every run has an identity
   independent of its current state, so supersession targets a stable identity
   without rewriting history. *Violation looks like:* the C12 duplicate
   concurrent runs, where identity-by-name collapsed under two runs with the
   same title.

6. **D6 — Capabilities are confined to their minimum boundary.** Secrets and
   dangerous capabilities live at the smallest machine and process scope that can
   do the job. *Violation looks like:* the Discord webhook URL existing anywhere
   on NUC2.

7. **D7 — Recoverability from the record alone.** A cold agent — or a stranger —
   must be able to continue or evaluate any work from persisted state, without
   access to the session that produced it. *Violation looks like:* a methodology
   that exists only inside one model's session logs.

8. **D8 — Explainability of every accepted transition.** "Is X accepted, by which
   evidence, under whose authority, and is it still current?" must be answerable
   from one bounded query, forever. *Violation looks like:* today's estate, where
   answering that question means grepping six hand-maintained files.

## The protected floor

No autonomy level, profile, or learned behavior ever includes: secrets, `.env`,
or webhook access; production configuration (Caddy, DNS, cron, systemd, tmux);
destructive git on shared branches; canonical database schema or data; external
sends outside the governed notifier; deleting or altering proof, ledger, or
dedupe artifacts; or modifying this Constitution, its gates, prompts, fitness
definitions, or its own authorization — including as a side effect of learning.

## Change authority

| Layer | What | Change mechanism |
|---|---|---|
| L3 | Implementation | Normal run + QA; the gates catch bad implementation |
| L2 | Policy / specifications | Recorded supersession by the owner or an owner-delegated rule |
| L1 | This Constitution and the protected floor | Owner ratification only, ever |

## What must never become constitutional

Vendors, models, machines, hostnames, topologies, file paths, formats, tools,
UIs, channels, performance targets, the sHAB codename, any org structure, and any
learned behavior. These are all current choices, not invariants; canonizing them
would make the true invariants less believable and the system less able to
change. Learning may propose policy; only owner ratification amends this
document.

## Explanatory note (optional lens, not canon)

**sHAB** is an internal codename only. Biology and biotech vocabulary (organism,
genome, DNA, organs) may be used as an optional human-facing explanatory lens,
but it is never canonical terminology and never load-bearing. The canonical terms
are the ordinary engineering ones used above: Constitution, invariant,
specification, evidence, ledger, run record.

## Ratification and evidence

- **Owner decision (2026-07-12, recorded as owner QA PASS):** keep this
  Constitution as the single durable anchor; merge surviving law concepts into it
  as concise invariants; keep the trust-conversion loop with "owner-authorized"
  wording; create no SCI/LAW/BIO/Research/Field-Journal document trees; add no
  methodology layers without a demonstrated engineering failure; next durable
  document is the Run Record & Acceptance Ledger Specification; no runtime
  implementation authorized.
- **Evidence lineage:** Fable architecture & identity challenge (2026-07-11
  15:00Z) → sHAB-001 Ecosystem Genesis (16:37Z, D1–D8 draft) → sHAB-002
  acceptance-boundary ratification (17:02Z) → Fable scientific-methodology peer
  review (2026-07-12 14:15Z) → this ratification
  (`proof_shab_lean_methodology_ratification_core_record_spec_20260712T155040Z`).
- **First specification under this Constitution:**
  [RUN_RECORD_AND_ACCEPTANCE_LEDGER_SPEC.md](RUN_RECORD_AND_ACCEPTANCE_LEDGER_SPEC.md).
