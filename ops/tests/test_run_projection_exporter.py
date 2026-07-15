from __future__ import annotations

import copy
import fcntl
import hashlib
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator


REPO_ROOT = Path(__file__).resolve().parents[2]
OPS_ROOT = REPO_ROOT / "ops"
FIXTURE = OPS_ROOT / "tests" / "fixtures" / "run-projections" / "active.json"
CLI = OPS_ROOT / "write-run-projection"
INDEX_SCHEMA = REPO_ROOT / "schema" / "run-projection-index.v1.schema.json"
PRODUCTION_ROOT = Path("/home/slimy/harness-logs/run-projections")

sys.path.insert(0, str(OPS_ROOT))
import run_projection_exporter as exporter  # noqa: E402


BASE_TIME = datetime(2026, 7, 15, 16, 0, tzinfo=timezone.utc)


def candidate(index: int = 1) -> dict:
    document = json.loads(FIXTURE.read_text(encoding="utf-8"))
    run_id = f"run_20260715T{index:012d}Z_{index:032x}"
    created = BASE_TIME + timedelta(minutes=index)
    document["run"]["run_id"] = run_id
    document["run"]["subject_id"] = f"rw2a-synthetic@{index:040x}"
    document["run"]["phase"] = f"rw2a-synthetic-{index}"
    document["run"]["created_at"] = created.isoformat(timespec="seconds").replace("+00:00", "Z")
    document["links"]["workspace_path"] = f"/runs/{run_id}"
    document["integrity"]["digest"] = None
    return document


def write_candidate(path: Path, index: int = 1, document: dict | None = None) -> Path:
    value = candidate(index) if document is None else document
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    return path


def output_paths(root: Path, index: int = 1) -> tuple[Path, Path]:
    run_id = candidate(index)["run"]["run_id"]
    return root / f"{run_id}.json", root / "index.json"


def tree_hashes(root: Path) -> dict[str, str]:
    return {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.iterdir())
        if path.is_file() and path.name.endswith(".json")
    }


def direct_write(
    root: Path,
    candidate_path: Path,
    *,
    minute: int = 0,
    failure_hook=None,
    lock_timeout_seconds: float = 5.0,
):
    return exporter.write_projection(
        root,
        candidate_path,
        now=BASE_TIME + timedelta(minutes=minute),
        failure_hook=failure_hook,
        lock_timeout_seconds=lock_timeout_seconds,
    )


def run_cli(*args: str, clean_env: bool = False) -> subprocess.CompletedProcess[str]:
    environment = {"PATH": os.environ["PATH"], "LANG": "C.UTF-8"} if clean_env else None
    return subprocess.run(
        [str(CLI), *args],
        cwd=REPO_ROOT,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )


def test_first_write_creates_canonical_projection_and_bounded_index(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    source = write_candidate(tmp_path / "candidate.json")
    result = direct_write(root, source)
    run_path, index_path = output_paths(root)

    assert result.status == "CREATED"
    assert result.state == "RUN_AND_INDEX_VALID"
    assert result.index_entries == 1
    projection = json.loads(run_path.read_text())
    index = json.loads(index_path.read_text())
    assert run_path.read_bytes() == exporter.canonical_json(projection)
    assert index_path.read_bytes() == exporter.canonical_json(index)
    assert projection["generated_by"] == exporter.PRODUCER_ID
    assert projection["source_machine"] == "nuc1"
    assert projection["integrity"]["digest"] == exporter.self_digest(projection)
    assert index["integrity"]["digest"] == exporter.self_digest(index)
    assert index["runs"] == [exporter._index_entry(projection)]
    assert run_path.stat().st_mode & 0o777 == 0o640
    assert index_path.stat().st_mode & 0o777 == 0o640
    assert (root / exporter.LOCK_FILENAME).stat().st_mode & 0o777 == 0o640
    assert exporter.validate_store(root).valid is True


def test_same_run_updates_without_duplicate_and_old_run_is_not_promoted(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    first = write_candidate(tmp_path / "first.json", 1)
    second = write_candidate(tmp_path / "second.json", 2)
    direct_write(root, first, minute=1)
    direct_write(root, second, minute=2)

    updated = candidate(1)
    updated["state"]["stage"] = "Updated fixture stage"
    update_path = write_candidate(tmp_path / "update.json", document=updated)
    result = direct_write(root, update_path, minute=3)
    index = json.loads((root / "index.json").read_text())

    assert result.status == "UPDATED"
    assert len(index["runs"]) == 2
    assert len({entry["run_id"] for entry in index["runs"]}) == 2
    assert index["runs"][0]["run_id"] == candidate(2)["run"]["run_id"]
    assert index["runs"][1]["run_id"] == candidate(1)["run"]["run_id"]


def test_index_caps_at_50_without_deleting_detail_files(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    for index in range(1, 52):
        direct_write(root, write_candidate(tmp_path / f"candidate-{index}.json", index), minute=index)
    index_document = json.loads((root / "index.json").read_text())
    detail_files = [path for path in root.glob("run_*.json")]

    assert len(index_document["runs"]) == 50
    assert len({entry["run_id"] for entry in index_document["runs"]}) == 50
    assert len(detail_files) == 51
    assert candidate(1)["run"]["run_id"] not in {entry["run_id"] for entry in index_document["runs"]}
    assert output_paths(root, 1)[0].exists()


def test_index_schema_is_valid_closed_and_matches_output(tmp_path: Path) -> None:
    schema = json.loads(INDEX_SCHEMA.read_text())
    Draft202012Validator.check_schema(schema)
    root = tmp_path / "store"
    root.mkdir()
    direct_write(root, write_candidate(tmp_path / "candidate.json"))
    Draft202012Validator(schema).validate(json.loads((root / "index.json").read_text()))

    def inspect(node: object) -> None:
        if isinstance(node, dict):
            if node.get("type") == "object":
                assert node.get("additionalProperties") is False
            for value in node.values():
                inspect(value)
        elif isinstance(node, list):
            for value in node:
                inspect(value)

    inspect(schema)


@pytest.mark.parametrize(
    "bad_root",
    [
        PRODUCTION_ROOT,
        Path("relative-root"),
        Path("/tmp"),
        Path("/home/slimy"),
        Path("/var/tmp/rw2a"),
    ],
)
def test_production_and_every_non_tmp_root_are_refused(bad_root: Path, tmp_path: Path) -> None:
    source = write_candidate(tmp_path / "candidate.json")
    with pytest.raises(exporter.ProjectionExporterError):
        direct_write(bad_root, source)
    assert not PRODUCTION_ROOT.exists()


def test_root_must_preexist_be_normalized_and_not_be_symlink(tmp_path: Path) -> None:
    source = write_candidate(tmp_path / "candidate.json")
    missing = tmp_path / "missing"
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(missing, source)
    assert error.value.error_class == "missing_root"
    assert not missing.exists()

    real = tmp_path / "real"
    real.mkdir()
    link = tmp_path / "link"
    link.symlink_to(real, target_is_directory=True)
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(link, source)
    assert error.value.error_class == "unsafe_root"


@pytest.mark.parametrize("unsafe_name", [exporter.LOCK_FILENAME, "index.json"])
def test_symlink_lock_or_index_is_refused(tmp_path: Path, unsafe_name: str) -> None:
    root = tmp_path / "store"
    root.mkdir()
    source = write_candidate(tmp_path / "candidate.json")
    (root / unsafe_name).symlink_to(tmp_path / "elsewhere")
    with pytest.raises(exporter.ProjectionExporterError):
        direct_write(root, source)


def test_symlink_existing_target_is_refused(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    source = write_candidate(tmp_path / "candidate.json")
    run_path, _index_path = output_paths(root)
    run_path.symlink_to(tmp_path / "elsewhere")
    with pytest.raises(exporter.ProjectionExporterError):
        direct_write(root, source)


def test_candidate_must_be_outside_store_and_have_null_digest(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    inside = write_candidate(root / "candidate.json")
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, inside)
    assert error.value.error_class == "unsafe_input"

    document = candidate()
    document["integrity"]["digest"] = "0" * 64
    outside = write_candidate(tmp_path / "digest.json", document=document)
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, outside)
    assert error.value.error_class == "candidate_digest_present"


@pytest.mark.parametrize(
    "mutation",
    ["fixture_flag", "storage_flag", "acceptance", "acceptance_id", "superseded"],
)
def test_rw2a_production_and_acceptance_assertions_are_refused(
    tmp_path: Path, mutation: str
) -> None:
    root = tmp_path / "store"
    root.mkdir()
    document = candidate()
    if mutation == "fixture_flag":
        document["flags"]["test_fixture_only"] = False
    elif mutation == "storage_flag":
        document["flags"]["production_storage_active"] = True
    elif mutation == "acceptance":
        document["state"]["acceptance"] = "ACCEPTED"
    elif mutation == "acceptance_id":
        document["acceptance"]["acceptance_id"] = "fixture-acceptance"
    else:
        document["acceptance"]["superseded_by"] = candidate(2)["run"]["run_id"]
    source = write_candidate(tmp_path / f"{mutation}.json", document=document)
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, source)
    assert error.value.error_class == "rw2a_boundary"
    assert not list(root.glob("*.json"))


def test_invalid_candidate_preserves_last_known_good_bytes(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    direct_write(root, write_candidate(tmp_path / "good.json"))
    before = tree_hashes(root)
    document = candidate()
    document["schema_version"] = "run-projection.v999"
    bad = write_candidate(tmp_path / "bad.json", document=document)
    with pytest.raises(exporter.ProjectionExporterError):
        direct_write(root, bad, minute=2)
    assert tree_hashes(root) == before


def test_invalid_existing_index_blocks_without_discovery_or_output_change(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    direct_write(root, write_candidate(tmp_path / "first.json"))
    index_path = root / "index.json"
    index_path.write_text("{}\n", encoding="utf-8")
    before = tree_hashes(root)
    with pytest.raises(exporter.ProjectionExporterError):
        direct_write(root, write_candidate(tmp_path / "second.json", 2), minute=2)
    assert tree_hashes(root) == before
    assert not output_paths(root, 2)[0].exists()


def test_missing_index_in_nonempty_root_is_refused_without_backfill(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    orphan = root / f"{candidate(1)['run']['run_id']}.json"
    orphan.write_text(json.dumps(candidate(1)), encoding="utf-8")
    before = hashlib.sha256(orphan.read_bytes()).hexdigest()
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, write_candidate(tmp_path / "second.json", 2), minute=2)
    assert error.value.error_class == "index_missing"
    assert hashlib.sha256(orphan.read_bytes()).hexdigest() == before
    assert not (root / "index.json").exists()


def test_secret_like_value_and_sensitive_artifact_name_are_refused(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    secret_value = candidate()
    secret_value["state"]["stage"] = "API_" + "TOKEN" + "=" + "synthetic-test-value"
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, write_candidate(tmp_path / "value.json", document=secret_value))
    assert error.value.error_class == "redaction_failure"

    sensitive_name = candidate()
    sensitive_name["artifacts"]["displayed_files"] = ["owner-session-token.txt"]
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, write_candidate(tmp_path / "name.json", document=sensitive_name))
    assert error.value.error_class == "redaction_failure"

    approval_value = candidate()
    approval_value["state"]["stage"] = (
        "APPROVAL_" + "NONCE" + "=" + "synthetic-test-value"
    )
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, write_candidate(tmp_path / "approval.json", document=approval_value))
    assert error.value.error_class == "redaction_failure"
    assert not list(root.glob("*.json"))


def test_lock_timeout_is_bounded_and_preserves_outputs(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    source = write_candidate(tmp_path / "candidate.json")
    lock_path = root / exporter.LOCK_FILENAME
    with lock_path.open("a+b") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        with pytest.raises(exporter.ProjectionExporterError) as error:
            direct_write(root, source, lock_timeout_seconds=0.02)
        assert error.value.error_class == "lock_timeout"
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    assert not list(root.glob("*.json"))


def test_root_swap_during_lock_acquisition_is_refused_before_rename(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = tmp_path / "store"
    root.mkdir()
    direct_write(root, write_candidate(tmp_path / "initial.json"))
    before = tree_hashes(root)
    displaced = tmp_path / "displaced-store"
    original_open_lock = exporter._open_lock

    def swap_root(root_path: Path, timeout_seconds: float):
        handle = original_open_lock(root_path, timeout_seconds)
        root_path.rename(displaced)
        root_path.mkdir()
        return handle

    monkeypatch.setattr(exporter, "_open_lock", swap_root)
    update = candidate()
    update["state"]["stage"] = "Must not reach replacement"
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, write_candidate(tmp_path / "update.json", document=update), minute=2)
    assert error.value.error_class == "unsafe_root"
    assert tree_hashes(displaced) == before
    assert not list(root.iterdir())


def test_lock_swap_during_acquisition_is_refused_before_rename(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = tmp_path / "store"
    root.mkdir()
    direct_write(root, write_candidate(tmp_path / "initial.json"))
    before = tree_hashes(root)
    original_open_lock = exporter._open_lock

    def swap_lock(root_path: Path, timeout_seconds: float):
        handle = original_open_lock(root_path, timeout_seconds)
        lock_path = root_path / exporter.LOCK_FILENAME
        lock_path.unlink()
        lock_path.write_bytes(b"")
        return handle

    monkeypatch.setattr(exporter, "_open_lock", swap_lock)
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, write_candidate(tmp_path / "update.json"), minute=2)
    assert error.value.error_class == "unsafe_lock"
    assert tree_hashes(root) == before


def test_concurrent_writers_serialize_and_keep_unique_index(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    sources = [write_candidate(tmp_path / f"candidate-{index}.json", index) for index in range(1, 9)]
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(lambda pair: direct_write(root, pair[1], minute=pair[0]), enumerate(sources, 1)))
    index = json.loads((root / "index.json").read_text())
    assert all(result.state == "RUN_AND_INDEX_VALID" for result in results)
    assert len(index["runs"]) == 8
    assert len({entry["run_id"] for entry in index["runs"]}) == 8
    assert exporter.validate_store(root).valid is True


def test_concurrent_same_run_updates_remain_one_detail_and_one_index_row(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    source = write_candidate(tmp_path / "candidate.json")
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(lambda minute: direct_write(root, source, minute=minute), range(8)))
    index = json.loads((root / "index.json").read_text())
    assert sum(result.status == "CREATED" for result in results) == 1
    assert sum(result.status == "UPDATED" for result in results) == 7
    assert len(list(root.glob("run_*.json"))) == 1
    assert len(index["runs"]) == 1
    assert exporter.validate_store(root).valid is True


@pytest.mark.parametrize(
    "failure_stage",
    ["after_run_pending_validation", "after_index_pending_validation", "before_run_replace"],
)
def test_all_pre_rename_injected_failures_preserve_last_known_good(
    tmp_path: Path, failure_stage: str
) -> None:
    root = tmp_path / "store"
    root.mkdir()
    direct_write(root, write_candidate(tmp_path / "initial.json"))
    before = tree_hashes(root)
    update = candidate()
    update["state"]["stage"] = f"Would fail at {failure_stage}"
    source = write_candidate(tmp_path / "update.json", document=update)

    def fail(stage: str) -> None:
        if stage == failure_stage:
            raise RuntimeError("synthetic injected failure")

    with pytest.raises(exporter.ProjectionExporterError):
        direct_write(root, source, minute=2, failure_hook=fail)
    assert tree_hashes(root) == before
    assert not [path for path in root.iterdir() if exporter.PENDING_MARKER in path.name]


def test_short_write_and_fsync_failures_preserve_last_known_good(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = tmp_path / "store"
    root.mkdir()
    direct_write(root, write_candidate(tmp_path / "initial.json"))
    before = tree_hashes(root)
    update = write_candidate(tmp_path / "update.json")

    original_write = exporter.os.write
    calls = 0

    def short_write(descriptor: int, data: bytes) -> int:
        nonlocal calls
        calls += 1
        return 0 if calls == 1 else original_write(descriptor, data)

    monkeypatch.setattr(exporter.os, "write", short_write)
    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, update, minute=2)
    assert error.value.error_class == "short_write"
    assert tree_hashes(root) == before
    monkeypatch.setattr(exporter.os, "write", original_write)

    original_fsync = exporter.os.fsync
    calls = 0

    def fail_fsync(descriptor: int) -> None:
        nonlocal calls
        calls += 1
        if calls == 1:
            raise OSError("synthetic fsync failure")
        original_fsync(descriptor)

    monkeypatch.setattr(exporter.os, "fsync", fail_fsync)
    with pytest.raises(exporter.ProjectionExporterError):
        direct_write(root, update, minute=3)
    assert tree_hashes(root) == before


def test_between_renames_reports_run_valid_index_lkg_and_retry_heals(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    direct_write(root, write_candidate(tmp_path / "initial.json"))
    before_index = hashlib.sha256((root / "index.json").read_bytes()).hexdigest()
    update = candidate()
    update["state"]["stage"] = "New valid detail before index replacement"
    source = write_candidate(tmp_path / "update.json", document=update)

    def fail(stage: str) -> None:
        if stage == "after_run_replace":
            raise RuntimeError("synthetic between-renames failure")

    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, source, minute=2, failure_hook=fail)
    assert error.value.state == "RUN_VALID_INDEX_LKG"
    run_path, index_path = output_paths(root)
    assert json.loads(run_path.read_text())["state"]["stage"] == update["state"]["stage"]
    assert hashlib.sha256(index_path.read_bytes()).hexdigest() == before_index
    assert exporter.validate_store(root).valid is False

    healed = direct_write(root, source, minute=3)
    assert healed.state == "RUN_AND_INDEX_VALID"
    assert exporter.validate_store(root).valid is True
    index = json.loads(index_path.read_text())
    assert index["runs"][0] == exporter._index_entry(json.loads(run_path.read_text()))


def test_failure_after_both_replacements_reports_committed_state(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    source = write_candidate(tmp_path / "candidate.json")

    def fail(stage: str) -> None:
        if stage == "after_index_replace":
            raise RuntimeError("synthetic post-commit failure")

    with pytest.raises(exporter.ProjectionExporterError) as error:
        direct_write(root, source, failure_hook=fail)
    assert error.value.state == "RUN_AND_INDEX_REPLACED_VALIDATION_UNKNOWN"
    assert exporter.validate_store(root).valid is True
    healed = direct_write(root, source, minute=1)
    assert healed.state == "RUN_AND_INDEX_VALID"


def test_index_is_never_replaced_before_new_detail_exists(tmp_path: Path) -> None:
    source_text = (OPS_ROOT / "run_projection_exporter.py").read_text(encoding="utf-8")
    run_replace = source_text.index("os.replace(run_pending, target)")
    index_replace = source_text.index("os.replace(index_pending, index_path)")
    assert run_replace < index_replace


def test_crash_leftovers_are_reported_and_never_deleted(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    direct_write(root, write_candidate(tmp_path / "candidate.json"))
    leftover = root / ".index.json.pending.999.deadbeef"
    leftover.write_text("partial", encoding="utf-8")
    before = leftover.read_bytes()
    result = exporter.validate_store(root)
    assert result.valid is False
    assert leftover.name in result.pending_files
    assert leftover.read_bytes() == before
    cli_result = run_cli("validate-store", "--root", str(root), "--format", "json")
    assert cli_result.returncode == 1
    assert leftover.exists()


def test_corrupt_existing_detail_is_never_silently_replaced(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    source = write_candidate(tmp_path / "candidate.json")
    direct_write(root, source)
    run_path, index_path = output_paths(root)
    run_path.write_text("{}\n", encoding="utf-8")
    before_run = run_path.read_bytes()
    before_index = index_path.read_bytes()
    with pytest.raises(exporter.ProjectionExporterError):
        direct_write(root, source, minute=1)
    assert run_path.read_bytes() == before_run
    assert index_path.read_bytes() == before_index


def test_cli_is_machine_readable_and_cold_environment_safe(tmp_path: Path) -> None:
    root = tmp_path / "store"
    root.mkdir()
    source = write_candidate(tmp_path / "candidate.json")
    completed = run_cli("write", "--root", str(root), "--input", str(source), clean_env=True)
    assert completed.returncode == 0, completed.stderr
    payload = json.loads(completed.stdout)
    assert payload["state"] == "RUN_AND_INDEX_VALID"
    validated = run_cli("validate-store", "--root", str(root), "--format", "json", clean_env=True)
    assert validated.returncode == 0, validated.stderr
    assert json.loads(validated.stdout)["valid"] is True


def test_public_cli_has_no_backdating_production_or_repair_controls() -> None:
    help_result = run_cli("--help")
    write_help = run_cli("write", "--help")
    validate_help = run_cli("validate-store", "--help")
    combined = help_result.stdout + write_help.stdout + validate_help.stdout
    assert help_result.returncode == write_help.returncode == validate_help.returncode == 0
    assert "write" in combined and "validate-store" in combined
    for forbidden in ("--now", "--production", "--all", "--repair", "--delete", "--quarantine"):
        assert forbidden not in combined


def test_static_boundary_has_no_lifecycle_notifier_ledger_network_or_subprocess() -> None:
    source = (OPS_ROOT / "run_projection_exporter.py").read_text(encoding="utf-8")
    wrapper = CLI.read_text(encoding="utf-8")
    for marker in (
        "acceptance-ledger",
        "acceptance_ledger",
        "notify-proof-dir-complete",
        "notify-session-complete",
        "run_record_store",
        "requests",
        "urllib",
        "socket",
        "subprocess",
        "rsync",
        "ssh ",
    ):
        assert marker not in source
        assert marker not in wrapper
    assert "PRODUCTION_ROOT" in source
    assert "production_root_refused" in source
    assert not PRODUCTION_ROOT.exists()
