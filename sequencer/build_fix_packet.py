#!/usr/bin/env python3
"""
build_fix_packet.py — produce the retry context for the next attempt.

Usage:
  python3 sequencer/build_fix_packet.py \
    --feature-id <id> --attempt <N> \
    --goal-dir <goal-dir> --feature-list <path>

Reads:
  <goal-dir>/attempt-<N>/qa-result.json   (required for prior attempt N-1)
  <goal-dir>/attempt-<N>/session-report.json  (if present)
  <goal-dir>/events.jsonl                  (for prior failure signatures)
  /home/slimy/failed-approaches.json       (existing SkillOpt buffer)

Writes:
  <goal-dir>/attempt-<N>/fix-packet.json

Tolerates missing files — produces a minimal packet with whatever it has.
"""

import argparse
import datetime
import json
import sys
from pathlib import Path


MAX_FAILING_COMMANDS = 5
MAX_FAILED_APPROACHES = 10
STDERR_HEAD_CHARS = 500


def _read_json(path):
    p = Path(path)
    if not p.is_file():
        return None
    try:
        with p.open() as f:
            return json.load(f)
    except json.JSONDecodeError:
        return None


def _truncate(s, n):
    if s is None:
        return ""
    s = str(s)
    return s if len(s) <= n else s[:n]


def _read_events(goal_dir):
    p = Path(goal_dir) / "events.jsonl"
    if not p.is_file():
        return []
    events = []
    with p.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events


def _load_failed_approaches(feature_id):
    p = Path("/home/slimy/failed-approaches.json")
    if not p.is_file():
        return []
    try:
        with p.open() as f:
            fa = json.load(f)
    except json.JSONDecodeError:
        return []
    entries = fa.get("entries", []) or []
    matching = [e for e in entries if e.get("feature_id") == feature_id]
    matching.sort(key=lambda e: e.get("timestamp", ""), reverse=True)
    return matching[:MAX_FAILED_APPROACHES]


def _test_trend(goal_dir):
    """Build {attempt_k: 'X/Y'} dict from any prior qa-results."""
    g = Path(goal_dir)
    if not g.is_dir():
        return {}
    trend = {}
    for attempt_dir in sorted(g.glob("attempt-*")):
        if not attempt_dir.is_dir():
            continue
        qa = _read_json(attempt_dir / "qa-result.json")
        if not qa:
            continue
        n = qa.get("attempt")
        passed = qa.get("test_pass_count")
        report = _read_json(attempt_dir / "session-report.json")
        count = None
        if report and isinstance(report.get("tests"), dict):
            count = report["tests"].get("count")
        if passed is not None and count is not None:
            trend[f"attempt_{n}"] = f"{passed}/{count}"
        elif passed is not None:
            trend[f"attempt_{n}"] = str(passed)
    return trend


def _stuck_signals_list(prior_qa, events):
    """Return list of human-readable stuck signal names from prior failures."""
    sigs = []
    if not prior_qa:
        return sigs
    error_sigs = prior_qa.get("error_signatures") or []
    if error_sigs:
        sigs.append("same_error_signature")
    if not (prior_qa.get("changed_files") or []):
        sigs.append("empty_changed_files")
    if prior_qa.get("session_status") == "blocked":
        sigs.append("session_status=blocked")
    if prior_qa.get("tests_passed") is False:
        sigs.append("tests.passed=false")
    if prior_qa.get("regression_detected"):
        sigs.append("regression_detected")
    # Look for repeated error sigs across events
    sig_counts = {}
    for e in events:
        if e.get("event") != "decision":
            continue
    return sigs


def main(argv=None):
    p = argparse.ArgumentParser(description="Build the next-attempt fix packet")
    p.add_argument("--feature-id", required=True)
    p.add_argument("--attempt", type=int, required=True,
                   help="The attempt number that JUST COMPLETED (the one whose qa-result we are summarizing).")
    p.add_argument("--goal-dir", required=True)
    p.add_argument("--feature-list", required=True)
    p.add_argument("--max-attempts", type=int, default=3)
    args = p.parse_args(argv)

    goal_dir = Path(args.goal_dir)
    attempt_dir = goal_dir / f"attempt-{args.attempt}"
    attempt_dir.mkdir(parents=True, exist_ok=True)

    # Load feature
    fl = _read_json(args.feature_list)
    features = fl.get("features", []) if isinstance(fl, dict) else (fl or [])
    feature = None
    for f in features:
        if f.get("id") == args.feature_id:
            feature = f
            break
    if feature is None:
        print(f"[build_fix_packet] feature {args.feature_id} not found", file=sys.stderr)
        return 2

    # Acceptance criteria (truth gate commands)
    acceptance = []
    for key in ("steps", "truth_gates", "validation_commands", "acceptance"):
        v = feature.get(key)
        if isinstance(v, list) and v:
            acceptance = [str(x) for x in v if x]
            break

    # Read prior attempt's artifacts
    prior_qa = _read_json(attempt_dir / "qa-result.json")
    prior_report = _read_json(attempt_dir / "session-report.json")
    events = _read_events(goal_dir)

    failing_commands = []
    error_signatures = []
    qa_fix_brief = None
    changed_files = []
    if prior_qa:
        for fc in (prior_qa.get("failing_commands") or [])[:MAX_FAILING_COMMANDS]:
            failing_commands.append({
                "command": fc.get("command", ""),
                "stderr_head": _truncate(fc.get("stderr_head", ""), STDERR_HEAD_CHARS),
                "signature": fc.get("signature", ""),
            })
        error_signatures = list(prior_qa.get("error_signatures") or [])
        qa_fix_brief = prior_qa.get("fix_brief")
        changed_files = list(prior_qa.get("changed_files") or [])

    # failed_approaches: prior report's summary + global SkillOpt buffer
    failed_approaches = []
    if prior_report:
        summary = prior_report.get("summary") or ""
        status = prior_report.get("status", "?")
        if summary:
            failed_approaches.append(
                f"attempt {args.attempt}: status={status}; {summary[:300]}"
            )
    for fa in _load_failed_approaches(args.feature_id):
        desc = fa.get("approach_description", "(none)")
        fail = fa.get("failure_reason", "(none)")
        anum = fa.get("attempt_number", "?")
        failed_approaches.append(f"attempt {anum}: {desc[:200]} -> {fail[:200]}")

    packet = {
        "feature_id": args.feature_id,
        "attempt_completed": args.attempt,
        "max_attempts": args.max_attempts,
        "objective": (feature.get("description") or "").strip(),
        "acceptance_criteria": acceptance,
        "failing_commands": failing_commands,
        "error_signatures": error_signatures,
        "changed_files": changed_files,
        "failed_approaches": failed_approaches[:MAX_FAILED_APPROACHES],
        "qa_fix_brief": qa_fix_brief,
        "test_trend": _test_trend(goal_dir),
        "stuck_signals": _stuck_signals_list(prior_qa, events),
        "built_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }

    out = attempt_dir / "fix-packet.json"
    tmp = out.with_suffix(out.suffix + ".tmp")
    with tmp.open("w") as f:
        json.dump(packet, f, indent=2)
        f.write("\n")
    tmp.replace(out)
    print(f"[build_fix_packet] wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
