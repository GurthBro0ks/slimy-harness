# Mission-Control Availability Runbook

## Purpose

This runbook covers Mission-Control availability incidents for Harness Reports at
`https://harness.slimyai.xyz/reports`.

Its job is to help the operator distinguish:

- healthy owner-gated login redirects;
- Mission-Control availability faults such as 502, timeout, or upstream
  unavailable;
- owner SSO/session failures;
- security incidents where logged-out users can see report content.

This runbook is documentation only. It does not authorize automatic recovery,
cron, systemd timer, Caddy, DNS, Discord, service environment, or secret
changes.

## Quick Classification

| Situation | Meaning | First action |
| --- | --- | --- |
| Logged-out `/reports`, `/reports/sessions`, or a dynamic report URL redirects to login or renders only the Harness Reports Access shell, with no report detail, JSON, or secret markers. | Healthy owner gate. | Run the watchdog and record PASS/WARN/FAIL. |
| Public Reports route returns 502, timeout, connection failure, or upstream unavailable while logged-out content remains protected. | Availability fault. | Capture route and service metadata. Do not restart until the operator approves. |
| Logged-out gates hold, but owner Habitat to Reports SSO loops or lands on the Reports login page. | SSO/session fault. | Diagnose the Habitat bridge, Mission-Control consume endpoint, verifier path, and report session handling. |
| Logged-out public route returns report detail markers, report JSON body markers, proof/session content, or raw secret markers. | Security incident. | Stop, mark FAIL, protect production first, and escalate for emergency route gating. |

## Baseline Guardrail

Run the accepted manual watchdog from NUC1:

```bash
cd /home/slimy/slimy-harness
PROOF_DIR="/tmp/proof_harness_reports_watchdog_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$PROOF_DIR"
chmod -R go-rwx "$PROOF_DIR" 2>/dev/null || true
sequencer/harness-route-auth-watchdog.sh --proof-dir "$PROOF_DIR/watchdog"
sed -n '1,160p' "$PROOF_DIR/watchdog/RESULT.md"
```

Interpretation:

- `PASS`: logged-out owner gates, dynamic report protection, session index,
  archive-only availability, report-label semantics, and private leak checks
  passed.
- `WARN`: a route, network, runtime, or validation check was inconclusive. Do
  not close out dependent work until the warning is understood.
- `FAIL`: possible protection or content-exposure problem. Stop and protect
  production first.

The watchdog performs no Discord notification delivery unless a separate phase
explicitly approves it, and it must not require a Discord webhook environment.

## Read-Only Diagnostics

Use marker-safe metadata checks only. Do not retain or expose full report
bodies.

### Git and accepted state

```bash
cd /home/slimy/slimy-harness
git status --short
git status -sb
git merge-base --is-ancestor 2363480 HEAD && echo "watchdog commit present"
git merge-base --is-ancestor 57fe18e HEAD && echo "watchdog runbook commit present"
```

```bash
cd /home/slimy/mission-control
git status --short
git status -sb
```

### NUC1 public route checks

From NUC1, check public Reports routes with a clean cookie jar and record only
status, final URL, redacted headers, and safe body markers.

Suggested routes:

- `https://harness.slimyai.xyz/reports`
- `https://harness.slimyai.xyz/reports/sessions`
- one known dynamic report detail URL

Healthy logged-out behavior is a redirect or access/login shell with no report
detail markers, no report JSON body markers, and no raw secret markers.

### Habitat and SSO bridge checks

If owner SSO fails but logged-out gates hold, inspect the bridge path without
printing cookies or tickets:

- Habitat `/reports/sso-bridge`;
- Mission-Control `/api/session/consume-sso`;
- GH Tracker SSO ticket verifier;
- report session acceptance by cookie name and boolean only, never by value.

On NUC1, `gh-tracker.service` may be relevant to the Habitat bridge/verifier
path:

```bash
systemctl --user status gh-tracker.service --no-pager
```

### NUC2 Mission-Control service checks

Mission-Control Reports rendering historically runs on NUC2 on port `3838`
behind the NUC1 public edge. On NUC1, `mission-control.service` may not exist;
that alone is not a failure.

On NUC2, use read-only checks:

```bash
systemctl --user status mission-control.service --no-pager
```

Local route and port checks should capture metadata only. Do not dump report
bodies.

### Source and layout checks

Source greps are allowed for route names and code shape:

```bash
cd /home/slimy/mission-control
grep -RInE 'consume-sso|sso-ticket|reports|Harness Reports Access|login|health|PORT|3838|requireOwnerReportAccess|slimy_session|habitat_session' \
  app lib src components scripts package.json 2>/dev/null | head -200
```

Do not read `.env*` files.

## Log Inspection Rules

Logs are read-only and must be redacted before storing or sharing.

Use bounded windows. Example on NUC2:

```bash
journalctl --user -u mission-control.service --since "30 minutes ago" --no-pager
```

Before sharing or saving output, redact:

- cookies;
- SSO tickets;
- session values;
- Authorization headers;
- webhook URLs;
- API keys;
- password hashes;
- report bodies;
- private proof paths if they expose sensitive content.

Record only route names, reason codes, status codes, booleans, timestamps, and
service state.

## Recovery Approval Gates

### Logged-out content exposure

If a logged-out public route exposes report content or raw secret markers:

1. Stop diagnostics that might spread content.
2. Mark `RESULT=FAIL`.
3. Do not send report content in Discord or any notification.
4. Protect production first with an emergency route gate or upstream block.
5. Do not restart blindly as the first action.

### Mission-Control down or 502

If public Reports are 502/down but logged-out content remains protected:

1. Capture public route metadata.
2. Capture NUC2 `mission-control.service` status.
3. Capture bounded redacted logs.
4. Run the watchdog if possible.
5. Ask for explicit operator approval before one manual
   `mission-control.service` restart on NUC2.

After an approved restart:

1. Rerun the watchdog.
2. Rerun public marker-safe route checks.
3. Confirm logged-out routes remain protected.
4. Require owner browser QA if Reports SSO or session behavior was affected.

### SSO/session failure

If logged-out gates hold but owner Habitat to Reports SSO fails:

1. Keep service running unless there is a separate availability fault.
2. Diagnose bridge, consume, verifier, and report session handling.
3. Do not restart blindly.
4. Do not expose cookie values, SSO ticket values, or auth values.
5. Require operator browser QA after any repair.

## Explicit Non-Goals

By default, this runbook does not authorize:

- automatic restarts;
- cron enablement;
- systemd timer enablement;
- Caddy changes;
- DNS changes;
- router/firewall changes;
- PM2, Docker, or tmux changes;
- service environment changes;
- Discord sends;
- webhook, cookie, ticket, token, auth secret, password hash, `.env`, or report
  body printing.

Any future automation or live scheduling requires a separate explicit operator
approval gate.

## Closeout Checklist

A Mission-Control availability incident cannot be closed out until the proof
includes:

- proof directory path;
- route classification;
- watchdog `PASS` or a clearly explained `WARN`;
- public marker-safe route checks;
- NUC2 service state when relevant;
- redacted logs if logs were inspected;
- confirmation that no logged-out report body was exposed;
- confirmation that no secrets were printed;
- explicit record of any service restart, or `SERVICES_RESTARTED=no`;
- operator browser QA if restart, SSO, auth, or report shell behavior changed;
- project state update.
