#!/usr/bin/env python3
"""Local Model Routing Phase 3 — Dry-Run Route Helper.

Read-only, deterministic, policy-only decision helper. Inspects
``config/local-model-routing.policy.json`` and prints a routing
decision for a proposed task.

This helper MUST NOT:
  * call Ollama
  * pull models
  * open a network socket
  * read or print secrets
  * send Discord messages
  * modify runtime state
  * execute subprocess commands

It is intentionally limited to: argparse, json, pathlib, sys.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

VALID_RISKS = ("LOW", "MEDIUM", "HIGH")
VALID_MACHINES = ("nuc1", "nuc2")

DENY_REASON_HIGH_RISK = "high_risk_denied"
DENY_REASON_PROTECTED_SURFACE = "protected_surface_denied"
DENY_REASON_NUC2_DISABLED = "nuc2_local_inference_disabled"
DENY_REASON_TASK = "denied_task"
DENY_REASON_DEFAULT = "default_deny"
ALLOW_REASON_TINY_HELPER = "tiny_helper_allowed"
ALLOW_REASON_BATCH_REVIEW = "batch_only_requires_review"


def _emit(lines, key, value):
    lines.append(f"{key}={value}")


def decide(policy, task, risk, touches, machine, json_output):
    """Apply decision rules to policy + inputs and return (lines_dict, exit_code)."""
    if risk not in VALID_RISKS:
        raise SystemExit(_fail(f"invalid_risk:{risk}", json_output))
    if machine not in VALID_MACHINES:
        raise SystemExit(_fail(f"invalid_machine:{machine}", json_output))
    if not task:
        raise SystemExit(_fail("missing_task", json_output))

    machines = policy.get("machines", {})
    nuc1_ollama = machines.get("nuc1", {}).get("ollama", {})
    qwen = nuc1_ollama.get("allowedModels", {}).get("qwen2.5:1.5b", {})
    denied_tasks = set(qwen.get("deniedTasks", []))
    allowed_tiny = set(qwen.get("allowedTinyHelperTasks", []))
    routing = policy.get("routingRules", {})
    protected_surfaces = set(routing.get("protectedSurfaces", {}).get("surfaces", []))

    target = "nuc1:qwen2.5:1.5b"
    model = "qwen2.5:1.5b"
    mode = "none"
    max_tokens = 0
    requires_review = "no"
    allowed = False
    reason = DENY_REASON_DEFAULT

    if risk == "HIGH":
        reason = DENY_REASON_HIGH_RISK
    elif touches & protected_surfaces:
        reason = DENY_REASON_PROTECTED_SURFACE
    elif machine == "nuc2":
        reason = DENY_REASON_NUC2_DISABLED
    elif task in denied_tasks:
        reason = DENY_REASON_TASK
    elif task in allowed_tiny:
        allowed = True
        mode = "advisory"
        max_tokens = int(routing.get("tinyClassification", {}).get("maxOutputTokens", 8))
        reason = ALLOW_REASON_TINY_HELPER
    elif task in routing.get("resultMdDraft", {}) or task == "resultMdDraft":
        rule = routing.get("resultMdDraft", {})
        if rule.get("localModelAllowed") is True:
            allowed = True
            mode = rule.get("mode", "batch_only")
            max_tokens = int(rule.get("maxOutputTokens", 8)) if "maxOutputTokens" in rule else 0
            requires_review = "yes" if rule.get("requiresReview") else "no"
            reason = ALLOW_REASON_BATCH_REVIEW
        else:
            reason = DENY_REASON_DEFAULT
    else:
        reason = DENY_REASON_DEFAULT

    lines = []
    _emit(lines, "PHASE", "local-model-routing-dry-run-route")
    _emit(lines, "RESULT", "PASS")
    _emit(lines, "DRY_RUN_ONLY", "yes")
    _emit(lines, "LIVE_ROUTING_ENABLED", "no")
    _emit(lines, "OLLAMA_CALLED", "no")
    _emit(lines, "MODELS_PULLED", "no")
    _emit(lines, "TASK", task)
    _emit(lines, "RISK", risk)
    _emit(lines, "TOUCHES", ",".join(touches) if touches else "none")
    _emit(lines, "MACHINE", machine)
    _emit(lines, "LOCAL_MODEL_ALLOWED", "yes" if allowed else "no")
    _emit(lines, "TARGET", target if allowed else "none")
    _emit(lines, "MODEL", model if allowed else "none")
    _emit(lines, "MODE", mode if allowed and mode != "none" else "none")
    _emit(lines, "MAX_OUTPUT_TOKENS", str(max_tokens) if allowed and max_tokens else "none")
    _emit(lines, "REQUIRES_REVIEW", requires_review)
    _emit(lines, "REASON", reason)

    if json_output:
        payload = {k.split("=", 1)[0]: k.split("=", 1)[1] for k in lines}
        sys.stdout.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    else:
        sys.stdout.write("\n".join(lines) + "\n")
    return 0


def _fail(reason, json_output):
    lines = [
        "PHASE=local-model-routing-dry-run-route",
        "RESULT=FAIL",
        f"REASON={reason}",
    ]
    if json_output:
        payload = {k.split("=", 1)[0]: k.split("=", 1)[1] for k in lines}
        sys.stdout.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    else:
        sys.stdout.write("\n".join(lines) + "\n")
    return 1


def parse_touches(raw):
    if not raw:
        return frozenset()
    parts = [p.strip() for p in raw.split(",") if p.strip()]
    return frozenset(parts)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="dry-run-route",
        description="Phase 3 dry-run route helper (policy-only, read-only).",
    )
    parser.add_argument(
        "--policy",
        default="config/local-model-routing.policy.json",
        help="Path to the local model routing policy JSON.",
    )
    parser.add_argument("--task", required=True, help="Task name to evaluate.")
    parser.add_argument(
        "--risk",
        default="LOW",
        choices=VALID_RISKS,
        help="Risk level (LOW, MEDIUM, HIGH).",
    )
    parser.add_argument(
        "--touches",
        default="none",
        help="Comma-separated surface list (e.g. secrets,caddy).",
    )
    parser.add_argument(
        "--machine",
        default="nuc1",
        choices=VALID_MACHINES,
        help="Target machine (nuc1 or nuc2).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON output in addition to key/value.",
    )
    args = parser.parse_args(argv)

    policy_path = Path(args.policy)
    if not policy_path.exists():
        return _fail(f"policy_not_found:{policy_path}", args.json)
    try:
        policy = json.loads(policy_path.read_text())
    except json.JSONDecodeError as exc:
        return _fail(f"policy_parse_error:{exc.msg}", args.json)

    touches = parse_touches(args.touches)
    return decide(policy, args.task, args.risk, touches, args.machine, args.json)


if __name__ == "__main__":
    sys.exit(main())
