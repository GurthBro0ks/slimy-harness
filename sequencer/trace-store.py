#!/usr/bin/env python3
"""Clean-room proof directory indexer for Slimy Harness.

Indexes local Slimy proof directories into safe metadata. This is not an
AGNT importer and does not read AGNT source; it only parses Slimy proof
artifacts such as RESULT.md.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


DEFAULT_OUTPUT = Path("/home/slimy/harness-logs/state/proof-index.json")
DEFAULT_ROOTS = [Path("/tmp")]
RESULT_FIELD_RE = re.compile(r"^\s*([A-Z][A-Z0-9_]+)\s*=\s*(.*?)\s*$")
SECRET_PATTERNS = [
    re.compile(r"https://discord(?:app)?\.com/api/webhooks/[^\s)>\]\"']+", re.IGNORECASE),
    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]+"),
    re.compile(r"\bsk-[A-Za-z0-9]{12,}"),
    re.compile(r"\bghp_[A-Za-z0-9]{12,}"),
    re.compile(r"-----BEGIN (?:RSA|OPENSSH|EC|DSA) PRIVATE KEY-----[\s\S]*?-----END (?:RSA|OPENSSH|EC|DSA) PRIVATE KEY-----"),
]


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def redact(value: Any) -> Any:
    if isinstance(value, str):
        redacted = value
        for pattern in SECRET_PATTERNS:
            redacted = pattern.sub("[REDACTED]", redacted)
        return redacted
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, dict):
        return {key: redact(item) for key, item in value.items()}
    return value


def safe_read(path: Path, max_bytes: int = 128_000) -> str | None:
    try:
        with path.open("rb") as handle:
            data = handle.read(max_bytes + 1)
    except OSError:
        return None
    return data[:max_bytes].decode("utf-8", errors="replace")


def parse_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    if normalized in {"yes", "true", "1", "pushed", "pass", "passed"}:
        return True
    if normalized in {"no", "false", "0", "none", "not_applicable", "not applicable"}:
        return False
    return None


def split_list(value: str | None) -> list[str]:
    if not value:
        return []
    if value.strip().lower() in {"none", "list_or_none", "n/a", "not_applicable"}:
        return []
    parts = re.split(r"[;\n,]", value)
    return [redact(part.strip()) for part in parts if part.strip()]


def discover_proof_dirs(roots: list[Path]) -> list[Path]:
    found: set[Path] = set()
    for root in roots:
        if not root.exists():
            continue
        if root.is_dir() and root.name.startswith("proof_"):
            found.add(root.resolve())
            continue
        try:
            children = root.iterdir()
        except OSError:
            continue
        for child in children:
            if child.is_dir() and child.name.startswith("proof_"):
                found.add(child.resolve())
    return sorted(found, key=lambda item: str(item))


def parse_result_fields(result_text: str | None) -> dict[str, str]:
    if not result_text:
        return {}
    fields: dict[str, str] = {}
    for line in result_text.splitlines():
        match = RESULT_FIELD_RE.match(line)
        if match:
            fields[match.group(1)] = str(redact(match.group(2).strip()))
    return fields


def summarize_validation(fields: dict[str, str], result_text: str | None) -> str | None:
    for key in ("VALIDATION", "SUMMARY"):
        value = fields.get(key)
        if value:
            return str(redact(value))
    if not result_text:
        return None
    for line in result_text.splitlines():
        if "verified" in line.lower() or "validation" in line.lower():
            return str(redact(line.strip("# -*")))
    return None


def classify_risk_flags(fields: dict[str, str], result_text: str | None, result_file_present: bool) -> list[str]:
    flags: list[str] = []
    if not result_file_present:
        flags.append("missing_result_md")
    result = (fields.get("RESULT") or "").upper()
    if result and result not in {"PASS", "WARN", "FAIL"}:
        flags.append("unknown_result")
    if result == "WARN":
        flags.append("warn_result")
    if result == "FAIL":
        flags.append("fail_result")
    for key in ("SERVICES_RESTARTED", "CRON_CHANGED", "TIMER_CHANGED", "TMUX_CHANGED", "CADDY_CHANGED", "DNS_CHANGED", "SECRETS_PRINTED"):
        if parse_bool(fields.get(key)) is True:
            flags.append(key.lower())
    if result_text and redact(result_text) != result_text:
        flags.append("redacted_secret_like_text")
    return sorted(set(flags))


def proof_mtime(proof_dir: Path) -> str | None:
    try:
        stamp = proof_dir.stat().st_mtime
    except OSError:
        return None
    return dt.datetime.fromtimestamp(stamp, dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_proof_dir(proof_dir: Path) -> dict[str, Any]:
    result_path = proof_dir / "RESULT.md"
    result_text = safe_read(result_path)
    fields = parse_result_fields(result_text)
    result_file_present = result_text is not None
    result = fields.get("RESULT")
    partial_result = result_file_present and not result

    record = {
        "id": proof_dir.name,
        "phase": fields.get("PHASE"),
        "result": result if result in {"PASS", "WARN", "FAIL"} else result,
        "target_machine": fields.get("TARGET_MACHINE"),
        "target_repo": fields.get("TARGET_REPO"),
        "proof_dir": str(proof_dir),
        "validation_summary": summarize_validation(fields, result_text),
        "manual_qa_status": fields.get("MANUAL_QA_STATUS"),
        "discord_status": fields.get("DISCORD_SENT"),
        "report_url": fields.get("REPORT_URL"),
        "changed_files": split_list(fields.get("CHANGED_FILES")),
        "commit_sha": fields.get("COMMIT_SHA"),
        "pushed": parse_bool(fields.get("PUSHED")),
        "risk_flags": classify_risk_flags(fields, result_text, result_file_present),
        "result_file_present": result_file_present,
        "result_file_partial": bool(partial_result),
        "updated_at": proof_mtime(proof_dir),
    }
    return redact(record)


def build_index(roots: list[Path], now: str | None = None) -> dict[str, Any]:
    proof_dirs = discover_proof_dirs(roots)
    proofs = [parse_proof_dir(path) for path in proof_dirs]
    proofs.sort(key=lambda item: (item.get("updated_at") or "", item["id"]), reverse=True)
    return {
        "schema_version": "slimy-proof-index/v1",
        "generated_at": now or utc_now(),
        "proof_roots": [str(root) for root in roots],
        "proof_count": len(proofs),
        "proofs": proofs,
    }


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Index Slimy proof directories into safe JSON metadata.")
    parser.add_argument("--root", action="append", default=[], help="Proof root to scan. Can be repeated. Defaults to /tmp.")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help=f"Output JSON path. Defaults to {DEFAULT_OUTPUT}.")
    parser.add_argument("--now", default=None, help="Optional generated_at timestamp for deterministic tests.")
    args = parser.parse_args(argv)

    roots = [Path(value) for value in args.root] if args.root else DEFAULT_ROOTS
    index = build_index(roots, args.now)
    write_json(Path(args.output), index)
    return 0


if __name__ == "__main__":
    sys.exit(main())
