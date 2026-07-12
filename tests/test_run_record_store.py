from __future__ import annotations

import importlib.util
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "ops" / "run_record_store.py"
WRAPPER = ROOT / "ops" / "run-record-create"
SPEC = importlib.util.spec_from_file_location("run_record_store", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
store = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(store)
RUN_ID = "run_20260712T180000000000Z_0123456789abcdef0123456789abcdef"
CREATED_AT = "2026-07-12T18:00:00.000000Z"
HEAD = "1" * 40


def cli(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([str(WRAPPER), *arguments], text=True, capture_output=True, check=False)


def create_args(root: Path, *extra: str) -> list[str]:
    return [
        "create", "--root", str(root), "--run-id", RUN_ID,
        "--subject-type", "run", "--project-id", "slimy-harness",
        "--repository-path", str(ROOT), "--repository-remote", "git@example.test:slimy-harness.git",
        "--repository-head", HEAD, "--machine", "nuc1", "--hostname", "test-nuc1",
        "--actor", "codex-gpt5", "--authority", "live-chat:iteration1",
        "--created-at", CREATED_AT, *extra,
    ]


def record_path(root: Path) -> Path:
    return root / "records" / f"{RUN_ID}.jsonl"


def test_generated_run_ids_are_well_formed_and_unique() -> None:
    ids = {store.generate_run_id() for _ in range(1000)}
    assert len(ids) == 1000
    assert all(store.RUN_ID_RE.fullmatch(run_id) for run_id in ids)


def test_create_round_trip_and_cold_store_validation(tmp_path: Path) -> None:
    root = tmp_path / "records"
    created = cli(*create_args(root))
    assert created.returncode == 0, created.stderr
    assert "create=CREATED" in created.stdout
    validated = cli("validate", str(record_path(root)))
    assert validated.returncode == 0, validated.stderr
    cold = cli("validate-store", "--root", str(root))
    assert cold.returncode == 0, cold.stderr
    assert "record_count=1" in cold.stdout
    record = json.loads(record_path(root).read_text())
    assert record["v"] == 1
    assert record["schema_id"] == "slimy-harness.run-created.v1"
    assert record["machine"] == {"hostname": "test-nuc1", "id": "nuc1"}
    assert record["actor"] != record["authority"]


def test_subject_is_normalized_and_unknown_namespace_refused(tmp_path: Path) -> None:
    root = tmp_path / "records"
    result = cli(*create_args(root, "--subject-type", "feature", "--subject-id", "  feature-42  "))
    assert result.returncode == 0, result.stderr
    assert json.loads(record_path(root).read_text())["subject_id"] == "feature-42"
    rejected = create_args(tmp_path / "bad")
    rejected[rejected.index("--subject-type") + 1] = "unknown"
    result = cli(*rejected)
    assert result.returncode == 1
    assert "unknown subject_type refused" in result.stderr


def test_missing_authority_is_refused_without_store_write(tmp_path: Path) -> None:
    arguments = create_args(tmp_path / "records")
    index = arguments.index("--authority")
    del arguments[index:index + 2]
    result = cli(*arguments)
    assert result.returncode != 0
    assert not (tmp_path / "records").exists()


def test_exact_replay_is_idempotent_but_conflict_is_refused(tmp_path: Path) -> None:
    root = tmp_path / "records"
    first = cli(*create_args(root))
    original = record_path(root).read_bytes()
    replay = cli(*create_args(root))
    conflict = cli(*create_args(root, "--actor", "different-actor"))
    assert first.returncode == 0
    assert replay.returncode == 0
    assert "create=EXISTS_IDENTICAL" in replay.stdout
    assert conflict.returncode == 1
    assert "RUN_ID collision refused" in conflict.stderr
    assert record_path(root).read_bytes() == original


def test_concurrent_same_id_has_one_winner_and_no_overwrite(tmp_path: Path) -> None:
    root = tmp_path / "records"
    processes = []
    for index in range(8):
        arguments = create_args(root, "--actor", f"actor-{index}")
        processes.append(subprocess.Popen([str(WRAPPER), *arguments], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE))
    results = [process.communicate(timeout=10) + (process.returncode,) for process in processes]
    assert sum("create=CREATED" in stdout for stdout, _stderr, _code in results) == 1
    assert sum(code == 1 and "collision refused" in stderr for _stdout, stderr, code in results) == 7
    assert len(list((root / "records").glob("*.jsonl"))) == 1
    assert not list((root / "pending").iterdir())
    assert cli("validate-store", "--root", str(root)).returncode == 0


@pytest.mark.parametrize("mutation", ["truncate", "digest", "newline", "extra"])
def test_malformed_or_corrupt_canonical_record_is_detected(tmp_path: Path, mutation: str) -> None:
    root = tmp_path / "records"
    assert cli(*create_args(root)).returncode == 0
    path = record_path(root)
    if mutation == "truncate":
        path.write_bytes(path.read_bytes()[:-5])
    elif mutation == "digest":
        data = json.loads(path.read_text())
        data["actor"] = "tampered"
        path.write_text(json.dumps(data, separators=(",", ":"), sort_keys=True) + "\n")
    elif mutation == "newline":
        path.write_bytes(path.read_bytes() + b"\n")
    else:
        data = json.loads(path.read_text())
        data["unexpected"] = True
        path.write_text(json.dumps(data, separators=(",", ":"), sort_keys=True) + "\n")
    result = cli("validate-store", "--root", str(root))
    assert result.returncode == 1
    assert "malformed_record=" in result.stderr


def test_killed_mid_write_is_detected_then_quarantined(tmp_path: Path) -> None:
    root = tmp_path / "records"
    ready = tmp_path / "ready"
    child = tmp_path / "child.py"
    child.write_text(
        """
import importlib.util, json, os, pathlib, time
spec = importlib.util.spec_from_file_location('store', os.environ['MODULE'])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
args = module.parse_args(json.loads(os.environ['ARGS']))
record = module.build_record(args)
def interrupted_write(descriptor, data, on_progress=None):
    written = os.write(descriptor, data[:max(1, len(data) // 2)])
    pathlib.Path(os.environ['READY']).write_text(str(written))
    while True: time.sleep(1)
module._write_all = interrupted_write
module.create_record(pathlib.Path(os.environ['STORE']), record)
""",
        encoding="utf-8",
    )
    environment = dict(os.environ)
    environment.update({
        "MODULE": str(MODULE_PATH), "ARGS": json.dumps(create_args(root)),
        "READY": str(ready), "STORE": str(root),
    })
    process = subprocess.Popen([sys.executable, str(child)], env=environment)
    for _ in range(100):
        if ready.exists():
            break
        time.sleep(0.02)
    assert ready.exists()
    process.send_signal(signal.SIGKILL)
    process.wait(timeout=5)
    assert process.returncode == -signal.SIGKILL
    assert not list((root / "records").iterdir())
    detected = cli("validate-store", "--root", str(root))
    assert detected.returncode == 1
    assert "partial_pending=" in detected.stderr
    quarantined = cli("validate-store", "--root", str(root), "--quarantine-partials")
    assert quarantined.returncode == 0, quarantined.stderr
    assert "quarantined_partials=1" in quarantined.stdout
    assert not list((root / "pending").iterdir())
    assert len(list((root / "quarantine").iterdir())) == 1
