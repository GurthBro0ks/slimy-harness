from __future__ import annotations

import copy
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
OPS_ROOT = REPO_ROOT / "ops"
FIXTURE_ROOT = OPS_ROOT / "tests" / "fixtures" / "run-projections"
SCHEMA_PATH = REPO_ROOT / "schema" / "run-projection.v1.schema.json"
CLI_PATH = OPS_ROOT / "validate-run-projection"
PRODUCTION_ROOT = Path("/home/slimy/harness-logs/run-projections")

sys.path.insert(0, str(OPS_ROOT))
import run_projection  # noqa: E402


GOOD_FIXTURES = (
    "active.json",
    "completed_owner_qa_pending.json",
    "superseded.json",
    "fixture_flagged.json",
    "completed_with_continuation.json",
)
INVALID_FIXTURES = ("corrupt.json", "wrong_version.json")


def load_fixture(name: str = "active.json") -> dict:
    return json.loads((FIXTURE_ROOT / name).read_text(encoding="utf-8"))


def run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(CLI_PATH), *args],
        cwd=REPO_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )


def fixture_tree_digest() -> dict[str, str]:
    return {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(FIXTURE_ROOT.glob("*.json"))
    }


@pytest.mark.parametrize("name", GOOD_FIXTURES)
def test_all_good_fixtures_validate(name: str) -> None:
    result = run_projection.validate_target(FIXTURE_ROOT / name)
    assert result["valid"] is True
    assert result["summary"] == {"total": 1, "valid": 1, "invalid": 0}


def test_fixture_inventory_is_exact() -> None:
    assert tuple(sorted(path.name for path in FIXTURE_ROOT.glob("*.json"))) == tuple(
        sorted(GOOD_FIXTURES + INVALID_FIXTURES)
    )


def test_corrupt_json_is_refused_safely() -> None:
    result = run_projection.validate_target(FIXTURE_ROOT / "corrupt.json")
    assert result["valid"] is False
    assert result["files"][0]["error_class"] == "invalid_json"
    assert "synthetic_note" not in result["files"][0]["errors"][0]


def test_wrong_and_unknown_versions_are_refused() -> None:
    wrong = run_projection.validate_target(FIXTURE_ROOT / "wrong_version.json")
    assert wrong["files"][0]["error_class"] == "unsupported_schema_version"

    document = load_fixture()
    document["schema_version"] = "run-projection.v999"
    with pytest.raises(run_projection.RunProjectionValidationError) as error:
        run_projection.validate_document(document)
    assert error.value.error_class == "unsupported_schema_version"


def test_missing_file_is_refused() -> None:
    result = run_projection.validate_target(FIXTURE_ROOT / "missing.json")
    assert result["valid"] is False
    assert result["files"][0]["error_class"] == "missing_path"


def test_missing_required_field_is_refused() -> None:
    document = load_fixture()
    del document["state"]["review"]
    with pytest.raises(run_projection.RunProjectionValidationError) as error:
        run_projection.validate_document(document)
    assert error.value.error_class == "schema_mismatch"


def test_additional_properties_are_refused_at_nested_levels() -> None:
    document = load_fixture()
    document["state"]["invented_truth"] = "not allowed"
    with pytest.raises(run_projection.RunProjectionValidationError) as error:
        run_projection.validate_document(document)
    assert error.value.error_class == "schema_mismatch"
    assert "not allowed" not in error.value.safe_message


def test_invalid_enum_is_refused() -> None:
    document = load_fixture()
    document["state"]["acceptance"] = "AUTO_ACCEPTED"
    with pytest.raises(run_projection.RunProjectionValidationError):
        run_projection.validate_document(document)


def test_invalid_run_id_is_refused() -> None:
    document = load_fixture()
    document["run"]["run_id"] = "run_not_canonical"
    document["links"]["workspace_path"] = "/runs/run_not_canonical"
    with pytest.raises(run_projection.RunProjectionValidationError):
        run_projection.validate_document(document)


def test_unknown_is_preserved_where_contract_allows_it() -> None:
    document = load_fixture("fixture_flagged.json")
    run_projection.validate_document(document)
    assert document["state"]["evidence"] == "UNKNOWN"
    assert document["state"]["review"] == "UNKNOWN"
    assert document["state"]["acceptance"] == "UNKNOWN"
    assert document["state"]["owner_action"] == "UNKNOWN"
    assert document["state"]["notification"] == "UNKNOWN"


def test_null_is_accepted_only_for_explicitly_nullable_fields() -> None:
    document = load_fixture()
    assert document["run"]["model"] is None
    run_projection.validate_document(document)

    not_nullable = copy.deepcopy(document)
    not_nullable["generated_by"] = None
    with pytest.raises(run_projection.RunProjectionValidationError):
        run_projection.validate_document(not_nullable)


@pytest.mark.parametrize("field", ("test_fixture_only", "production_acceptance_enabled"))
def test_fixture_safety_markers_are_required(field: str) -> None:
    document = load_fixture()
    del document["flags"][field]
    with pytest.raises(run_projection.RunProjectionValidationError):
        run_projection.validate_document(document)


def test_all_valid_fixtures_are_explicitly_fixture_only_and_production_disabled() -> None:
    for name in GOOD_FIXTURES:
        document = load_fixture(name)
        assert document["generated_by"] == "rw0-fixture"
        assert document["flags"]["test_fixture_only"] is True
        assert document["flags"]["production_acceptance_enabled"] is False
        assert document["flags"]["production_storage_active"] is False


def test_route_backed_fixture_has_safe_synthetic_report_link() -> None:
    document = load_fixture("completed_owner_qa_pending.json")
    assert document["links"]["report_url"] == (
        "https://harness.slimyai.xyz/reports/sessions/"
        "report-fixture-run-workspace-rw1.json"
    )
    assert load_fixture("active.json")["links"]["report_url"] is None


def test_directory_mode_is_deterministic_and_bounded_to_json_files() -> None:
    first = run_projection.validate_target(FIXTURE_ROOT)
    second = run_projection.validate_target(FIXTURE_ROOT)
    assert first == second
    assert first["summary"] == {"total": 7, "valid": 5, "invalid": 2}
    names = [Path(item["path"]).name for item in first["files"]]
    assert names == sorted(names)


def test_json_output_is_machine_readable() -> None:
    completed = run_cli(str(FIXTURE_ROOT / "active.json"), "--format", "json")
    assert completed.returncode == 0
    payload = json.loads(completed.stdout)
    assert payload["schema_version"] == "run-projection-validator.v1"
    assert payload["valid"] is True
    assert payload["summary"] == {"invalid": 0, "total": 1, "valid": 1}


def test_text_output_is_useful_and_wrong_version_exits_nonzero() -> None:
    completed = run_cli(str(FIXTURE_ROOT / "wrong_version.json"))
    assert completed.returncode != 0
    assert "Run projection validation: FAIL" in completed.stdout
    assert "unsupported_schema_version" in completed.stdout
    assert "Summary:" in completed.stdout


def test_help_explains_file_directory_formats_and_read_only_behavior() -> None:
    completed = run_cli("--help")
    assert completed.returncode == 0
    assert "one run-projection.v1 JSON file" in completed.stdout
    assert "directory" in completed.stdout
    assert "--format" in completed.stdout
    assert "never modified" in completed.stdout


def test_validation_does_not_write_fixture_tree_or_create_production_root() -> None:
    assert not PRODUCTION_ROOT.exists()
    before = fixture_tree_digest()
    completed = run_cli(str(FIXTURE_ROOT), "--format", "json")
    assert completed.returncode != 0
    assert fixture_tree_digest() == before
    assert not PRODUCTION_ROOT.exists()


def test_validator_has_no_notifier_network_deep_validation_or_production_path() -> None:
    source = (OPS_ROOT / "run_projection.py").read_text(encoding="utf-8")
    wrapper = CLI_PATH.read_text(encoding="utf-8")
    forbidden = (
        "acceptance-ledger",
        "notify-proof-dir-complete",
        "notify-session-complete",
        "requests",
        "urllib",
        "socket",
        "/home/slimy/harness-logs/run-projections",
    )
    for marker in forbidden:
        assert marker not in source
        assert marker not in wrapper
    assert "subprocess" not in source


def test_continuation_fixture_validates_and_authorization_is_non_transitive() -> None:
    document = load_fixture("completed_with_continuation.json")
    run_projection.validate_document(document)
    continuation = document["continuation"]
    assert continuation is not None
    assert continuation["push_authorized"] is False
    assert continuation["deploy_authorized"] is False
    assert continuation["restart_authorized"] is False
    assert continuation["handoff_complete"] is False
    wording = " ".join(continuation["prohibited_actions"]).lower()
    assert "not transitive" in wording
    assert "fresh live-owner authorization" in wording


def test_schema_closes_every_data_object_and_contains_governance_wording() -> None:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    governance = (
        "Every field that asserts a fact about a run's canonical state must appear in the "
        "canonical-versus-projection matrix or is refused. Producer-provenance fields "
        "(schema_version, generated_at, generated_by, source_machine) and self-integrity fields "
        "(integrity.*) are explicitly exempt because they describe the projection file rather "
        "than canonical run state."
    )
    assert schema["$comment"] == governance

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


def test_url_and_path_fields_are_constrained() -> None:
    document = load_fixture()
    document["links"]["report_url"] = "https://example.invalid/report.json"
    with pytest.raises(run_projection.RunProjectionValidationError):
        run_projection.validate_document(document)

    document = load_fixture()
    document["evidence"]["proof_dir"] = "/etc/passwd"
    with pytest.raises(run_projection.RunProjectionValidationError):
        run_projection.validate_document(document)
