#!/usr/bin/env python3
"""Append-only clean-room active goal record for Slimy Harness."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path
from typing import Any


DEFAULT_RECORD = Path("/home/slimy/harness-logs/state/goal-records.jsonl")
DEFAULT_EXPORT = Path("/home/slimy/harness-logs/state/goal-record-summary.json")
ALLOWED_STATES = {"queued", "running", "paused", "blocked", "retrying", "failed", "complete", "accepted", "warn"}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def require_reason(value: str) -> str:
    reason = value.strip()
    if not reason:
        raise ValueError("state transition reason is required")
    return reason


def append_event(record_path: Path, event: dict[str, Any]) -> None:
    record_path.parent.mkdir(parents=True, exist_ok=True)
    with record_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, sort_keys=True) + "\n")


def load_events(record_path: Path) -> list[dict[str, Any]]:
    if not record_path.exists():
        return []
    events: list[dict[str, Any]] = []
    with record_path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            item = json.loads(stripped)
            validate_event(item, line_number)
            events.append(item)
    return events


def validate_event(event: dict[str, Any], line_number: int = 0) -> None:
    prefix = f"line {line_number}: " if line_number else ""
    state = event.get("state")
    if state not in ALLOWED_STATES:
        raise ValueError(f"{prefix}invalid state: {state!r}")
    if not str(event.get("goal_id") or "").strip():
        raise ValueError(f"{prefix}goal_id is required")
    require_reason(str(event.get("reason") or ""))
    if "passes" in event:
        raise ValueError(f"{prefix}passes is forbidden in goal records; QA owns pass/fail feature claims")


def summarize_events(events: list[dict[str, Any]]) -> dict[str, Any]:
    latest_by_goal: dict[str, dict[str, Any]] = {}
    for event in events:
        latest_by_goal[str(event["goal_id"])] = event
    latest_goals = sorted(latest_by_goal.values(), key=lambda item: str(item.get("timestamp") or ""), reverse=True)
    active_states = {"queued", "running", "paused", "blocked", "retrying", "warn"}
    return {
        "schema_version": "slimy-goal-record-summary/v1",
        "generated_at": utc_now(),
        "record_count": len(events),
        "active_count": sum(1 for event in latest_goals if event.get("state") in active_states),
        "latest_goals": latest_goals[:20],
    }


def cmd_append(args: argparse.Namespace) -> int:
    state = args.state.strip().lower()
    if state not in ALLOWED_STATES:
        raise ValueError(f"invalid state {state!r}; allowed: {', '.join(sorted(ALLOWED_STATES))}")
    event = {
        "schema_version": "slimy-goal-record/v1",
        "timestamp": args.now or utc_now(),
        "goal_id": args.goal_id.strip(),
        "phase": args.phase.strip() or None,
        "state": state,
        "reason": require_reason(args.reason),
        "target_machine": args.target_machine.strip() or None,
        "target_repo": args.target_repo.strip() or None,
        "proof_dir": args.proof_dir.strip() or None,
        "manual_qa_status": args.manual_qa_status.strip() or None,
        "blocker": args.blocker.strip() or None,
        "report_url": args.report_url.strip() or None,
    }
    validate_event(event)
    append_event(Path(args.record), event)
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    load_events(Path(args.record))
    return 0


def cmd_export(args: argparse.Namespace) -> int:
    events = load_events(Path(args.record))
    summary = summarize_events(events)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Append and validate Slimy active goal records.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    append = subparsers.add_parser("append", help="Append one explicit state transition event.")
    append.add_argument("--record", default=str(DEFAULT_RECORD))
    append.add_argument("--goal-id", required=True)
    append.add_argument("--phase", default="")
    append.add_argument("--state", required=True)
    append.add_argument("--reason", required=True)
    append.add_argument("--target-machine", default="")
    append.add_argument("--target-repo", default="")
    append.add_argument("--proof-dir", default="")
    append.add_argument("--manual-qa-status", default="")
    append.add_argument("--blocker", default="")
    append.add_argument("--report-url", default="")
    append.add_argument("--now", default=None)
    append.set_defaults(func=cmd_append)

    validate = subparsers.add_parser("validate", help="Validate every JSONL event.")
    validate.add_argument("--record", default=str(DEFAULT_RECORD))
    validate.set_defaults(func=cmd_validate)

    export = subparsers.add_parser("export", help="Export compact current/recent goal summary JSON.")
    export.add_argument("--record", default=str(DEFAULT_RECORD))
    export.add_argument("--output", default=str(DEFAULT_EXPORT))
    export.set_defaults(func=cmd_export)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"goal-registry: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
