# Acceptance Ledger Historical Inventory and Backfill Plan

Status: read-only inventory and plan. No backfill was executed and no historical acceptance was rewritten.

## Read-only classification

| Classification | Existing-state observation | Iteration 2 treatment |
|---|---|---|
| Clear authority/evidence | Iteration 1 final closeout has owner QA, exact commits, proof/report, test results, and guarded push evidence | Candidate for a future explicit per-item backfill only; no entry generated now |
| Incomplete authority | Many legacy `feature_list.json` and progress items say accepted/passed without a canonical authority artifact and digest | Refuse automatic import |
| Incomplete evidence | Narrative/progress summaries may lack exact evidence manifests or final artifact digests | Refuse automatic import |
| Superseded | Iteration 1 report-repair WARN was followed by bounded deployment and accepted closeout | Preserve as history; do not synthesize ledger relationships from chronology |
| Ambiguous | Legacy truth is distributed across feature list, progress, reports, and proofs | Leave explicitly unaccepted until individually reconciled |
| Rejected | C13c is recorded excluded/blocked in accepted architecture evidence | Preserve the rejection evidence; do not reinterpret or import |
| Not acceptance-related | Server/service status, operational logs, and report indexes | Exclude from acceptance ledger |
| Excluded | Cache files, generated indexes, unrelated KB dirt, raw session context, and notification dedupe state | Never import as acceptance decisions |

## Future backfill plan

1. A separate owner-reviewed phase names a durable cut-over date and production ledger root.
2. The ledger starts empty; there is no bulk importer.
3. Each candidate is reviewed independently for exact subject, source run, evidence manifest/digest, authority artifact/digest, scope, limitations, unresolved state, and supersession.
4. Missing or ambiguous facts remain explicit and produce no acceptance entry.
5. A proposed entry is independently QA-reviewed before append.
6. Existing stores remain canonical until an explicit cut-over acceptance says otherwise; rollback is to stop trusting the additive ledger, not rewrite prior stores.
7. Backups and a cold restore one-query drill pass before any authoritative use.

BACKFILL_EXECUTED=no
HISTORICAL_ACCEPTANCE_REWRITTEN=no
