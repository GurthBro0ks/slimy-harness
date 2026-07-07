from __future__ import annotations

import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HELPER = REPO_ROOT / "ops" / "loop-status-export-latest"
CANONICAL_OUT = Path("/home/slimy/harness-logs/loop-status-snapshot/latest.json")


def write_queue(path: Path) -> None:
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "created_at": "2026-07-07T00:00:00Z",
                "updated_at": "2026-07-07T00:00:00Z",
                "items": [
                    {
                        "id": "q000001",
                        "phase": "manual-snapshot-smoke",
                        "title": "Manual snapshot smoke",
                        "target_machine": "NUC1",
                        "target_repo": "/home/slimy/slimy-harness",
                        "model_recommendation": "GPT/Codex $100 coding plan",
                        "glm_thinking_level": "high_review_only",
                        "status": "READY_FOR_OWNER_QA",
                        "safety_level": "queue_only_no_execution",
                        "proof_dir": "",
                        "proof_gate_verdict": "PASS_ELIGIBLE",
                        "manual_qa_status": "not_required_local_cli",
                        "next_required_gate": "owner review",
                        "blocked_reason": "",
                        "updated_at": "2026-07-07T00:00:00Z",
                    }
                ],
            }
        )
        + "\n"
    )


def run_helper(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(HELPER), *args],
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def test_dry_run_requires_explicit_queue_and_does_not_create_output(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    out_path = tmp_path / "snapshot.json"
    write_queue(queue_path)

    result = run_helper("--queue", str(queue_path), "--out", str(out_path), "--dry-run")

    assert result.returncode == 0
    assert "DRY_RUN=1" in result.stdout
    assert str(queue_path) in result.stdout
    assert str(out_path) in result.stdout
    assert not out_path.exists()


def test_exports_only_to_explicit_tmp_output(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    out_path = tmp_path / "snapshot.json"
    write_queue(queue_path)

    result = run_helper("--queue", str(queue_path), "--out", str(out_path))

    assert result.returncode == 0, result.stderr
    snapshot = json.loads(out_path.read_text())
    assert snapshot["schema_version"] == "loop-status.v1"
    assert snapshot["summary"]["by_status"]["OK"] == 1
    assert snapshot["safety"]["shell_execution_present"] is False
    assert snapshot["safety"]["mutation_controls_present"] is False
    assert snapshot["safety"]["request_time_shell_required"] is False
    assert snapshot["safety"]["secrets_redacted"] is True
    assert snapshot["safety"]["owner_gate_required_for_ui"] is True


def test_refuses_missing_queue_without_creating_canonical_parent(tmp_path: Path) -> None:
    missing_queue = tmp_path / "missing.json"
    canonical_parent_existed = CANONICAL_OUT.parent.exists()

    result = run_helper("--queue", str(missing_queue))

    assert result.returncode == 66
    assert "queue file not found" in result.stderr
    assert CANONICAL_OUT.parent.exists() is canonical_parent_existed


def test_refuses_canonical_write_without_confirmation(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    write_queue(queue_path)
    canonical_parent_existed = CANONICAL_OUT.parent.exists()
    canonical_file_existed = CANONICAL_OUT.exists()

    result = run_helper("--queue", str(queue_path))

    assert result.returncode == 64
    assert "requires --confirm-canonical-latest" in result.stderr
    assert CANONICAL_OUT.parent.exists() is canonical_parent_existed
    assert CANONICAL_OUT.exists() is canonical_file_existed


def test_refuses_canonical_write_with_double_slash_spelling(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    write_queue(queue_path)
    canonical_parent_existed = CANONICAL_OUT.parent.exists()
    canonical_file_existed = CANONICAL_OUT.exists()
    alt_out = "/home/slimy/harness-logs//loop-status-snapshot/latest.json"

    result = run_helper("--queue", str(queue_path), "--out", alt_out)

    assert result.returncode == 64
    assert "requires --confirm-canonical-latest" in result.stderr
    assert CANONICAL_OUT.parent.exists() is canonical_parent_existed
    assert CANONICAL_OUT.exists() is canonical_file_existed


def test_refuses_canonical_write_with_dot_segment_spelling(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    write_queue(queue_path)
    canonical_parent_existed = CANONICAL_OUT.parent.exists()
    canonical_file_existed = CANONICAL_OUT.exists()
    alt_out = "/home/slimy/harness-logs/loop-status-snapshot/../loop-status-snapshot/latest.json"

    result = run_helper("--queue", str(queue_path), "--out", alt_out)

    assert result.returncode == 64
    assert "requires --confirm-canonical-latest" in result.stderr
    assert CANONICAL_OUT.parent.exists() is canonical_parent_existed
    assert CANONICAL_OUT.exists() is canonical_file_existed


def test_canonical_dry_run_reports_confirmation_requirement_for_equivalent_spelling(
    tmp_path: Path,
) -> None:
    queue_path = tmp_path / "queue.json"
    write_queue(queue_path)
    canonical_parent_existed = CANONICAL_OUT.parent.exists()
    canonical_file_existed = CANONICAL_OUT.exists()
    alt_out = "/home/slimy/harness-logs/loop-status-snapshot/../loop-status-snapshot/latest.json"

    result = run_helper("--queue", str(queue_path), "--out", alt_out, "--dry-run")

    assert result.returncode == 0
    assert "canonical_confirmation_required=yes" in result.stdout
    assert "canonical_confirmation_present=0" in result.stdout
    assert CANONICAL_OUT.parent.exists() is canonical_parent_existed
    assert CANONICAL_OUT.exists() is canonical_file_existed


def test_canonical_dry_run_reports_confirmation_requirement_without_writing(tmp_path: Path) -> None:
    queue_path = tmp_path / "queue.json"
    write_queue(queue_path)
    canonical_parent_existed = CANONICAL_OUT.parent.exists()
    canonical_file_existed = CANONICAL_OUT.exists()

    result = run_helper("--queue", str(queue_path), "--dry-run")

    assert result.returncode == 0
    assert "canonical_confirmation_required=yes" in result.stdout
    assert "canonical_confirmation_present=0" in result.stdout
    assert CANONICAL_OUT.parent.exists() is canonical_parent_existed
    assert CANONICAL_OUT.exists() is canonical_file_existed
