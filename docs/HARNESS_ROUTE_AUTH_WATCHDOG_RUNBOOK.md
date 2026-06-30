# Harness Route/Auth Watchdog Runbook

Status: manual/run-on-demand only. This runbook does not approve cron, timer,
systemd, tmux, Caddy, DNS, service restart, or Discord notification changes.

## When To Run

Run the watchdog after Harness report/auth work, before accepting a closeout
that depends on logged-out report blocking, or when checking that the manual
watchdog still agrees with the current live Harness routes.

Do not use this as a live scheduled monitor in this phase. Live scheduling
requires a separate operator-approved implementation with fresh proof.

## Manual Command

```bash
cd /home/slimy/slimy-harness
PROOF_DIR="/tmp/proof_harness_route_auth_watchdog_manual_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$PROOF_DIR"
chmod -R go-rwx "$PROOF_DIR" 2>/dev/null || true
sequencer/harness-route-auth-watchdog.sh --proof-dir "$PROOF_DIR/watchdog"
```

The script writes its result to:

```text
$PROOF_DIR/watchdog/RESULT.md
```

## Ops Dry-Run Preview

The ops registry entry is dry-run-only. These commands should print plans or
`WOULD_RUN` text and must not mutate cron, timers, services, or Discord:

```bash
ops/harness-ops schedule controls-validate
ops/harness-ops schedule plan harness-watchdog-cron
ops/harness-ops schedule dry-run harness-watchdog-cron --action enable
ops/harness-ops schedule dry-run harness-watchdog-cron --action disable
ops/harness-ops schedule run-once-dry-run harness-watchdog-cron
```

The run-once preview references:

```text
sequencer/harness-route-auth-watchdog.sh --proof-dir <proof_dir>/harness-watchdog-cron
```

That is a preview command, not a live schedule install.

## Result Meanings

`RESULT=PASS`: the watchdog accepted the owner gate, logged-out reports blocking,
dynamic report blocking, session index, archive-only behavior, report-label
semantics, and private-leak scan.

`RESULT=WARN`: at least one route or evidence check needs operator review. Do
not accept the dependent closeout until the WARN field is understood.

`RESULT=FAIL`: treat the phase as blocked. Preserve the proof directory and
inspect only the safe status fields in `RESULT.md`; do not expose cookies,
tickets, tokens, secrets, report bodies, or webhook values.

## Escalation

If the watchdog warns or fails, stop the closeout and keep the proof directory.
Escalate with the phase name, proof path, command run, and the non-secret status
fields from `RESULT.md`.

Do not repair failures by changing cron, timers, Caddy, DNS, services, tmux, or
notification wiring inside the watchdog phase. Those changes require a separate
explicit operator approval and proof plan.
