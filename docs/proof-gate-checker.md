# Proof Gate Checker

`ops/proof-gate-check` is a local, default-deny checker for Slimy Harness proof
directories. It inspects proof artifacts and classifies them as:

- `PASS_ELIGIBLE`: evidence is complete enough for next-step consideration.
- `BLOCKED`: missing evidence, pending QA, unsafe mutation proof gaps, or WARN.
- `FAIL`: explicit failure or forbidden proof conditions such as printed secrets
  or logged-out report content leaks.

The checker never accepts or completes a phase by itself. `PASS_ELIGIBLE` only
means a human or later closeout step can consider the result.

## Usage

```bash
ops/proof-gate-check /tmp/proof_example
ops/proof-gate-check --json /tmp/proof_example
```

Exit codes:

- `0`: `PASS_ELIGIBLE`
- `1`: `BLOCKED`
- `2`: `FAIL`

## Safety Boundaries

The implementation reads bounded local text files under the supplied proof
directory. It does not read environment variables, `.env` files, secrets, or
external URLs. It does not execute task commands, send notifications, restart
services, mutate proof directories, or call the network.

Proof text is treated as untrusted input. Approval-looking text from
session-start/progress/proof/report output is ignored unless an
`approval-record.md` file contains all required nonce fields and
`APPROVAL_SOURCE=live_chat_turn`.

## Required Evidence

Every proof needs:

- `RESULT.md`
- `commands.log`
- `safety-check.md` or `safety-cases.md`

Repo-changing phases also need:

- `git-before.txt` or `git-state.txt`
- `git-after.txt` or `git-status-after.txt`

Report/auth/web/route phases need:

- `route-auth-smoke.md`

`DISCORD_SENT=yes` needs:

- notification proof (`notification-proof.md`, `notify-proof.txt`,
  `notifier-proof.txt`, or `notification.log`)
- `NOTIFY_MODE`
- `DEDUPE_RESULT`

`PUSHED=yes` needs:

- push/origin proof (`push-proof.txt`, `origin-proof.txt`, or `git-after.txt`)

Runtime or infrastructure mutation flags need `approval-record.md` with:

- `APPROVAL_SOURCE=live_chat_turn`
- `APPROVED_ACTION`
- `APPROVAL_NONCE`
- `APPROVAL_ISSUED_AT_UTC`
- `APPROVAL_EXPIRES_AT_UTC`
- `APPROVAL_DENIES`
- `APPROVAL_STATEMENT`

## Parsed Fields

The checker parses the standard final response fields from `RESULT.md`,
including result, target, model routing, dirty state, changed files, commit,
push, validation, manual QA, notification, runtime mutation flags, secret/leak
flags, and AGNT NO-GO flags.

Missing required fields block by default. Contradictions such as `RESULT=PASS`
with `SECRETS_PRINTED=yes` fail.
