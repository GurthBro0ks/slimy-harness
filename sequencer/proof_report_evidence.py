#!/usr/bin/env python3
"""Extract bounded, display-safe report evidence from a proof directory.

The proof adapters intentionally read only RESULT.md metadata, known validation
artifacts, and artifact *names*. They never embed raw proof contents.
"""

from __future__ import annotations

import datetime as dt
import json
import math
import re
from pathlib import Path
from typing import Any


PASS_STATUSES = {"completed", "done", "ok", "pass", "passed", "success"}
FAIL_STATUSES = {"error", "fail", "failed"}
KNOWN_CHECKS = (
    ("focused-tests.txt", "Focused tests", "focused"),
    ("full-tests.txt", "Full tests", "full"),
    ("harness-validation.txt", "Harness validation", "harness"),
    ("collision-tests.txt", "Collision", "collision"),
    ("concurrency-tests.txt", "Concurrency", "concurrency"),
    ("torn-write-tests.txt", "Torn-write", "torn_write"),
)
SENSITIVE_NAME = re.compile(
    r"(?:sk-[A-Za-z0-9_-]{12,}|[A-Za-z0-9_-]{32,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,})"
)
ADAPTER_CONTROL_FILES = {"RESULT.md", "harness-metadata.json", "harness-metadata.resolved.json"}


def parse_result_fields(path: str | Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    result_path = Path(path)
    if not result_path.is_file():
        return fields
    for raw_line in result_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if re.fullmatch(r"[A-Z0-9_]+", key):
            fields[key] = value.strip()[:2000]
    return fields


def _status(text: object) -> str:
    return str(text or "").strip().lower()


def _bool_value(text: object) -> bool | None:
    lowered = _status(text)
    if lowered in {"1", "active", "enabled", "pass", "passed", "true", "yes"}:
        return True
    if lowered in {"0", "disabled", "fail", "failed", "false", "inactive", "no", "none"}:
        return False
    return None


def _read_known_artifact(proof_dir: Path, name: str) -> str:
    path = proof_dir / name
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")[:200_000]


def _parse_check(filename: str, label: str, check_id: str, text: str) -> dict[str, Any] | None:
    if not text:
        return None

    passed = failed = total = None
    if filename == "harness-validation.txt":
        match = re.search(r"Results:\s*.*?(\d+)\s+passed.*?(\d+)\s+failures?", text, re.I | re.S)
        if match:
            passed, failed = int(match.group(1)), int(match.group(2))
            total = passed + failed
    else:
        passed_match = re.search(r"(\d+)\s+passed", text, re.I)
        failed_match = re.search(r"(\d+)\s+failed", text, re.I)
        if passed_match or failed_match:
            passed = int(passed_match.group(1)) if passed_match else 0
            failed = int(failed_match.group(1)) if failed_match else 0
            total = passed + failed

    if total is None:
        if re.search(r"(?:^|\s)(?:PASS|passed)(?:\s|$)", text, re.I):
            passed, failed, total = 1, 0, 1
        elif re.search(r"(?:^|\s)(?:FAIL|failed)(?:\s|$)", text, re.I):
            passed, failed, total = 0, 1, 1
        else:
            return None

    check_status = "PASS" if failed == 0 and passed == total else "FAIL"
    count = f"{passed}/{total}" if filename != "harness-validation.txt" else f"{passed}/{failed}"
    return {
        "id": check_id,
        "name": label,
        "status": check_status,
        "passed": passed,
        "failed": failed,
        "total": total,
        "display": f"{label}: {count} {check_status}",
        "source_artifact": filename,
    }


def _classify_tests(fields: dict[str, str], proof_dir: Path, status_value: str) -> dict[str, Any]:
    checks = [
        check
        for filename, label, check_id in KNOWN_CHECKS
        if (check := _parse_check(filename, label, check_id, _read_known_artifact(proof_dir, filename)))
    ]
    if checks:
        passed = all(check["status"] == "PASS" for check in checks)
        return {
            "ran": True,
            "passed": passed,
            "label": "TESTS PASS" if passed else "TESTS FAIL",
            "details": "\n".join(check["display"] for check in checks),
            "checks": checks,
        }

    combined = " ".join(
        fields.get(key, "")
        for key in ("VALIDATION", "MANUAL_QA_STATUS", "RESULT", "SUMMARY")
    ).lower()
    normalized = re.sub(r"[-_]+", " ", combined)
    if re.search(r"\bsmoke only\b|\broute smoke\b|\bsmoke\b", normalized):
        return {
            "ran": False,
            "passed": False,
            "label": "SMOKE ONLY",
            "details": "Proof dir adapter: smoke-only validation from RESULT.md metadata",
            "checks": [],
        }
    if re.search(r"tests? not run|no tests run|not required|read only|discovery only", normalized):
        return {
            "ran": False,
            "passed": False,
            "label": "TESTS NOT RUN",
            "details": "Proof dir adapter: tests were not run according to RESULT.md metadata",
            "checks": [],
        }
    if re.search(r"test fail|tests fail|lint fail|typecheck fail|build fail|validation fail", normalized):
        return {
            "ran": True,
            "passed": False,
            "label": "TESTS FAIL",
            "details": "Proof dir adapter: failing test/validation command evidence from RESULT.md metadata",
            "checks": [],
        }
    ran = bool(
        re.search(
            r"lint pass|typecheck pass|test pass|tests pass|build pass|focused .* pass|"
            r"shell syntax pass|validate .* pass|validation .* pass",
            normalized,
        )
    )
    result_passed = _status(fields.get("RESULT", status_value)) in PASS_STATUSES
    if ran:
        return {
            "ran": True,
            "passed": result_passed,
            "label": "TESTS PASS" if result_passed else "TESTS FAIL",
            "details": "Proof dir adapter: test/validation command evidence from RESULT.md metadata",
            "checks": [],
        }
    if result_passed:
        return {
            "ran": False,
            "passed": False,
            "label": "TESTS NOT RUN",
            "details": "Proof dir adapter: proof passed, but no test-run evidence was found",
            "checks": [],
        }
    return {
        "ran": True,
        "passed": False,
        "label": "TESTS FAIL",
        "details": "Proof dir adapter: failing RESULT.md status",
        "checks": [],
    }


def _parse_time(value: object) -> dt.datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def _proof_start(fields: dict[str, str], proof_dir: Path) -> tuple[dt.datetime | None, str]:
    for key in ("STARTED_AT", "SESSION_STARTED_AT", "START_TIME"):
        if parsed := _parse_time(fields.get(key)):
            return parsed, f"RESULT.md:{key}"
    match = re.search(r"_(\d{8}T\d{6}Z)$", proof_dir.name)
    if match:
        parsed = dt.datetime.strptime(match.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=dt.timezone.utc)
        return parsed, "proof_directory_timestamp"
    return None, "unknown"


def _duration(fields: dict[str, str], proof_dir: Path, completed_at: str) -> dict[str, Any]:
    for key in ("DURATION_MINUTES", "ELAPSED_MINUTES"):
        raw = fields.get(key, "")
        try:
            minutes = float(raw)
        except ValueError:
            continue
        if minutes > 0:
            return {
                "duration_minutes": minutes,
                "duration_source": f"RESULT.md:{key}",
                "started_at": None,
                "completed_at": completed_at,
            }

    start, source = _proof_start(fields, proof_dir)
    end = None
    for key in ("COMPLETED_AT", "ENDED_AT", "SESSION_ENDED_AT", "END_TIME"):
        if parsed := _parse_time(fields.get(key)):
            end = parsed
            completed_at = parsed.isoformat().replace("+00:00", "Z")
            source = f"{source}+RESULT.md:{key}"
            break
    if end is None:
        end = _parse_time(completed_at)
        source = f"{source}+report_timestamp" if start else "unknown"
    if not start or not end:
        return {
            "duration_minutes": None,
            "duration_source": "unknown",
            "started_at": start.isoformat().replace("+00:00", "Z") if start else None,
            "completed_at": completed_at or None,
        }
    seconds = (end - start).total_seconds()
    if seconds <= 0:
        return {
            "duration_minutes": None,
            "duration_source": "unknown",
            "started_at": start.isoformat().replace("+00:00", "Z"),
            "completed_at": completed_at or None,
        }
    return {
        "duration_minutes": max(1, math.ceil(seconds / 60)),
        "duration_source": source,
        "started_at": start.isoformat().replace("+00:00", "Z"),
        "completed_at": completed_at,
    }


def _safe_artifact_name(name: str) -> str:
    return "[REDACTED ARTIFACT NAME]" if SENSITIVE_NAME.search(name) else name


def _artifacts(proof_dir: Path) -> dict[str, Any]:
    directory_names = sorted(
        _safe_artifact_name(path.name)
        for path in proof_dir.iterdir()
        if path.is_file()
    )
    names = [name for name in directory_names if name not in ADAPTER_CONTROL_FILES]
    excluded = [name for name in directory_names if name in ADAPTER_CONTROL_FILES]
    return {
        "directory_files_total": len(directory_names),
        "proof_files_total": len(names),
        "displayed_count": len(names),
        "displayed_files": names,
        "excluded_count": len(excluded),
        "excluded_files": excluded,
        "filter_explanation": (
            f"All {len(names)} evidence artifact names are displayed; {len(excluded)} adapter control files "
            "(RESULT.md and harness metadata) are excluded from the proof-artifact count, and contents are not embedded."
        ),
    }


def _next_action(fields: dict[str, str], summary: str, override: str = "") -> str:
    if override.strip():
        return override.strip()[:2000]
    for key in ("NEXT_STEP", "NEXT_RECOMMENDED_ACTION"):
        if fields.get(key, "").strip():
            return fields[key].strip()[:2000]
    match = re.search(r"(?i)\bnext step:\s*(.+)$", summary.strip())
    return match.group(1).strip()[:2000] if match else ""


def collect_report_evidence(
    proof_dir: str | Path,
    result_file: str | Path,
    status_value: str,
    completed_at: str,
    summary: str = "",
    next_action_override: str = "",
) -> dict[str, Any]:
    proof_path = Path(proof_dir)
    fields = parse_result_fields(result_file)
    tests = _classify_tests(fields, proof_path, status_value)
    artifacts = _artifacts(proof_path)
    duration = _duration(fields, proof_path, completed_at)
    next_action = _next_action(fields, summary, next_action_override)
    underlying_functional_qa = fields.get("UNDERLYING_FUNCTIONAL_QA") or None
    if underlying_functional_qa is None and re.search(r"isolated\s+qa(?:\s+rerun)?\s+pass", summary, re.I):
        underlying_functional_qa = "PASS"

    pushed = _bool_value(fields.get("PUSHED"))
    production_storage = "unknown"
    for key in ("PRODUCTION_STORAGE_ACTIVE", "STORAGE_ACCEPTED_FOR_PRODUCTION"):
        value = _bool_value(fields.get(key))
        if value is not None:
            production_storage = "active" if value else "inactive"
            break
    if production_storage == "unknown" and re.search(r"production storage inactive", summary, re.I):
        production_storage = "inactive"

    return {
        "result_fields": fields,
        "tests": tests,
        "validation_summary": tests["details"],
        "artifacts": artifacts,
        "duration": duration,
        "next_action": next_action,
        "run_id": fields.get("RUN_ID_CREATED") or fields.get("RUN_ID") or None,
        "subject_id": fields.get("SUBJECT_ID_CREATED") or fields.get("SUBJECT_ID") or None,
        "pushed": pushed,
        "production_storage_state": production_storage,
        "underlying_functional_qa": underlying_functional_qa,
        "manual_qa_status": fields.get("MANUAL_QA_STATUS") or None,
        "operator_qa": fields.get("OPERATOR_QA") or None,
    }


if __name__ == "__main__":
    raise SystemExit("proof_report_evidence.py is an import-only helper")
