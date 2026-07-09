from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "ops" / "feature_list_append_locked.py"
WRAPPER = ROOT / "ops" / "feature-list-append-locked"
SPEC = importlib.util.spec_from_file_location("feature_list_append_locked", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


def write_json(path: Path, data: object) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def read_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def run_helper(*args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(WRAPPER), *args],
        cwd=str(cwd or ROOT),
        text=True,
        capture_output=True,
        check=False,
    )


def test_validate_current_shape_with_fixture(tmp_path: Path) -> None:
    feature_list = tmp_path / "feature_list.json"
    write_json(feature_list, {"features": [{"id": "existing", "passes": False}]})

    result = run_helper("--feature-list", str(feature_list), "--validate-only")

    assert result.returncode == 0, result.stderr
    assert "validate=PASS" in result.stdout
    assert "duplicate_ids=[]" in result.stdout


def test_append_unique_id_preserves_object_shape(tmp_path: Path) -> None:
    feature_list = tmp_path / "feature_list.json"
    entry = tmp_path / "entry.json"
    write_json(feature_list, {"_meta": {"scope": "fixture"}, "features": [{"id": "existing"}]})
    write_json(entry, {"id": "new-entry", "passes": False})

    result = run_helper("--feature-list", str(feature_list), "--entry-json", str(entry))

    assert result.returncode == 0, result.stderr
    data = read_json(feature_list)
    assert isinstance(data, dict)
    assert data["_meta"] == {"scope": "fixture"}
    assert [item["id"] for item in data["features"]] == ["existing", "new-entry"]


def test_reject_duplicate_id_without_writing(tmp_path: Path) -> None:
    feature_list = tmp_path / "feature_list.json"
    entry = tmp_path / "entry.json"
    original = {"features": [{"id": "same", "phase": "original"}]}
    write_json(feature_list, original)
    write_json(entry, {"id": "same", "phase": "duplicate"})

    result = run_helper("--feature-list", str(feature_list), "--entry-json", str(entry))

    assert result.returncode == 1
    assert "duplicate id refused" in result.stderr
    assert read_json(feature_list) == original


def test_preserve_top_level_list_shape(tmp_path: Path) -> None:
    feature_list = tmp_path / "feature_list.json"
    entry = tmp_path / "entry.json"
    write_json(feature_list, [{"id": "a"}])
    write_json(entry, {"id": "b"})

    result = run_helper("--feature-list", str(feature_list), "--entry-json", str(entry))

    assert result.returncode == 0, result.stderr
    data = read_json(feature_list)
    assert isinstance(data, list)
    assert [item["id"] for item in data] == ["a", "b"]


def test_dry_run_does_not_write(tmp_path: Path) -> None:
    feature_list = tmp_path / "feature_list.json"
    entry = tmp_path / "entry.json"
    original = {"features": [{"id": "a"}]}
    write_json(feature_list, original)
    write_json(entry, {"id": "b"})

    result = run_helper("--feature-list", str(feature_list), "--entry-json", str(entry), "--dry-run")

    assert result.returncode == 0, result.stderr
    assert "dry_run=PASS" in result.stdout
    assert read_json(feature_list) == original


def test_atomic_replace_removes_temp_file_and_preserves_mode(tmp_path: Path) -> None:
    feature_list = tmp_path / "feature_list.json"
    entry = tmp_path / "entry.json"
    write_json(feature_list, {"features": [{"id": "a"}]})
    write_json(entry, {"id": "b"})
    os.chmod(feature_list, 0o640)

    result = run_helper("--feature-list", str(feature_list), "--entry-json", str(entry))

    assert result.returncode == 0, result.stderr
    assert not list(tmp_path.glob(".feature_list.json.*.tmp"))
    assert feature_list.stat().st_mode & 0o777 == 0o640
    assert [item["id"] for item in read_json(feature_list)["features"]] == ["a", "b"]


def test_reject_existing_duplicate_ids_before_append(tmp_path: Path) -> None:
    feature_list = tmp_path / "feature_list.json"
    entry = tmp_path / "entry.json"
    write_json(feature_list, {"features": [{"id": "dup"}, {"id": "dup"}]})
    write_json(entry, {"id": "new"})

    result = run_helper("--feature-list", str(feature_list), "--entry-json", str(entry))

    assert result.returncode == 1
    assert "duplicate_ids=" in result.stderr
    assert [item["id"] for item in read_json(feature_list)["features"]] == ["dup", "dup"]


def test_concurrent_unique_appends_are_serialized(tmp_path: Path) -> None:
    feature_list = tmp_path / "feature_list.json"
    lock_file = tmp_path / "feature_list.lock"
    write_json(feature_list, {"features": [{"id": "base"}]})
    entries = []
    for index in range(8):
        entry = tmp_path / f"entry-{index}.json"
        write_json(entry, {"id": f"new-{index}"})
        entries.append(entry)

    procs = [
        subprocess.Popen(
            [
                sys.executable,
                str(MODULE_PATH),
                "--feature-list",
                str(feature_list),
                "--entry-json",
                str(entry),
                "--lock-file",
                str(lock_file),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        for entry in entries
    ]
    results = [proc.communicate(timeout=10) + (proc.returncode,) for proc in procs]

    assert all(returncode == 0 for _stdout, _stderr, returncode in results), results
    data = read_json(feature_list)
    ids = [item["id"] for item in data["features"]]
    assert ids[0] == "base"
    assert sorted(ids[1:]) == [f"new-{index}" for index in range(8)]
    assert len(ids) == len(set(ids))
