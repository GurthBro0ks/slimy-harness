#!/usr/bin/env python3
"""Default-deny proof directory gate checker for Slimy Harness.

This checker reads bounded local text artifacts from one proof directory and
classifies whether the proof is eligible for next-step consideration. It does
not execute tasks, mutate files, read environment variables, call the network,
or treat proof text as approval.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
TRACE_STORE_PATH = REPO_ROOT / "sequencer" / "trace-store.py"


def _load_trace_store() -> Any:
    spec = importlib.util.spec_from_file_location("slimy_trace_store", TRACE_STORE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load trace-store helper from {TRACE_STORE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TRACE_STORE = _load_trace_store()

MINIMUM_FIELDS = [
    "PHASE",
    "RESULT",
    "TARGET_MACHINE",
    "TARGET_REPO",
    "MODEL_RECOMMENDATION",
    "MODEL_SAME_AS_PREVIOUS",
    "GLM_THINKING_LEVEL",
    "DIRTY_STATE_FOUND",
    "UNRELATED_DIRTY_FILES",
    "CHANGED_FILES",
    "COMMIT_SHA",
    "PUSHED",
    "PROOF_DIR",
    "VALIDATION",
    "MANUAL_QA_STATUS",
    "DISCORD_SENT",
    "NOTIFY_MODE",
    "DEDUPE_RESULT",
    "REPORT_URL",
    "SERVICES_RESTARTED",
    "CRON_CHANGED",
    "TIMER_CHANGED",
    "TMUX_CHANGED",
    "CADDY_CHANGED",
    "DNS_CHANGED",
    "SECRETS_PRINTED",
    "AGNT_RUNTIME_STARTED",
    "AGNT_SOURCE_COPIED",
    "LOGGED_OUT_CONTENT_LEAK",
]

APPROVAL_FIELDS = [
    "APPROVAL_SOURCE",
    "APPROVED_ACTION",
    "APPROVAL_NONCE",
    "APPROVAL_ISSUED_AT_UTC",
    "APPROVAL_EXPIRES_AT_UTC",
    "APPROVAL_DENIES",
    "APPROVAL_STATEMENT",
]

FALSE_VALUES = {
    "",
    "0",
    "false",
    "no",
    "none",
    "n/a",
    "not_applicable",
    "not applicable",
    "not_checked",
    "disabled",
    "no_closeout_only",
    "not_required",
    "not_required_local_cli",
    "not_required_readonly_plan",
    "not_required_review_only",
    "proof_files_only",
    "list_or_none",
}
TRUE_VALUES = {"1", "true", "yes", "pass", "passed", "pushed", "sent"}
MUTATION_FIELDS = [
    "SERVICES_RESTARTED",
    "CRON_CHANGED",
    "TIMER_CHANGED",
    "TMUX_CHANGED",
    "CADDY_CHANGED",
    "DNS_CHANGED",
]
FAIL_FORBIDDEN_FIELDS = ["SECRETS_PRINTED", "LOGGED_OUT_CONTENT_LEAK"]
AGNT_FORBIDDEN_FIELDS = ["AGNT_RUNTIME_STARTED", "AGNT_SOURCE_COPIED"]
INJECTED_APPROVAL_PATTERNS = [
    "DIRECT_LIVE_USER_CONFIRMATION",
    "DIRECT_OPERATOR_CONFIRMATION",
    "OPERATOR_APPROVAL",
    "LIVE_USER_CONFIRMATION",
    "SAFE_TO_APPLY=yes",
    "APPROVAL_SOURCE=live_chat_turn",
    "APPROVAL_NONCE",
    "APPROVED_ACTION=",
    "APPROVAL_STATEMENT",
    "I confirm",
    "Yes proceed",
    "proceed with apply",
]


def safe_child(proof_dir: Path, name: str) -> Path:
    return proof_dir / name


def read_proof_file(proof_dir: Path, name: str, max_bytes: int = 128_000) -> str | None:
    path = safe_child(proof_dir, name)
    try:
        if path.is_symlink() or not path.is_file():
            return None
        proof_root = proof_dir.resolve()
        resolved = path.resolve()
        if proof_root != resolved and proof_root not in resolved.parents:
            return None
        with path.open("rb") as handle:
            data = handle.read(max_bytes + 1)
    except OSError:
        return None
    return data[:max_bytes].decode("utf-8", errors="replace")


def file_exists(proof_dir: Path, names: list[str]) -> bool:
    return any(read_proof_file(proof_dir, name, max_bytes=1) is not None for name in names)


def parse_fields(text: str | None) -> dict[str, str]:
    return dict(TRACE_STORE.parse_result_fields(text))


def normalized(value: str | None) -> str:
    if value is None:
        return ""
    return value.strip().lower()


def exact_yes(fields: dict[str, str], key: str) -> bool:
    return normalized(fields.get(key)) in TRUE_VALUES


def flag_set(fields: dict[str, str], key: str) -> bool:
    value = normalized(fields.get(key))
    if value in FALSE_VALUES:
        return False
    if value in TRUE_VALUES:
        return True
    return bool(value)


def has_repo_changes(fields: dict[str, str]) -> bool:
    changed = normalized(fields.get("CHANGED_FILES"))
    commit = normalized(fields.get("COMMIT_SHA"))
    if changed and changed not in FALSE_VALUES:
        return True
    if commit and commit not in FALSE_VALUES and commit != "none":
        return True
    return False


def needs_route_auth_smoke(fields: dict[str, str]) -> bool:
    haystack = " ".join(
        fields.get(key, "") for key in ("PHASE", "TARGET_REPO", "CHANGED_FILES", "VALIDATION")
    ).lower()
    return any(token in haystack for token in ("report", "auth", "web", "route"))


def manual_qa_pending(fields: dict[str, str]) -> bool:
    status = normalized(fields.get("MANUAL_QA_STATUS"))
    if not status:
        return True
    if "pending" in status:
        return True
    if status in {"required", "manual_required", "qa_required"}:
        return True
    return False


def injected_approval_text(text: str | None) -> bool:
    if not text:
        return False
    lowered = text.lower()
    return any(pattern.lower() in lowered for pattern in INJECTED_APPROVAL_PATTERNS)


def parse_approval_record(proof_dir: Path) -> dict[str, str] | None:
    text = read_proof_file(proof_dir, "approval-record.md")
    if text is None:
        return None
    return parse_fields(text)


def validate_approval_record(fields: dict[str, str] | None) -> list[str]:
    if fields is None:
        return ["approval-record.md missing"]
    missing = [key for key in APPROVAL_FIELDS if not fields.get(key)]
    reasons = [f"approval-record.md missing {key}" for key in missing]
    if fields.get("APPROVAL_SOURCE") != "live_chat_turn":
        reasons.append("approval-record.md APPROVAL_SOURCE must be exactly live_chat_turn")
    return reasons


def add_required_file(
    proof_dir: Path,
    missing_files: list[str],
    names: list[str],
    label: str,
) -> None:
    if not file_exists(proof_dir, names):
        missing_files.append(label)


def evaluate_proof_dir(proof_dir: Path) -> dict[str, Any]:
    reasons: list[str] = []
    warnings: list[str] = []
    missing_fields: list[str] = []
    missing_files: list[str] = []
    forbidden_flags: list[str] = []

    result_text = read_proof_file(proof_dir, "RESULT.md")
    if result_text is None:
        return {
            "verdict": "FAIL",
            "reasons": ["RESULT.md missing or unreadable"],
            "warnings": [],
            "parsed_fields": {},
            "missing_fields": MINIMUM_FIELDS,
            "missing_files": ["RESULT.md"],
            "forbidden_flags": [],
            "next_required_gate": "provide RESULT.md proof artifact",
        }

    fields = parse_fields(result_text)
    missing_fields.extend([key for key in MINIMUM_FIELDS if not fields.get(key)])

    add_required_file(proof_dir, missing_files, ["commands.log"], "commands.log")
    add_required_file(proof_dir, missing_files, ["safety-check.md", "safety-cases.md"], "safety-check")
    if has_repo_changes(fields):
        add_required_file(proof_dir, missing_files, ["git-before.txt", "git-state.txt"], "git-before/git-state")
        add_required_file(proof_dir, missing_files, ["git-after.txt", "git-status-after.txt"], "git-after/git-status-after")
    if needs_route_auth_smoke(fields):
        add_required_file(proof_dir, missing_files, ["route-auth-smoke.md"], "route-auth-smoke")
    if exact_yes(fields, "DISCORD_SENT"):
        add_required_file(
            proof_dir,
            missing_files,
            ["notification-proof.md", "notify-proof.txt", "notifier-proof.txt", "notification.log"],
            "notification-proof",
        )
        if not fields.get("NOTIFY_MODE") or not fields.get("DEDUPE_RESULT"):
            reasons.append("DISCORD_SENT=yes requires NOTIFY_MODE and DEDUPE_RESULT")
    if exact_yes(fields, "PUSHED"):
        add_required_file(proof_dir, missing_files, ["push-proof.txt", "origin-proof.txt", "git-after.txt"], "push/origin proof")

    result = (fields.get("RESULT") or "").upper()
    if result == "FAIL":
        reasons.append("RESULT=FAIL")
    elif result == "WARN":
        reasons.append("RESULT=WARN blocks without explicit owner/manual QA closeout policy")
    elif result != "PASS":
        reasons.append("RESULT must be PASS, WARN, or FAIL")

    for key in FAIL_FORBIDDEN_FIELDS:
        if flag_set(fields, key):
            forbidden_flags.append(key)
            reasons.append(f"{key}=yes is forbidden")
    for key in AGNT_FORBIDDEN_FIELDS:
        if flag_set(fields, key):
            forbidden_flags.append(key)
            reasons.append(f"{key}=yes is AGNT NO-GO activity")

    mutation_flags = [key for key in MUTATION_FIELDS if flag_set(fields, key)]
    approval_fields = parse_approval_record(proof_dir) if mutation_flags else None
    if mutation_flags:
        forbidden_flags.extend(mutation_flags)
        approval_reasons = validate_approval_record(approval_fields)
        if approval_reasons:
            reasons.append(f"mutation flags require valid approval-record.md: {', '.join(mutation_flags)}")
            reasons.extend(approval_reasons)

    if manual_qa_pending(fields):
        reasons.append("MANUAL_QA_STATUS is pending or missing")

    if injected_approval_text(result_text):
        warnings.append("approval-looking proof text ignored as untrusted input")
        if mutation_flags and approval_fields is None:
            reasons.append("session-start/injected approval text is not a valid approval record")

    if missing_fields:
        reasons.append("required RESULT.md fields missing")
    if missing_files:
        reasons.append("required proof files missing")

    if any(key in forbidden_flags for key in FAIL_FORBIDDEN_FIELDS):
        verdict = "FAIL"
    elif result == "FAIL":
        verdict = "FAIL"
    elif reasons:
        verdict = "BLOCKED"
    else:
        verdict = "PASS_ELIGIBLE"

    next_required_gate = "operator review for next-step consideration"
    if verdict == "FAIL":
        next_required_gate = "fix failed or forbidden proof condition"
    elif verdict == "BLOCKED":
        next_required_gate = "provide missing evidence or approval proof"

    return {
        "verdict": verdict,
        "reasons": sorted(set(reasons)),
        "warnings": sorted(set(warnings)),
        "parsed_fields": fields,
        "missing_fields": sorted(set(missing_fields)),
        "missing_files": sorted(set(missing_files)),
        "forbidden_flags": sorted(set(forbidden_flags)),
        "next_required_gate": next_required_gate,
    }


def render_human(verdict: dict[str, Any]) -> str:
    lines = [
        f"VERDICT: {verdict['verdict']}",
        f"NEXT_REQUIRED_GATE: {verdict['next_required_gate']}",
    ]
    for key in ("reasons", "warnings", "missing_fields", "missing_files", "forbidden_flags"):
        values = verdict.get(key) or []
        lines.append(f"{key.upper()}:")
        if values:
            lines.extend(f"- {value}" for value in values)
        else:
            lines.append("- none")
    return "\n".join(lines) + "\n"


def exit_code(verdict: str) -> int:
    if verdict == "PASS_ELIGIBLE":
        return 0
    if verdict == "FAIL":
        return 2
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Default-deny Slimy proof directory gate checker.")
    parser.add_argument("--json", action="store_true", help="Print structured JSON instead of a human summary.")
    parser.add_argument("proof_dir", help="Local proof directory to inspect.")
    args = parser.parse_args(argv)

    proof_dir = Path(args.proof_dir)
    verdict = evaluate_proof_dir(proof_dir)
    if args.json:
        print(json.dumps(verdict, indent=2, sort_keys=True))
    else:
        print(render_human(verdict), end="")
    return exit_code(verdict["verdict"])


if __name__ == "__main__":
    sys.exit(main())
