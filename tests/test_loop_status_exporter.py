from __future__ import annotations

import importlib.util
import json
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "ops" / "loop_status_exporter.py"
SPEC = importlib.util.spec_from_file_location("loop_status_exporter", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
exporter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exporter)


def write_queue(path: Path, items: list[dict]) -> None:
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "created_at": "2026-07-03T00:00:00Z",
                "updated_at": "2026-07-03T00:00:00Z",
                "items": items,
            }
        )
    )


def run_export(queue_path: Path, out_path: Path, proof_root: Path | None = None) -> dict:
    args = ["--queue", str(queue_path), "--out", str(out_path)]
    if proof_root is not None:
        args.extend(["--proof-root", str(proof_root)])
    assert exporter.main(args) == 0
    return json.loads(out_path.read_text())


def test_snapshot_schema_shape_and_safety_literals(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    out_path = tmp_path / "snapshot.json"
    write_queue(
        queue_path,
        [
            {
                "id": "q000001",
                "phase": "phase-one",
                "title": "Ready item",
                "target_machine": "NUC1",
                "target_repo": "/home/slimy/slimy-harness",
                "model_recommendation": "GPT/Codex $100 coding plan",
                "glm_thinking_level": "high_review_only",
                "status": "READY_FOR_OWNER_QA",
                "safety_level": "queue_only_no_execution",
                "proof_dir": "/tmp/proof_ready",
                "proof_gate_verdict": "PASS_ELIGIBLE",
                "manual_qa_status": "not_required_local_cli",
                "next_required_gate": "owner review",
                "blocked_reason": "",
                "updated_at": "2026-07-03T00:00:00Z",
            }
        ],
    )

    snapshot = run_export(queue_path, out_path)

    assert snapshot["schema_version"] == "loop-status.v1"
    assert snapshot["generator"] == "slimy-harness.loop_status_exporter"
    assert snapshot["summary"]["total_items"] == 1
    assert snapshot["summary"]["by_status"]["OK"] == 1
    assert snapshot["items"][0]["status"] == "OK"
    assert set(snapshot["items"][0]) == {
        "id",
        "phase",
        "title",
        "target_machine",
        "target_repo",
        "model_recommendation",
        "glm_thinking_level",
        "status",
        "safety_level",
        "proof_dir",
        "proof_gate_verdict",
        "manual_qa_status",
        "next_required_gate",
        "blocked_reason",
        "updated_at",
        "warnings_count",
        "reasons_count",
    }
    assert snapshot["safety"]["shell_execution_present"] is False
    assert snapshot["safety"]["mutation_controls_present"] is False
    assert snapshot["safety"]["request_time_shell_required"] is False
    assert snapshot["safety"]["secrets_redacted"] is True
    assert snapshot["safety"]["owner_gate_required_for_ui"] is True


def test_sanitizes_secret_like_strings_and_excludes_raw_fields(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    out_path = tmp_path / "snapshot.json"
    write_queue(
        queue_path,
        [
            {
                "id": "q000002",
                "phase": "Authorization: Bearer fixture-token",
                "title": "APPROVAL_STATEMENT=raw operator text",
                "target_machine": "NUC1",
                "target_repo": "https://example.invalid/action/secret",
                "model_recommendation": "BOT_SYNC_SECRET=fixture-value",
                "glm_thinking_level": "high_review_only",
                "status": "HOLD",
                "safety_level": "hold_requires_owner_review",
                "proof_dir": "/tmp/proof_secret",
                "proof_gate_verdict": "BLOCKED",
                "manual_qa_status": "pending",
                "next_required_gate": "raw cron line: * * * * * run",
                "blocked_reason": "API_TOKEN=fixture-value",
                "updated_at": "2026-07-03T00:00:00Z",
                "notes": "raw proof text should not be exported",
                "history": [{"message": "command output should not be exported"}],
            }
        ],
    )

    snapshot = run_export(queue_path, out_path)
    rendered = json.dumps(snapshot)

    assert "fixture-token" not in rendered
    assert "raw operator text" not in rendered
    assert "fixture-value" not in rendered
    assert "example.invalid/action" not in rendered
    assert "raw proof text" not in rendered
    assert "command output" not in rendered
    assert snapshot["items"][0]["status"] == "BLOCKED"
    assert snapshot["safety"]["secrets_redacted"] is True


def test_missing_queue_yields_unknown_snapshot_without_crash(tmp_path: Path) -> None:
    queue_path = tmp_path / "missing.json"
    out_path = tmp_path / "snapshot.json"

    snapshot = run_export(queue_path, out_path)

    assert snapshot["summary"]["total_items"] == 0
    assert snapshot["summary"]["highest_risk_state"] == "UNKNOWN"
    assert snapshot["summary"]["has_blockers"] is True
    assert snapshot["errors"]
    assert out_path.exists()


def test_invalid_queue_yields_unknown_snapshot_without_crash(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    out_path = tmp_path / "snapshot.json"
    queue_path.write_text("{not json")

    snapshot = run_export(queue_path, out_path)

    assert snapshot["summary"]["highest_risk_state"] == "UNKNOWN"
    assert snapshot["errors"]


def test_exporter_writes_only_explicit_output_path(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    out_path = tmp_path / "owner" / "snapshot.json"
    out_path.parent.mkdir()
    write_queue(queue_path, [])

    snapshot = run_export(queue_path, out_path)

    assert snapshot["summary"]["total_items"] == 0
    assert out_path.exists()
    assert sorted(path.relative_to(tmp_path).as_posix() for path in tmp_path.rglob("*") if path.is_file()) == [
        "owner/snapshot.json",
        "queue.json",
    ]


def test_unsafe_queue_item_maps_blocked_or_fail_never_accepted(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    out_path = tmp_path / "snapshot.json"
    write_queue(
        queue_path,
        [
            {
                "id": "q000003",
                "phase": "unsafe",
                "title": "Run agents and send Discord",
                "target_machine": "NUC1",
                "target_repo": "/home/slimy/slimy-harness",
                "model_recommendation": "GPT/Codex",
                "glm_thinking_level": "high_review_only",
                "status": "HOLD",
                "safety_level": "hold_requires_owner_review",
                "proof_dir": "",
                "proof_gate_verdict": "",
                "manual_qa_status": "",
                "next_required_gate": "owner review",
                "blocked_reason": "request contains execution terms",
                "updated_at": "2026-07-03T00:00:00Z",
            },
            {
                "id": "q000004",
                "phase": "bad-proof",
                "title": "Bad proof",
                "target_machine": "NUC1",
                "target_repo": "/home/slimy/slimy-harness",
                "model_recommendation": "GPT/Codex",
                "glm_thinking_level": "high_review_only",
                "status": "REJECTED",
                "safety_level": "queue_only_no_execution",
                "proof_dir": "",
                "proof_gate_verdict": "FAIL",
                "manual_qa_status": "not_required_local_cli",
                "next_required_gate": "fix failed proof",
                "blocked_reason": "proof gate failed",
                "updated_at": "2026-07-03T00:00:00Z",
            },
        ],
    )

    snapshot = run_export(queue_path, out_path)
    statuses = [item["status"] for item in snapshot["items"]]

    assert statuses == ["BLOCKED", "FAIL"]
    assert "ACCEPTED" not in json.dumps(snapshot)
    assert snapshot["summary"]["has_failures"] is True


def test_optional_proof_root_uses_gate_without_exporting_proof_text(tmp_path: Path) -> None:
    proof_root = tmp_path / "proofs"
    proof = proof_root / "proof_unit"
    proof.mkdir(parents=True)
    (proof / "RESULT.md").write_text("RESULT=FAIL\nMANUAL_QA_STATUS=not_required_local_cli\nSECRETS_PRINTED=no\n")
    (proof / "commands.log").write_text("raw command output with SECRET_TOKEN=fixture-value\n")
    (proof / "safety-cases.md").write_text("safety\n")
    queue_path = tmp_path / "queue.json"
    out_path = tmp_path / "snapshot.json"
    write_queue(
        queue_path,
        [
            {
                "id": "q000005",
                "phase": "proof",
                "title": "Proof inspected",
                "target_machine": "NUC1",
                "target_repo": "/home/slimy/slimy-harness",
                "model_recommendation": "GPT/Codex",
                "glm_thinking_level": "high_review_only",
                "status": "READY_FOR_OWNER_QA",
                "safety_level": "queue_only_no_execution",
                "proof_dir": "proof_unit",
                "proof_gate_verdict": "PASS_ELIGIBLE",
                "manual_qa_status": "not_required_local_cli",
                "next_required_gate": "owner review",
                "blocked_reason": "",
                "updated_at": "2026-07-03T00:00:00Z",
            }
        ],
    )

    snapshot = run_export(queue_path, out_path, proof_root)
    rendered = json.dumps(snapshot)

    assert snapshot["items"][0]["status"] == "FAIL"
    assert snapshot["items"][0]["proof_dir"] == "proof_unit"
    assert "raw command output" not in rendered
    assert "fixture-value" not in rendered
