#!/usr/bin/env python3
"""Manual local loop-status snapshot exporter for Slimy Harness.

The exporter reads one explicit queue JSON path and writes one explicit output
JSON path. It may inspect proof directories under an explicit proof root, but
it never executes queue actions, agents, models, network calls, notifications,
or service/runtime mutations.
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


SCHEMA_VERSION = "loop-status.v1"
GENERATOR = "slimy-harness.loop_status_exporter"
DISPLAY_STATES = ("OK", "WARN", "BLOCKED", "FAIL", "UNKNOWN")
RISK_RANK = {"OK": 0, "UNKNOWN": 1, "WARN": 2, "BLOCKED": 3, "FAIL": 4}
SECRET_MARKERS = re.compile(
    r"discord(?:app)?\.com/api/webhooks/|"
    r"\bAuthorization:\s*Bearer\s+\S+|"
    r"\bBearer\s+[A-Za-z0-9._~+/=-]+|"
    r"\b[A-Z0-9_]*(?:SECRET|TOKEN|PASSWORD|PRIVATE_KEY|API_KEY|WEBHOOK)[A-Z0-9_]*\s*=|"
    r"\bAPPROVAL_(?:NONCE|STATEMENT)\b|"
    r"\b(crontab|raw cron)\b|"
    r"https?://",
    re.IGNORECASE,
)
ASSIGNMENT_SECRET = re.compile(
    r"(\b[A-Z0-9_]*(?:SECRET|TOKEN|PASSWORD|PRIVATE_KEY|API_KEY|WEBHOOK)[A-Z0-9_]*\s*=)\S+",
    re.IGNORECASE,
)
MAX_SCALAR_CHARS = 240


class ExporterError(Exception):
    """User-facing exporter error."""


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sanitize_scalar(value: Any) -> str:
    if value is None:
        return ""
    text = str(value).replace("\x00", "").strip()
    if not text:
        return ""
    text = re.sub(r"https://discord(?:app)?\.com/api/webhooks/\S+", "[REDACTED_URL]", text, flags=re.IGNORECASE)
    text = re.sub(r"\bAuthorization:\s*Bearer\s+\S+", "Authorization: Bearer [REDACTED]", text, flags=re.IGNORECASE)
    text = re.sub(r"\bBearer\s+[A-Za-z0-9._~+/=-]+", "Bearer [REDACTED]", text, flags=re.IGNORECASE)
    text = ASSIGNMENT_SECRET.sub(r"\1[REDACTED]", text)
    text = re.sub(r"APPROVAL_STATEMENT\s*=.*", "APPROVAL_STATEMENT=[REDACTED]", text, flags=re.IGNORECASE)
    text = re.sub(r"APPROVAL_NONCE\s*=.*", "APPROVAL_NONCE=[REDACTED]", text, flags=re.IGNORECASE)
    text = re.sub(r"https?://\S+", "[REDACTED_URL]", text, flags=re.IGNORECASE)
    if SECRET_MARKERS.search(text):
        return "[REDACTED]"
    if len(text) > MAX_SCALAR_CHARS:
        return text[: MAX_SCALAR_CHARS - 3] + "..."
    return text


def sanitize_path(value: Any, *, proof_root: Path | None = None) -> str:
    text = sanitize_scalar(value)
    if not text or text == "[REDACTED]":
        return text
    path = Path(text)
    if proof_root is not None:
        proof_path = resolve_proof_path(path, proof_root)
        if proof_path is not None:
            return proof_path.name
    return path.name if path.name else text


def safe_count(value: Any) -> int:
    if isinstance(value, list):
        return len(value)
    if isinstance(value, dict):
        return len(value)
    if isinstance(value, str) and value.strip():
        return 1
    return 0


def resolve_proof_path(raw_path: Path, proof_root: Path) -> Path | None:
    candidate = raw_path if raw_path.is_absolute() else proof_root / raw_path
    try:
        root = proof_root.resolve()
        resolved = candidate.resolve()
    except OSError:
        return None
    if root == resolved or root in resolved.parents:
        return resolved
    return None


def inspect_proof(item: dict[str, Any], proof_root: Path | None) -> dict[str, Any] | None:
    if proof_root is None or not item.get("proof_dir"):
        return None
    proof_path = resolve_proof_path(Path(str(item["proof_dir"])), proof_root)
    if proof_path is None or not proof_path.is_dir():
        return None
    return proof_gate_checker.evaluate_proof_dir(proof_path)


def load_queue(queue_path: Path) -> tuple[dict[str, Any] | None, list[str]]:
    if not queue_path.exists():
        return None, [f"queue file not found: {sanitize_path(queue_path)}"]
    if queue_path.is_dir():
        return None, [f"queue path is a directory: {sanitize_path(queue_path)}"]
    try:
        data = json.loads(queue_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return None, [f"cannot read queue JSON: {sanitize_scalar(exc)}"]
    if not isinstance(data, dict):
        return None, ["queue JSON must be an object"]
    if not isinstance(data.get("items"), list):
        return None, ["queue items must be a list"]
    return data, []


def status_from_item(item: dict[str, Any], proof_result: dict[str, Any] | None) -> str:
    raw_status = str(item.get("status", "")).strip().upper()
    gate = str((proof_result or {}).get("verdict") or item.get("proof_gate_verdict", "")).strip().upper()

    if gate == "FAIL" or raw_status == "REJECTED":
        return "FAIL"
    if gate == "BLOCKED" or raw_status in {"BLOCKED", "HOLD"}:
        return "BLOCKED"
    if raw_status == "ACCEPTED" and gate != "PASS_ELIGIBLE":
        return "BLOCKED"
    if raw_status in {"READY_FOR_OWNER_QA", "READY_FOR_CLOSEOUT", "ACCEPTED"}:
        return "OK" if gate in {"PASS_ELIGIBLE", ""} else "BLOCKED"
    if raw_status in {"DRAFT", "READY_FOR_REVIEW"}:
        return "WARN"
    if not raw_status:
        return "UNKNOWN"
    return "UNKNOWN"


def sanitize_item(item: Any, proof_root: Path | None) -> tuple[dict[str, Any], list[str]]:
    warnings: list[str] = []
    if not isinstance(item, dict):
        return {
            "id": "",
            "phase": "",
            "title": "",
            "target_machine": "",
            "target_repo": "",
            "model_recommendation": "",
            "glm_thinking_level": "",
            "status": "UNKNOWN",
            "safety_level": "",
            "proof_dir": "",
            "proof_gate_verdict": "UNKNOWN",
            "manual_qa_status": "",
            "next_required_gate": "valid queue item object required",
            "blocked_reason": "queue item is not an object",
            "updated_at": "",
            "warnings_count": 0,
            "reasons_count": 1,
        }, ["non-object queue item rendered as UNKNOWN"]

    proof_result = inspect_proof(item, proof_root)
    gate_verdict = (proof_result or {}).get("verdict") or item.get("proof_gate_verdict") or "UNKNOWN"
    status = status_from_item(item, proof_result)
    reasons_count = safe_count((proof_result or {}).get("reasons")) + safe_count(item.get("reasons"))
    warnings_count = safe_count((proof_result or {}).get("warnings")) + safe_count(item.get("warnings"))
    if item.get("blocked_reason"):
        reasons_count = max(reasons_count, 1)
    if status == "UNKNOWN":
        warnings.append(f"{sanitize_scalar(item.get('id') or 'item')} has unknown status")

    return {
        "id": sanitize_scalar(item.get("id")),
        "phase": sanitize_scalar(item.get("phase")),
        "title": sanitize_scalar(item.get("title")),
        "target_machine": sanitize_scalar(item.get("target_machine")),
        "target_repo": sanitize_scalar(item.get("target_repo")),
        "model_recommendation": sanitize_scalar(item.get("model_recommendation")),
        "glm_thinking_level": sanitize_scalar(item.get("glm_thinking_level")),
        "status": status,
        "safety_level": sanitize_scalar(item.get("safety_level")),
        "proof_dir": sanitize_path(item.get("proof_dir"), proof_root=proof_root),
        "proof_gate_verdict": sanitize_scalar(gate_verdict),
        "manual_qa_status": sanitize_scalar(item.get("manual_qa_status")),
        "next_required_gate": sanitize_scalar((proof_result or {}).get("next_required_gate") or item.get("next_required_gate")),
        "blocked_reason": sanitize_scalar(item.get("blocked_reason")),
        "updated_at": sanitize_scalar(item.get("updated_at")),
        "warnings_count": warnings_count,
        "reasons_count": reasons_count,
    }, warnings


def build_summary(items: list[dict[str, Any]], errors: list[str]) -> dict[str, Any]:
    by_status = {state: 0 for state in DISPLAY_STATES}
    by_gate: dict[str, int] = {}
    highest = "UNKNOWN" if errors else "OK"
    for item in items:
        status = item["status"] if item["status"] in DISPLAY_STATES else "UNKNOWN"
        by_status[status] += 1
        gate = item.get("proof_gate_verdict") or "UNKNOWN"
        by_gate[gate] = by_gate.get(gate, 0) + 1
        if RISK_RANK[status] > RISK_RANK[highest]:
            highest = status
    return {
        "total_items": len(items),
        "by_status": by_status,
        "by_gate": dict(sorted(by_gate.items())),
        "highest_risk_state": highest,
        "has_blockers": bool(errors) or any(item["status"] in {"BLOCKED", "UNKNOWN"} for item in items),
        "has_failures": any(item["status"] == "FAIL" for item in items),
        "stale_count": 0,
    }


def build_snapshot(queue_path: Path, proof_root: Path | None) -> dict[str, Any]:
    queue, errors = load_queue(queue_path)
    items: list[dict[str, Any]] = []
    warnings: list[str] = []
    if queue is not None:
        for item in queue["items"]:
            sanitized, item_warnings = sanitize_item(item, proof_root)
            items.append(sanitized)
            warnings.extend(item_warnings)

    sanitized_errors = [sanitize_scalar(error) for error in errors]
    sanitized_warnings = [sanitize_scalar(warning) for warning in warnings]
    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": utc_now(),
        "generator": GENERATOR,
        "source": {
            "queue_path": sanitize_scalar(queue_path),
            "proof_root": sanitize_scalar(proof_root) if proof_root is not None else "",
        },
        "summary": build_summary(items, sanitized_errors),
        "items": items,
        "safety": {
            "shell_execution_present": False,
            "mutation_controls_present": False,
            "request_time_shell_required": False,
            "secrets_redacted": True,
            "owner_gate_required_for_ui": True,
        },
        "errors": sanitized_errors,
        "warnings": sanitized_warnings,
    }


def write_snapshot(snapshot: dict[str, Any], out_path: Path) -> None:
    if not out_path.parent.exists():
        raise ExporterError(f"output parent directory does not exist: {out_path.parent}")
    if out_path.exists() and out_path.is_dir():
        raise ExporterError("--out must point to a JSON file, not a directory")
    temp_path = out_path.with_name(f".{out_path.name}.tmp")
    temp_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temp_path.replace(out_path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Export a sanitized local loop-status snapshot.")
    parser.add_argument("--queue", required=True, help="Explicit local queue JSON path to read.")
    parser.add_argument("--out", required=True, help="Explicit JSON snapshot path to write.")
    parser.add_argument("--proof-root", default="", help="Optional explicit local root for proof-gate output inspection.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    queue_path = Path(args.queue)
    proof_root = Path(args.proof_root) if args.proof_root else None
    try:
        snapshot = build_snapshot(queue_path, proof_root)
        write_snapshot(snapshot, Path(args.out))
    except ExporterError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 64
    return 0


if __name__ == "__main__":
    sys.exit(main())
