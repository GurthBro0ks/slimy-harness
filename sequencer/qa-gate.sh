#!/usr/bin/env bash
# qa-gate.sh — deterministic truth-gate runner and session-report evaluator.
#
# Phase 1 contract: QA_GATE_DRY_RUN=1 is always set. Real truth-gate
# execution against a repo is deferred to Phase 2.
#
# Usage:
#   QA_GATE_DRY_RUN=1 bash sequencer/qa-gate.sh \
#     <feature_id> <session-report.json> <attempt-dir> [feature-list-path]
#
# Outputs:
#   <attempt-dir>/qa-result.json
#
# This script does NOT set passes:true. It only produces qa-result.json
# for goal_runner.py to consume.
set -euo pipefail

FEATURE_ID="${1:-}"
REPORT_PATH="${2:-}"
ATTEMPT_DIR="${3:-}"
FEATURE_LIST_PATH="${4:-/home/slimy/feature_list.json}"

log() { echo "[$(date -Iseconds)] [qa-gate] $*" >&2; }

if [ -z "$FEATURE_ID" ] || [ -z "$REPORT_PATH" ] || [ -z "$ATTEMPT_DIR" ]; then
  log "usage: qa-gate.sh <feature_id> <session-report.json> <attempt-dir> [feature-list-path]"
  exit 2
fi

if [ ! -f "$REPORT_PATH" ]; then
  log "session report not found: $REPORT_PATH"
  exit 2
fi

if [ ! -f "$FEATURE_LIST_PATH" ]; then
  log "feature list not found: $FEATURE_LIST_PATH"
  exit 2
fi

mkdir -p "$ATTEMPT_DIR"
QA_RESULT_PATH="$ATTEMPT_DIR/qa-result.json"

DRY_RUN="${QA_GATE_DRY_RUN:-1}"

log "feature_id=$FEATURE_ID report=$REPORT_PATH attempt_dir=$ATTEMPT_DIR dry_run=$DRY_RUN"

export FEATURE_ID REPORT_PATH ATTEMPT_DIR FEATURE_LIST_PATH DRY_RUN QA_RESULT_PATH

python3 << 'PYEOF'
import hashlib
import json
import os
import re
import sys
from pathlib import Path

feature_id = os.environ["FEATURE_ID"]
report_path = Path(os.environ["REPORT_PATH"])
attempt_dir = Path(os.environ["ATTEMPT_DIR"])
feature_list_path = Path(os.environ["FEATURE_LIST_PATH"])
dry_run = os.environ.get("DRY_RUN", "1") == "1"
qa_result_path = Path(os.environ["QA_RESULT_PATH"])

with report_path.open() as f:
    report = json.load(f)

with feature_list_path.open() as f:
    fl = json.load(f)
if isinstance(fl, dict):
    features = fl.get("features", [])
else:
    features = fl

feature = None
for f in features:
    if f.get("id") == feature_id:
        feature = f
        break

if feature is None:
    print(f"[qa-gate] feature {feature_id} not found in feature list", file=sys.stderr)
    sys.exit(2)

# Discover truth gate commands using the same priority as goal_runner.py
truth_gates = []
for key in ("steps", "truth_gates", "validation_commands", "acceptance"):
    v = feature.get(key)
    if isinstance(v, list) and v:
        truth_gates = [str(x) for x in v if x]
        break
truth_gate_status = "discovered" if truth_gates else "missing"

session_status = report.get("status")
tests = report.get("tests") or {}
tests_passed = tests.get("passed")
tests_count = tests.get("count")
tests_failed_count = tests.get("failed_count")
tests_ran = tests.get("ran", False)

summary = report.get("summary") or ""
changes = report.get("changes") or []
blockers = report.get("blockers") or []
recommendation = report.get("recommendation") or {}

# Stub / TODO detection in summary and changes
stub_pattern = re.compile(r"\b(TODO|FIXME|XXX|stub|not implemented|placeholder)\b", re.I)
combined_text = summary + " " + " ".join(str(c) for c in changes)
stub_detected = bool(stub_pattern.search(combined_text))

# Test pass count derivation
test_pass_count = None
if isinstance(tests_count, int) and isinstance(tests_failed_count, int):
    test_pass_count = max(tests_count - tests_failed_count, 0)
elif isinstance(tests_count, int) and tests_passed is True:
    test_pass_count = tests_count
elif isinstance(tests_count, int) and tests_passed is False:
    test_pass_count = max(tests_count - 1, 0)

# Truth gate execution (dry-run vs real)
failing_commands = []
all_passed = True

if dry_run:
    truth_gate_verdict = "dry-run-skipped"
    if truth_gates:
        # In dry-run, derive failing commands from session report content
        if session_status in ("failed", "partial") or tests_passed is False or stub_detected:
            for i, cmd in enumerate(truth_gates):
                # Synthesize one failing command per gate for the signature
                err_text = (
                    f"[dry-run] {session_status or 'unknown'}: {summary[:200]} "
                    f"tests.passed={tests_passed} count={tests_count} failed={tests_failed_count}"
                ).encode()
                sig = hashlib.md5(err_text[: min(20 * 80, len(err_text))]).hexdigest()
                stderr_lines = err_text.decode(errors="replace").splitlines()[:10]
                failing_commands.append({
                    "command": cmd,
                    "exit_code": 1,
                    "stderr_head": "\n".join(stderr_lines),
                    "signature": sig,
                })
            all_passed = False
        # else: all gates would pass in dry-run
else:
    # Real mode (Phase 2): cd to project dir and run each command
    project_path = feature.get("path") or f"/opt/slimy/{feature.get('project','unknown')}"
    truth_gate_verdict = "pass"  # optimistic, flip if any fail
    if not truth_gates:
        truth_gate_verdict = "missing"
    else:
        import subprocess
        # Build a clean env that always has PYTHONDONTWRITEBYTECODE=1
        # so truth-gate Python commands cannot create __pycache__ in
        # the worktree being evaluated. Inherits PATH/HOME/USER from
        # the parent so the gate can still find binaries.
        clean_env = dict(os.environ)
        clean_env["PYTHONDONTWRITEBYTECODE"] = "1"
        for cmd in truth_gates:
            try:
                proc = subprocess.run(
                    cmd, shell=True, cwd=project_path,
                    capture_output=True, text=True, timeout=300,
                    env=clean_env,
                )
                if proc.returncode != 0:
                    all_passed = False
                    stderr_text = (proc.stderr or "")[-50*200:]
                    stderr_lines = stderr_text.splitlines()[:10]
                    sig = hashlib.md5("\n".join(stderr_lines).encode()).hexdigest()
                    failing_commands.append({
                        "command": cmd,
                        "exit_code": proc.returncode,
                        "stderr_head": "\n".join(stderr_lines),
                        "signature": sig,
                    })
            except Exception as e:
                all_passed = False
                failing_commands.append({
                    "command": cmd, "exit_code": -1,
                    "stderr_head": f"exception: {e}",
                    "signature": hashlib.md5(str(e).encode()).hexdigest(),
                })
        if failing_commands:
            truth_gate_verdict = "fail"

# Combine with session report signals
if session_status in ("failed", "blocked") and not failing_commands and not dry_run:
    all_passed = False
if tests_passed is False and not failing_commands and not dry_run:
    all_passed = False

# In dry-run, verdict = pass iff session report indicates pass
if dry_run:
    session_ok = (
        session_status in ("completed",)
        and tests_passed is True
        and not stub_detected
    )
    verdict = "pass" if session_ok and not failing_commands else "fail"
    truth_gate_verdict = "dry-run-skipped" if not failing_commands else truth_gate_verdict
else:
    verdict = "pass" if (all_passed and not failing_commands) else "fail"

# Error signatures
error_signatures = [fc["signature"] for fc in failing_commands]

# fix_brief
fix_brief = None
if verdict == "fail":
    if failing_commands:
        first = failing_commands[0]
        first_cmd_short = first["command"][:80]
        first_err_short = (first.get("stderr_head") or "").splitlines()[0] if first.get("stderr_head") else "(no stderr)"
        fix_brief = f"gate {first_cmd_short!r} failed: {first_err_short[:120]}"
    elif session_status == "blocked":
        blocker_descs = "; ".join((b.get("description") or "?")[:80] for b in blockers) or "(no description)"
        fix_brief = f"agent self-reported blocked: {blocker_descs}"
    else:
        fix_brief = f"verdict=fail with status={session_status}, tests.passed={tests_passed}"
    # Enforce mechanical, single-sentence
    fix_brief = fix_brief.split("\n")[0][:240]

# Regression check: compare with previous attempt qa-result
regression_detected = False
prev_qa_path = attempt_dir.parent / f"attempt-{int(attempt_dir.name.split('-')[-1]) - 1}" / "qa-result.json"
if prev_qa_path.is_file():
    try:
        with prev_qa_path.open() as f:
            prev = json.load(f)
        prev_pass = prev.get("test_pass_count")
        if (test_pass_count is not None and prev_pass is not None
                and test_pass_count < prev_pass):
            regression_detected = True
    except Exception:
        pass

# changed_files: from session report (if available)
changed_files = list(changes) if isinstance(changes, list) else []

# Evidence lines
evidence = []
evidence.append(f"status={session_status}")
evidence.append(f"tests.passed={tests_passed}")
if tests_count is not None:
    evidence.append(f"tests.count={tests_count}")
if tests_failed_count is not None:
    evidence.append(f"tests.failed_count={tests_failed_count}")
evidence.append(f"truth_gate={truth_gate_verdict}")
if stub_detected:
    evidence.append("stub/TODO/FIXME detected in summary or changes")
if regression_detected:
    evidence.append(f"regression vs previous qa-result (test_pass_count {test_pass_count} < {prev_pass})")

qa_result = {
    "feature_id": feature_id,
    "attempt": int(attempt_dir.name.split("-")[-1]),
    "verdict": verdict,
    "truth_gate": truth_gate_verdict,
    "session_status": session_status,
    "tests_passed": tests_passed,
    "test_pass_count": test_pass_count,
    "changed_files": changed_files,
    "regression_detected": regression_detected,
    "failing_commands": failing_commands,
    "error_signatures": error_signatures,
    "stub_detected": stub_detected,
    "fix_brief": fix_brief,
    "evidence": evidence,
}

with qa_result_path.open("w") as f:
    json.dump(qa_result, f, indent=2)
    f.write("\n")
print(f"[qa-gate] wrote {qa_result_path} verdict={verdict} truth_gate={truth_gate_verdict}")
PYEOF

log "qa-gate complete: $QA_RESULT_PATH"
