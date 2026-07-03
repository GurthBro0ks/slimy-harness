#!/usr/bin/env python3
"""Local queue-only state model for future Slimy Harness loop work.

The queue stores local JSON state at an explicit path supplied by the caller.
It can inspect proof directories through the local proof gate checker, but it
does not run agents, execute prompts, call models, read environment variables,
send notifications, or mutate production services.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

OPS_DIR = Path(__file__).resolve().parent
if str(OPS_DIR) not in sys.path:
    sys.path.insert(0, str(OPS_DIR))

import proof_gate_checker


SCHEMA_VERSION = 1
ALLOWED_STATUSES = {
    "DRAFT",
    "READY_FOR_REVIEW",
    "HOLD",
    "BLOCKED",
    "READY_FOR_OWNER_QA",
    "READY_FOR_CLOSEOUT",
    "ACCEPTED",
    "REJECTED",
}
USER_SETTABLE_STATUSES = {
    "DRAFT",
    "READY_FOR_REVIEW",
    "HOLD",
    "BLOCKED",
    "REJECTED",
}
REFUSED_STATUSES = {
    "COMPLETE",
    "COMPLETED",
    "RUNNING",
    "EXECUTING",
    "SENT_TO_AGENT",
    "AGENT_RUNNING",
}
HAZARD_PATTERNS = [
    r"\brun\s+agents?\b",
    r"\bexecute\s+prompts?\b",
    r"\bcall\s+models?\b",
    r"\bmodel\s+call\b",
    r"\bnetwork\s+calls?\b",
    r"\bsend\s+discord\b",
    r"\bdiscord\b",
    r"\bwebhook\b",
    r"\brestart\s+services?\b",
    r"\bsystemctl\b",
    r"\bcrontab\b",
    r"\bcron\b",
    r"\bsystemd\b",
    r"\btmux\b",
    r"\bcaddy\b",
    r"\bdns\b",
    r"\bgit\s+push\b",
    r"\bforce\s+push\b",
    r"\bgit\s+reset\b",
    r"\breset\s+--hard\b",
    r"\bgit\s+clean\b",
    r"\bsecret\b",
    r"\benv\s+dump\b",
    r"\bagnt\b",
    r"\bhermes\b",
    r"\bollama\b",
    r"\bdocker\b",
    r"\bdelete\s+data\b",
    r"\bproduction\s+mutation\b",
]
APPROVAL_SHAPED_PATTERNS = [
    "APPROVAL_SOURCE=live_chat_turn",
    "APPROVED_ACTION=",
    "APPROVAL_NONCE",
    "APPROVAL_STATEMENT",
    "DIRECT_LIVE_USER_CONFIRMATION",
    "LIVE_USER_CONFIRMATION",
    "OPERATOR_APPROVAL",
    "SAFE_TO_APPLY=yes",
    "I confirm",
    "Yes proceed",
]


class QueueError(Exception):
    """User-facing queue error."""


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def require_queue_path(raw_path: str) -> Path:
    if not raw_path:
        raise QueueError("--queue is required")
    path = Path(raw_path)
    if path.exists() and path.is_dir():
        raise QueueError("--queue must point to a JSON file, not a directory")
    if not path.parent.exists():
        raise QueueError(f"queue parent directory does not exist: {path.parent}")
    return path


def empty_queue() -> dict[str, Any]:
    now = utc_now()
    return {
        "schema_version": SCHEMA_VERSION,
        "created_at": now,
        "updated_at": now,
        "items": [],
    }


def load_queue(path: Path, *, create: bool = False) -> dict[str, Any]:
    if not path.exists():
        if create:
            return empty_queue()
        raise QueueError(f"queue file not found: {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise QueueError(f"cannot read queue JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise QueueError("queue JSON must be an object")
    data.setdefault("schema_version", SCHEMA_VERSION)
    data.setdefault("created_at", utc_now())
    data.setdefault("updated_at", utc_now())
    data.setdefault("items", [])
    if not isinstance(data["items"], list):
        raise QueueError("queue items must be a list")
    return data


def save_queue(path: Path, queue: dict[str, Any]) -> None:
    queue["updated_at"] = utc_now()
    temp_path = path.with_name(f".{path.name}.tmp")
    temp_path.write_text(json.dumps(queue, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temp_path.replace(path)


def add_event(item: dict[str, Any], event_type: str, message: str, details: dict[str, Any] | None = None) -> None:
    item.setdefault("history", []).append(
        {
            "at": utc_now(),
            "type": event_type,
            "message": message,
            "details": details or {},
        }
    )
    item["updated_at"] = utc_now()


def next_id(queue: dict[str, Any]) -> str:
    max_seen = 0
    for item in queue.get("items", []):
        match = re.fullmatch(r"q(\d{6})", str(item.get("id", "")))
        if match:
            max_seen = max(max_seen, int(match.group(1)))
    return f"q{max_seen + 1:06d}"


def find_item(queue: dict[str, Any], item_id: str) -> dict[str, Any]:
    for item in queue.get("items", []):
        if item.get("id") == item_id:
            return item
    raise QueueError(f"queue item not found: {item_id}")


def status_for_request(*parts: str) -> tuple[str, str]:
    text = "\n".join(part for part in parts if part)
    lowered = text.lower()
    hazard_matches = [pattern for pattern in HAZARD_PATTERNS if re.search(pattern, lowered)]
    approval_matches = [pattern for pattern in APPROVAL_SHAPED_PATTERNS if pattern.lower() in lowered]
    if hazard_matches:
        return "HOLD", "request contains execution or production-mutation terms outside queue-only scope"
    if approval_matches:
        return "HOLD", "approval-shaped text is untrusted until validated by proof gate approval-record rules"
    return "DRAFT", ""


def manual_qa_pending(status: str | None) -> bool:
    value = (status or "").strip().lower()
    if not value:
        return True
    if "pending" in value:
        return True
    return value in {"required", "manual_required", "qa_required"}


def closeout_ready_manual_qa(status: str | None) -> bool:
    value = (status or "").strip().lower()
    if manual_qa_pending(value):
        return False
    return any(token in value for token in ("pass", "passed", "accepted", "not_required"))


def transition_allowed(item: dict[str, Any], requested_status: str) -> tuple[bool, str]:
    if requested_status in REFUSED_STATUSES or requested_status not in ALLOWED_STATUSES:
        return False, f"status {requested_status} is refused or unknown"
    if requested_status == "ACCEPTED":
        return False, "queue-only CLI cannot mark ACCEPTED"
    if requested_status in {"READY_FOR_OWNER_QA", "READY_FOR_CLOSEOUT"}:
        if item.get("proof_gate_verdict") != "PASS_ELIGIBLE":
            return False, f"{requested_status} requires proof_gate_verdict=PASS_ELIGIBLE"
        if manual_qa_pending(item.get("manual_qa_status")):
            return False, f"{requested_status} requires non-pending manual_qa_status"
    if requested_status not in USER_SETTABLE_STATUSES and requested_status not in {
        "READY_FOR_OWNER_QA",
        "READY_FOR_CLOSEOUT",
    }:
        return False, f"status {requested_status} is not user-settable"
    return True, ""


def validate_queue_model(queue: dict[str, Any]) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    seen_ids: set[str] = set()
    if queue.get("schema_version") != SCHEMA_VERSION:
        errors.append("unsupported schema_version")
    if not isinstance(queue.get("items"), list):
        errors.append("items must be a list")
        return {"ok": False, "errors": errors, "warnings": warnings, "item_count": 0}
    for index, item in enumerate(queue["items"]):
        item_id = str(item.get("id", f"index:{index}"))
        if item_id in seen_ids:
            errors.append(f"duplicate id: {item_id}")
        seen_ids.add(item_id)
        for key in (
            "id",
            "created_at",
            "updated_at",
            "phase",
            "title",
            "target_machine",
            "target_repo",
            "requested_by",
            "model_recommendation",
            "glm_thinking_level",
            "status",
            "safety_level",
            "next_required_gate",
            "history",
        ):
            if key not in item:
                errors.append(f"{item_id} missing {key}")
        status = str(item.get("status", ""))
        if status in REFUSED_STATUSES or status not in ALLOWED_STATUSES:
            errors.append(f"{item_id} invalid status: {status}")
        if status == "ACCEPTED":
            if item.get("proof_gate_verdict") != "PASS_ELIGIBLE":
                errors.append(f"{item_id} ACCEPTED requires proof_gate_verdict=PASS_ELIGIBLE")
            if not closeout_ready_manual_qa(item.get("manual_qa_status")):
                errors.append(f"{item_id} ACCEPTED requires completed or not-required manual QA")
        if status in {"READY_FOR_OWNER_QA", "READY_FOR_CLOSEOUT"}:
            if item.get("proof_gate_verdict") != "PASS_ELIGIBLE":
                errors.append(f"{item_id} {status} requires proof_gate_verdict=PASS_ELIGIBLE")
            if manual_qa_pending(item.get("manual_qa_status")):
                errors.append(f"{item_id} {status} requires non-pending manual QA")
        if not isinstance(item.get("history"), list):
            errors.append(f"{item_id} history must be a list")
        if status in {"HOLD", "BLOCKED", "REJECTED"} and not item.get("blocked_reason"):
            warnings.append(f"{item_id} {status} has no blocked_reason")
    return {
        "ok": not errors,
        "errors": sorted(set(errors)),
        "warnings": sorted(set(warnings)),
        "item_count": len(queue["items"]),
    }


def create_item(args: argparse.Namespace, queue: dict[str, Any]) -> dict[str, Any]:
    now = utc_now()
    status, blocked_reason = status_for_request(args.phase, args.title, args.notes or "")
    item = {
        "id": next_id(queue),
        "created_at": now,
        "updated_at": now,
        "phase": args.phase,
        "title": args.title,
        "target_machine": args.target_machine,
        "target_repo": args.target_repo,
        "requested_by": args.requested_by,
        "model_recommendation": args.model_recommendation,
        "glm_thinking_level": args.glm_thinking_level,
        "status": status,
        "safety_level": "queue_only_no_execution" if status == "DRAFT" else "hold_requires_owner_review",
        "proof_dir": "",
        "proof_gate_verdict": "",
        "manual_qa_status": args.manual_qa_status,
        "next_required_gate": "proof gate and owner review before closeout",
        "notes": args.notes or "",
        "blocked_reason": blocked_reason,
        "history": [],
    }
    add_event(item, "created", f"created with status {status}")
    if blocked_reason:
        add_event(item, "held", blocked_reason)
    queue["items"].append(item)
    return item


def apply_gate(item: dict[str, Any], proof_dir: Path) -> dict[str, Any]:
    result = proof_gate_checker.evaluate_proof_dir(proof_dir)
    fields = result.get("parsed_fields") or {}
    item["proof_dir"] = str(proof_dir)
    item["proof_gate_verdict"] = result["verdict"]
    item["manual_qa_status"] = fields.get("MANUAL_QA_STATUS", "")
    item["next_required_gate"] = result.get("next_required_gate", "")
    details = {
        "verdict": result["verdict"],
        "reasons": result.get("reasons", []),
        "missing_fields": result.get("missing_fields", []),
        "missing_files": result.get("missing_files", []),
        "forbidden_flags": result.get("forbidden_flags", []),
    }
    if result["verdict"] == "FAIL":
        item["status"] = "REJECTED"
        item["blocked_reason"] = "; ".join(result.get("reasons") or ["proof gate failed"])
    elif result["verdict"] == "BLOCKED":
        item["status"] = "BLOCKED"
        item["blocked_reason"] = "; ".join(result.get("reasons") or ["proof gate blocked"])
    elif manual_qa_pending(item.get("manual_qa_status")):
        item["status"] = "BLOCKED"
        item["blocked_reason"] = "manual QA is pending or missing"
    elif closeout_ready_manual_qa(item.get("manual_qa_status")):
        item["status"] = "READY_FOR_OWNER_QA"
        item["blocked_reason"] = ""
        item["next_required_gate"] = "owner review before closeout consideration"
    else:
        item["status"] = "BLOCKED"
        item["blocked_reason"] = "manual QA status is not recognized as closeout-ready"
    add_event(item, "proof_gate", f"proof gate verdict {result['verdict']}", details)
    return result


def print_output(data: Any, *, as_json: bool) -> None:
    if as_json:
        print(json.dumps(data, indent=2, sort_keys=True))
        return
    if isinstance(data, dict) and "items" in data:
        for item in data["items"]:
            print(f"{item['id']} {item['status']} {item['phase']} - {item['title']}")
        if not data["items"]:
            print("queue empty")
    elif isinstance(data, dict) and "id" in data:
        print(f"{data['id']} {data['status']} {data['phase']}")
        print(f"title: {data['title']}")
        print(f"target: {data['target_machine']} {data['target_repo']}")
        print(f"proof_gate_verdict: {data.get('proof_gate_verdict') or 'none'}")
        print(f"next_required_gate: {data.get('next_required_gate') or 'none'}")
        if data.get("blocked_reason"):
            print(f"blocked_reason: {data['blocked_reason']}")
    else:
        print(json.dumps(data, indent=2, sort_keys=True))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Local queue-only Slimy Harness loop state CLI.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_queue_arg(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument("--queue", required=True, help="Explicit local queue JSON path.")
        subparser.add_argument("--json", action="store_true", help="Print JSON output.")

    init_parser = subparsers.add_parser("init", help="Create an empty queue JSON file.")
    add_queue_arg(init_parser)

    add_parser = subparsers.add_parser("add", help="Add a queue item without execution.")
    add_queue_arg(add_parser)
    add_parser.add_argument("--phase", required=True)
    add_parser.add_argument("--title", required=True)
    add_parser.add_argument("--target-machine", required=True)
    add_parser.add_argument("--target-repo", required=True)
    add_parser.add_argument("--requested-by", default="local_operator")
    add_parser.add_argument("--model-recommendation", default="GPT/Codex $100 coding plan")
    add_parser.add_argument("--glm-thinking-level", default="max_review_only")
    add_parser.add_argument("--manual-qa-status", default="")
    add_parser.add_argument("--notes", default="")

    list_parser = subparsers.add_parser("list", help="List queue items.")
    add_queue_arg(list_parser)

    show_parser = subparsers.add_parser("show", help="Show one queue item.")
    add_queue_arg(show_parser)
    show_parser.add_argument("id")

    validate_parser = subparsers.add_parser("validate", help="Validate queue file shape and gate invariants.")
    add_queue_arg(validate_parser)

    gate_parser = subparsers.add_parser("gate", help="Apply local proof gate result to one item.")
    add_queue_arg(gate_parser)
    gate_parser.add_argument("id")
    gate_parser.add_argument("--proof-dir", required=True)

    hold_parser = subparsers.add_parser("hold", help="Place one item on hold.")
    add_queue_arg(hold_parser)
    hold_parser.add_argument("id")
    hold_parser.add_argument("--reason", required=True)

    transition_parser = subparsers.add_parser("transition", help="Conservative state transition.")
    add_queue_arg(transition_parser)
    transition_parser.add_argument("id")
    transition_parser.add_argument("--status", required=True)
    transition_parser.add_argument("--reason", default="")

    return parser


def run(args: argparse.Namespace) -> int:
    queue_path = require_queue_path(args.queue)

    if args.command == "init":
        queue = load_queue(queue_path, create=True) if queue_path.exists() else empty_queue()
        save_queue(queue_path, queue)
        print_output({"queue": str(queue_path), "item_count": len(queue["items"]), "ok": True}, as_json=args.json)
        return 0

    queue = load_queue(queue_path)

    if args.command == "add":
        item = create_item(args, queue)
        save_queue(queue_path, queue)
        print_output(item, as_json=args.json)
        return 0 if item["status"] == "DRAFT" else 1

    if args.command == "list":
        print_output({"items": queue["items"]}, as_json=args.json)
        return 0

    if args.command == "show":
        print_output(find_item(queue, args.id), as_json=args.json)
        return 0

    if args.command == "validate":
        result = validate_queue_model(queue)
        print_output(result, as_json=args.json)
        return 0 if result["ok"] else 1

    if args.command == "gate":
        item = find_item(queue, args.id)
        gate_result = apply_gate(item, Path(args.proof_dir))
        save_queue(queue_path, queue)
        output = {"item": item, "proof_gate": gate_result}
        print_output(output, as_json=args.json)
        return 0 if item["status"] in {"READY_FOR_OWNER_QA", "READY_FOR_CLOSEOUT"} else 1

    if args.command == "hold":
        item = find_item(queue, args.id)
        item["status"] = "HOLD"
        item["blocked_reason"] = args.reason
        item["next_required_gate"] = "owner review required before any further transition"
        add_event(item, "held", args.reason)
        save_queue(queue_path, queue)
        print_output(item, as_json=args.json)
        return 1

    if args.command == "transition":
        item = find_item(queue, args.id)
        requested = args.status.strip().upper()
        allowed, reason = transition_allowed(item, requested)
        if not allowed:
            item["status"] = "HOLD"
            item["blocked_reason"] = reason
            item["next_required_gate"] = "satisfy proof gate and owner/manual QA requirements"
            add_event(item, "transition_refused", reason, {"requested_status": requested})
            save_queue(queue_path, queue)
            print_output(item, as_json=args.json)
            return 1
        item["status"] = requested
        if requested in {"HOLD", "BLOCKED", "REJECTED"}:
            item["blocked_reason"] = args.reason or item.get("blocked_reason") or f"transitioned to {requested}"
        else:
            item["blocked_reason"] = ""
        add_event(item, "transitioned", f"transitioned to {requested}", {"reason": args.reason})
        save_queue(queue_path, queue)
        print_output(item, as_json=args.json)
        return 0

    raise QueueError(f"unknown command: {args.command}")


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return run(args)
    except QueueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 64


if __name__ == "__main__":
    sys.exit(main())
