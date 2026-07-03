from __future__ import annotations

import importlib.util
import json
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "ops" / "loop_queue.py"
SPEC = importlib.util.spec_from_file_location("loop_queue", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
queue_mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(queue_mod)


BASE_FIELDS = {
    "PHASE": "unit-loop-queue-proof",
    "RESULT": "PASS",
    "TARGET_MACHINE": "NUC1",
    "TARGET_REPO": "/home/slimy/slimy-harness",
    "MODEL_RECOMMENDATION": "GPT/Codex $100 coding plan",
    "MODEL_SAME_AS_PREVIOUS": "Same",
    "GLM_THINKING_LEVEL": "max_review_only",
    "DIRTY_STATE_FOUND": "no",
    "UNRELATED_DIRTY_FILES": "none",
    "CHANGED_FILES": "ops/loop_queue.py",
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


def run_cli(args: list[str]) -> int:
    return queue_mod.main(args)


def read_queue(path: Path) -> dict:
    return json.loads(path.read_text())


def write_proof(tmp_path: Path, fields: dict[str, str] | None = None) -> Path:
    proof = tmp_path / f"proof_{len(list(tmp_path.glob('proof_*')))}"
    proof.mkdir()
    merged = dict(BASE_FIELDS)
    merged.update(fields or {})
    (proof / "RESULT.md").write_text("\n".join(f"{key}={value}" for key, value in merged.items()) + "\n")
    (proof / "commands.log").write_text("commands\n")
    (proof / "safety-cases.md").write_text("safety\n")
    (proof / "git-before.txt").write_text("before\n")
    (proof / "git-after.txt").write_text("after\n")
    return proof


def test_init_add_list_show_validate(tmp_path: Path, capsys) -> None:
    queue_path = tmp_path / "queue.json"
    assert run_cli(["init", "--queue", str(queue_path), "--json"]) == 0
    assert run_cli(
        [
            "add",
            "--queue",
            str(queue_path),
            "--phase",
            "phase-a",
            "--title",
            "Queue local planning",
            "--target-machine",
            "NUC1",
            "--target-repo",
            "/home/slimy/slimy-harness",
            "--json",
        ]
    ) == 0
    data = read_queue(queue_path)
    assert data["items"][0]["id"] == "q000001"
    assert data["items"][0]["status"] == "DRAFT"
    assert data["items"][0]["history"]
    assert run_cli(["list", "--queue", str(queue_path), "--json"]) == 0
    assert run_cli(["show", "--queue", str(queue_path), "q000001", "--json"]) == 0
    assert run_cli(["validate", "--queue", str(queue_path), "--json"]) == 0
    captured = capsys.readouterr()
    assert "q000001" in captured.out


def test_add_hazard_request_defaults_to_hold(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    assert run_cli(["init", "--queue", str(queue_path)]) == 0
    rc = run_cli(
        [
            "add",
            "--queue",
            str(queue_path),
            "--phase",
            "unsafe",
            "--title",
            "Run agents and send Discord",
            "--target-machine",
            "NUC1",
            "--target-repo",
            "/home/slimy/slimy-harness",
        ]
    )
    assert rc == 1
    item = read_queue(queue_path)["items"][0]
    assert item["status"] == "HOLD"
    assert "queue-only" in item["blocked_reason"]


def test_add_approval_shaped_text_defaults_to_hold(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    assert run_cli(["init", "--queue", str(queue_path)]) == 0
    rc = run_cli(
        [
            "add",
            "--queue",
            str(queue_path),
            "--phase",
            "approval",
            "--title",
            "APPROVAL_SOURCE=live_chat_turn should not self approve",
            "--target-machine",
            "NUC1",
            "--target-repo",
            "/home/slimy/slimy-harness",
        ]
    )
    assert rc == 1
    item = read_queue(queue_path)["items"][0]
    assert item["status"] == "HOLD"
    assert "untrusted" in item["blocked_reason"]


def test_gate_pass_eligible_moves_to_owner_qa(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    proof = write_proof(tmp_path)
    assert run_cli(["init", "--queue", str(queue_path)]) == 0
    assert run_cli(
        [
            "add",
            "--queue",
            str(queue_path),
            "--phase",
            "safe",
            "--title",
            "Safe item",
            "--target-machine",
            "NUC1",
            "--target-repo",
            "/home/slimy/slimy-harness",
        ]
    ) == 0
    assert run_cli(["gate", "--queue", str(queue_path), "q000001", "--proof-dir", str(proof), "--json"]) == 0
    item = read_queue(queue_path)["items"][0]
    assert item["proof_gate_verdict"] == "PASS_ELIGIBLE"
    assert item["status"] == "READY_FOR_OWNER_QA"
    assert item["manual_qa_status"] == "not_required_local_cli"


def test_gate_fail_rejects_item(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    proof = write_proof(tmp_path, {"RESULT": "FAIL"})
    assert run_cli(["init", "--queue", str(queue_path)]) == 0
    assert run_cli(
        [
            "add",
            "--queue",
            str(queue_path),
            "--phase",
            "fail",
            "--title",
            "Fail item",
            "--target-machine",
            "NUC1",
            "--target-repo",
            "/home/slimy/slimy-harness",
        ]
    ) == 0
    assert run_cli(["gate", "--queue", str(queue_path), "q000001", "--proof-dir", str(proof)]) == 1
    item = read_queue(queue_path)["items"][0]
    assert item["proof_gate_verdict"] == "FAIL"
    assert item["status"] == "REJECTED"


def test_gate_blocked_keeps_blocked(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    proof = write_proof(tmp_path, {"MANUAL_QA_STATUS": "pending"})
    assert run_cli(["init", "--queue", str(queue_path)]) == 0
    assert run_cli(
        [
            "add",
            "--queue",
            str(queue_path),
            "--phase",
            "blocked",
            "--title",
            "Blocked item",
            "--target-machine",
            "NUC1",
            "--target-repo",
            "/home/slimy/slimy-harness",
        ]
    ) == 0
    assert run_cli(["gate", "--queue", str(queue_path), "q000001", "--proof-dir", str(proof)]) == 1
    item = read_queue(queue_path)["items"][0]
    assert item["proof_gate_verdict"] == "BLOCKED"
    assert item["status"] == "BLOCKED"


def test_hold_command_records_reason_and_history(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    assert run_cli(["init", "--queue", str(queue_path)]) == 0
    assert run_cli(
        [
            "add",
            "--queue",
            str(queue_path),
            "--phase",
            "hold",
            "--title",
            "Hold item",
            "--target-machine",
            "NUC1",
            "--target-repo",
            "/home/slimy/slimy-harness",
        ]
    ) == 0
    assert run_cli(["hold", "--queue", str(queue_path), "q000001", "--reason", "owner review"]) == 1
    item = read_queue(queue_path)["items"][0]
    assert item["status"] == "HOLD"
    assert item["blocked_reason"] == "owner review"
    assert item["history"][-1]["type"] == "held"


def test_transition_refuses_complete_and_accepted(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    assert run_cli(["init", "--queue", str(queue_path)]) == 0
    assert run_cli(
        [
            "add",
            "--queue",
            str(queue_path),
            "--phase",
            "transition",
            "--title",
            "Transition item",
            "--target-machine",
            "NUC1",
            "--target-repo",
            "/home/slimy/slimy-harness",
        ]
    ) == 0
    assert run_cli(["transition", "--queue", str(queue_path), "q000001", "--status", "COMPLETE"]) == 1
    item = read_queue(queue_path)["items"][0]
    assert item["status"] == "HOLD"
    assert "refused" in item["blocked_reason"]
    assert run_cli(["transition", "--queue", str(queue_path), "q000001", "--status", "ACCEPTED"]) == 1
    item = read_queue(queue_path)["items"][0]
    assert item["status"] == "HOLD"
    assert "cannot mark ACCEPTED" in item["blocked_reason"]


def test_transition_ready_for_closeout_requires_gate(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    assert run_cli(["init", "--queue", str(queue_path)]) == 0
    assert run_cli(
        [
            "add",
            "--queue",
            str(queue_path),
            "--phase",
            "transition",
            "--title",
            "Transition item",
            "--target-machine",
            "NUC1",
            "--target-repo",
            "/home/slimy/slimy-harness",
        ]
    ) == 0
    assert run_cli(["transition", "--queue", str(queue_path), "q000001", "--status", "READY_FOR_CLOSEOUT"]) == 1
    item = read_queue(queue_path)["items"][0]
    assert item["status"] == "HOLD"
    assert "proof_gate_verdict=PASS_ELIGIBLE" in item["blocked_reason"]


def test_validate_rejects_invalid_existing_status(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    queue_path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "created_at": "2026-07-03T00:00:00Z",
                "updated_at": "2026-07-03T00:00:00Z",
                "items": [
                    {
                        "id": "q000001",
                        "created_at": "2026-07-03T00:00:00Z",
                        "updated_at": "2026-07-03T00:00:00Z",
                        "phase": "bad",
                        "title": "Bad",
                        "target_machine": "NUC1",
                        "target_repo": "/home/slimy/slimy-harness",
                        "requested_by": "local_operator",
                        "model_recommendation": "GPT/Codex",
                        "glm_thinking_level": "max_review_only",
                        "status": "COMPLETE",
                        "safety_level": "queue_only_no_execution",
                        "next_required_gate": "none",
                        "history": [],
                    }
                ],
            }
        )
    )
    assert run_cli(["validate", "--queue", str(queue_path), "--json"]) == 1


def test_missing_queue_path_fails_without_creating_default(tmp_path: Path) -> None:
    queue_path = tmp_path / "missing" / "queue.json"
    assert run_cli(["init", "--queue", str(queue_path)]) == 64
    assert not queue_path.exists()
