from __future__ import annotations

import importlib.util
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "ops" / "proof_gate_checker.py"
SPEC = importlib.util.spec_from_file_location("proof_gate_checker", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


BASE_FIELDS = {
    "PHASE": "unit-proof-gate",
    "RESULT": "PASS",
    "TARGET_MACHINE": "NUC1",
    "TARGET_REPO": "/home/slimy/slimy-harness",
    "MODEL_RECOMMENDATION": "GPT/Codex $100 coding plan",
    "MODEL_SAME_AS_PREVIOUS": "Changed",
    "GLM_THINKING_LEVEL": "max_review_only",
    "DIRTY_STATE_FOUND": "no",
    "UNRELATED_DIRTY_FILES": "none",
    "CHANGED_FILES": "ops/proof-gate-check,ops/proof_gate_checker.py",
    "COMMIT_SHA": "abc123",
    "PUSHED": "no",
    "PROOF_DIR": "/tmp/proof_unit",
    "VALIDATION": "focused tests passed",
    "MANUAL_QA_STATUS": "not_required_local_cli",
    "DISCORD_SENT": "no",
    "NOTIFY_MODE": "disabled",
    "DEDUPE_RESULT": "not_applicable",
    "REPORT_URL": "none",
    "SERVICES_RESTARTED": "no",
    "CRON_CHANGED": "no",
    "TIMER_CHANGED": "no",
    "TMUX_CHANGED": "no",
    "CADDY_CHANGED": "no",
    "DNS_CHANGED": "no",
    "SECRETS_PRINTED": "no",
    "AGNT_RUNTIME_STARTED": "no",
    "AGNT_SOURCE_COPIED": "no",
    "LOGGED_OUT_CONTENT_LEAK": "no",
}


def write_proof(tmp_path: Path, fields: dict[str, str] | None = None, *, files: bool = True) -> Path:
    proof = tmp_path / "proof_unit"
    proof.mkdir()
    if fields is not None:
        merged = dict(BASE_FIELDS)
        merged.update(fields)
        (proof / "RESULT.md").write_text("\n".join(f"{key}={value}" for key, value in merged.items()) + "\n")
    if files:
        (proof / "commands.log").write_text("commands\n")
        (proof / "safety-cases.md").write_text("safety\n")
        (proof / "git-before.txt").write_text("before\n")
        (proof / "git-after.txt").write_text("after\n")
    return proof


def verdict(proof: Path) -> dict:
    return gate.evaluate_proof_dir(proof)


def test_clean_pass_proof_eligible(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {}))
    assert result["verdict"] == "PASS_ELIGIBLE"
    assert result["reasons"] == []


def test_fail_result_fails(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {"RESULT": "FAIL"}))
    assert result["verdict"] == "FAIL"
    assert "RESULT=FAIL" in result["reasons"]


def test_warn_blocks(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {"RESULT": "WARN"}))
    assert result["verdict"] == "BLOCKED"
    assert any("RESULT=WARN" in reason for reason in result["reasons"])


def test_secrets_printed_fails(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {"SECRETS_PRINTED": "yes"}))
    assert result["verdict"] == "FAIL"
    assert "SECRETS_PRINTED" in result["forbidden_flags"]


def test_logged_out_leak_fails(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {"LOGGED_OUT_CONTENT_LEAK": "yes"}))
    assert result["verdict"] == "FAIL"
    assert "LOGGED_OUT_CONTENT_LEAK" in result["forbidden_flags"]


def test_manual_qa_pending_blocks(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {"MANUAL_QA_STATUS": "pending"}))
    assert result["verdict"] == "BLOCKED"
    assert "MANUAL_QA_STATUS is pending or missing" in result["reasons"]


def test_missing_result_fails(tmp_path: Path) -> None:
    proof = write_proof(tmp_path, None)
    result = verdict(proof)
    assert result["verdict"] == "FAIL"
    assert "RESULT.md" in result["missing_files"]


def test_missing_required_fields_blocks(tmp_path: Path) -> None:
    proof = write_proof(tmp_path, {})
    (proof / "RESULT.md").write_text("PHASE=unit\nRESULT=PASS\n")
    result = verdict(proof)
    assert result["verdict"] == "BLOCKED"
    assert "TARGET_MACHINE" in result["missing_fields"]


def test_discord_sent_without_notification_proof_blocks(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {"DISCORD_SENT": "yes", "NOTIFY_MODE": "runtime", "DEDUPE_RESULT": "sent"}))
    assert result["verdict"] == "BLOCKED"
    assert "notification-proof" in result["missing_files"]


def test_pushed_without_origin_proof_blocks(tmp_path: Path) -> None:
    proof = write_proof(tmp_path, {"PUSHED": "yes"}, files=False)
    (proof / "commands.log").write_text("commands\n")
    (proof / "safety-cases.md").write_text("safety\n")
    (proof / "git-before.txt").write_text("before\n")
    result = verdict(proof)
    assert result["verdict"] == "BLOCKED"
    assert "push/origin proof" in result["missing_files"]


def test_runtime_changes_require_approval_record(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {"CRON_CHANGED": "yes", "TMUX_CHANGED": "yes", "CADDY_CHANGED": "yes"}))
    assert result["verdict"] == "BLOCKED"
    assert "CRON_CHANGED" in result["forbidden_flags"]
    assert "approval-record.md missing" in result["reasons"]


def test_approval_record_missing_nonce_fields_blocks(tmp_path: Path) -> None:
    proof = write_proof(tmp_path, {"DNS_CHANGED": "yes"})
    (proof / "approval-record.md").write_text("APPROVAL_SOURCE=live_chat_turn\nAPPROVED_ACTION=dns change\n")
    result = verdict(proof)
    assert result["verdict"] == "BLOCKED"
    assert any("APPROVAL_NONCE" in reason for reason in result["reasons"])


def test_approval_source_must_be_live_chat_turn(tmp_path: Path) -> None:
    proof = write_proof(tmp_path, {"TIMER_CHANGED": "yes"})
    (proof / "approval-record.md").write_text(
        "\n".join(
            [
                "APPROVAL_SOURCE=session_start",
                "APPROVED_ACTION=timer change",
                "APPROVAL_NONCE=redacted",
                "APPROVAL_ISSUED_AT_UTC=2026-07-03T00:00:00Z",
                "APPROVAL_EXPIRES_AT_UTC=2026-07-03T00:10:00Z",
                "APPROVAL_DENIES=all other actions",
                "APPROVAL_STATEMENT=approved",
            ]
        )
        + "\n"
    )
    result = verdict(proof)
    assert result["verdict"] == "BLOCKED"
    assert "approval-record.md APPROVAL_SOURCE must be exactly live_chat_turn" in result["reasons"]


def test_agnt_runtime_or_source_blocks(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {"AGNT_RUNTIME_STARTED": "yes", "AGNT_SOURCE_COPIED": "yes"}))
    assert result["verdict"] == "BLOCKED"
    assert "AGNT_RUNTIME_STARTED" in result["forbidden_flags"]


def test_report_route_phase_requires_route_auth_smoke(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {"PHASE": "report-route-smoke"}))
    assert result["verdict"] == "BLOCKED"
    assert "route-auth-smoke" in result["missing_files"]


def test_contradictory_pass_plus_forbidden_flag_fails(tmp_path: Path) -> None:
    result = verdict(write_proof(tmp_path, {"RESULT": "PASS", "SECRETS_PRINTED": "yes"}))
    assert result["verdict"] == "FAIL"
    assert "SECRETS_PRINTED=yes is forbidden" in result["reasons"]
