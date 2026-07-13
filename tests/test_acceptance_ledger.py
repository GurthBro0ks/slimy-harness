from __future__ import annotations

import fcntl
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import jsonschema
import pytest


ROOT = Path(__file__).resolve().parents[1]
OPS = ROOT / "ops"
sys.path.insert(0, str(OPS))
import acceptance_ledger as ledger  # noqa: E402


CLI = OPS / "acceptance-ledger"
RUN_CLI = OPS / "run-record-create"
RUN_ID = "run_20260713T160000000000Z_0123456789abcdef0123456789abcdef"
HEAD = "3" * 40
SUBJECT_ID = f"slimy-harness@{HEAD}"
ACCEPTANCE_1 = "acceptance_20260713T160100000000Z_11111111111111111111111111111111"
ACCEPTANCE_2 = "acceptance_20260713T160200000000Z_22222222222222222222222222222222"
RECORDED_1 = "2026-07-13T16:01:00.000000Z"
RECORDED_2 = "2026-07-13T16:02:00.000000Z"
SCOPE = "repository-source:iteration2-foundation"


def run_cli(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([str(CLI), *arguments], text=True, capture_output=True, check=False)


def canonical_write(path: Path, value: object) -> None:
    path.write_bytes(ledger.canonical_json(value))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_arg(arguments: list[str], flag: str, value: str) -> list[str]:
    result = list(arguments)
    result[result.index(flag) + 1] = value
    return result


def remove_arg(arguments: list[str], flag: str) -> list[str]:
    result = list(arguments)
    index = result.index(flag)
    del result[index:index + 2]
    return result


def make_bundle(tmp_path: Path, *, scope: str = SCOPE, suffix: str = "one") -> dict[str, object]:
    run_root = tmp_path / "run-records"
    created = subprocess.run(
        [
            str(RUN_CLI), "create", "--root", str(run_root), "--run-id", RUN_ID,
            "--subject-type", "repository", "--subject-id", SUBJECT_ID,
            "--project-id", "slimy-harness", "--repository-path", str(ROOT),
            "--repository-remote", "git@example.test:slimy-harness.git",
            "--repository-head", HEAD, "--machine", "nuc1", "--hostname", "test-nuc1",
            "--actor", "codex-gpt5", "--authority", "test-fixture:run-creation",
            "--created-at", "2026-07-13T16:00:00.000000Z",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert created.returncode == 0, created.stderr
    run_record = run_root / "records" / f"{RUN_ID}.jsonl"
    authority_path = tmp_path / f"authority-{suffix}.json"
    authority_ref = f"fixture://iteration2/{suffix}"
    authority = {
        "schema_version": 1,
        "authority_artifact_type": "TEST_AUTHORITY_DECLARATION",
        "authority_type": "test_fixture",
        "authority_ref": authority_ref,
        "authority_scope": scope,
        "issued_at": "2026-07-13T15:00:00.000000Z",
        "effective_at": "2026-07-13T15:30:00.000000Z",
        "expires_at": "2027-07-13T15:30:00.000000Z",
        "authority_authentication": "TEST_FIXTURE_ONLY",
        "production_authority_verification": "NOT_IMPLEMENTED",
        "production_acceptance_enabled": False,
    }
    canonical_write(authority_path, authority)
    evidence_artifact = tmp_path / f"evidence-{suffix}.txt"
    evidence_artifact.write_text("focused=PASS\nfull=PASS\n", encoding="utf-8")
    evidence_manifest = tmp_path / f"evidence-{suffix}.json"
    evidence_ref = f"proof://iteration2/{suffix}"
    manifest = {
        "schema_version": 1,
        "evidence_manifest_type": "ACCEPTANCE_EVIDENCE",
        "evidence_type": "proof_manifest",
        "evidence_ref": evidence_ref,
        "source_run_id": RUN_ID,
        "subject": {"subject_type": "repository", "subject_id": SUBJECT_ID},
        "validation_summary": "focused and full tests pass",
        "evidence_created_at": "2026-07-13T16:00:30.000000Z",
        "artifact_path": str(evidence_artifact),
        "artifact_digest": sha256(evidence_artifact),
    }
    canonical_write(evidence_manifest, manifest)
    ledger_root = tmp_path / "acceptance-ledger"
    arguments = [
        "append", "--root", str(ledger_root), "--run-record", str(run_record),
        "--acceptance-id", ACCEPTANCE_1, "--decision", "ACCEPTED", "--scope", scope,
        "--actor-id", "codex-gpt5", "--authority-file", str(authority_path),
        "--authority-type", "test_fixture", "--authority-ref", authority_ref,
        "--authority-scope", scope, "--authority-digest", sha256(authority_path),
        "--evidence-manifest", str(evidence_manifest), "--effective-at", RECORDED_1,
        "--recorded-at", RECORDED_1,
    ]
    return {
        "tmp": tmp_path,
        "root": ledger_root,
        "run_record": run_record,
        "authority": authority_path,
        "authority_value": authority,
        "evidence": evidence_artifact,
        "manifest": evidence_manifest,
        "manifest_value": manifest,
        "args": arguments,
        "scope": scope,
    }


def append(bundle: dict[str, object], *extra: str) -> subprocess.CompletedProcess[str]:
    return run_cli(*[str(item) for item in bundle["args"]], *extra)


def entry_files(bundle: dict[str, object]) -> list[Path]:
    return sorted((Path(bundle["root"]) / "entries").glob("*.jsonl"))


def test_acceptance_id_schema_help_and_canonical_serialization(tmp_path: Path) -> None:
    generated = {ledger.generate_acceptance_id() for _ in range(100)}
    assert len(generated) == 100
    assert all(ledger.ACCEPTANCE_ID_RE.fullmatch(value) for value in generated)
    help_result = run_cli("append", "--help")
    assert help_result.returncode == 0
    assert "--authority-file" in help_result.stdout
    assert "--evidence-manifest" in help_result.stdout
    bundle = make_bundle(tmp_path)
    result = append(bundle)
    assert result.returncode == 0, result.stderr
    path = entry_files(bundle)[0]
    entry = json.loads(path.read_text())
    schema = json.loads((ROOT / "schema" / "acceptance-decision.v1.schema.json").read_text())
    jsonschema.validate(entry, schema)
    assert path.read_bytes() == ledger.canonical_json(entry)
    assert entry["schema_version"] == 1
    assert entry["production_acceptance_enabled"] is False


def test_valid_append_exact_replay_current_history_and_cold_validation(tmp_path: Path) -> None:
    bundle = make_bundle(tmp_path)
    first = append(bundle)
    replay = append(bundle)
    assert first.returncode == 0, first.stderr
    assert json.loads(first.stdout)["append"] == "APPENDED"
    assert replay.returncode == 0, replay.stderr
    assert json.loads(replay.stdout)["append"] == "EXISTS_IDENTICAL"
    assert len(entry_files(bundle)) == 1
    validated = run_cli("validate", "--root", str(bundle["root"]))
    assert validated.returncode == 0, validated.stderr
    current = run_cli(
        "current", "--root", str(bundle["root"]), "--subject-type", "repository",
        "--subject-id", SUBJECT_ID, "--scope", SCOPE,
    )
    query = json.loads(current.stdout)
    assert query["status"] == "ACCEPTED"
    assert query["is_current_accepted_state"] is True
    assert query["current"]["run_id"] == RUN_ID
    assert query["current"]["authority"]["authority_ref"] == "fixture://iteration2/one"
    assert query["current"]["evidence"][0]["evidence_ref"] == "proof://iteration2/one"
    assert query["production_acceptance_enabled"] is False
    history = run_cli(
        "history", "--root", str(bundle["root"]), "--subject-type", "repository",
        "--subject-id", SUBJECT_ID, "--scope", SCOPE,
    )
    assert json.loads(history.stdout)["entry_count"] == 1


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        ("missing", "required"),
        ("malformed_ref", "unsupported or vague"),
        ("missing_scope", "required"),
        ("actor_only", "actor identity alone"),
        ("owner_label_only", "required"),
        ("scope_mismatch", "authority scope mismatch"),
        ("digest_mismatch", "authority digest mismatch"),
        ("expired", "authority fixture is expired"),
        ("not_effective", "authority is not effective"),
        ("production_claim", "non-production boundaries"),
    ],
)
def test_authority_failures_are_rejected_without_append(
    tmp_path: Path, mutation: str, message: str
) -> None:
    bundle = make_bundle(tmp_path)
    args = [str(item) for item in bundle["args"]]
    if mutation == "missing":
        args = remove_arg(args, "--authority-file")
    elif mutation == "malformed_ref":
        args = replace_arg(args, "--authority-ref", "latest proof")
    elif mutation == "missing_scope":
        args = remove_arg(args, "--authority-scope")
    elif mutation == "actor_only":
        args = replace_arg(args, "--actor-id", "fixture://iteration2/one")
    elif mutation == "owner_label_only":
        args = remove_arg(replace_arg(args, "--actor-id", "owner"), "--authority-file")
    elif mutation == "scope_mismatch":
        args = replace_arg(args, "--authority-scope", "repository-source:other")
    elif mutation == "digest_mismatch":
        args = replace_arg(args, "--authority-digest", "0" * 64)
    else:
        authority = dict(bundle["authority_value"])
        if mutation == "expired":
            authority["expires_at"] = "2026-07-13T16:00:00.000000Z"
        elif mutation == "not_effective":
            authority["effective_at"] = "2026-07-13T16:30:00.000000Z"
        else:
            authority["production_acceptance_enabled"] = True
        canonical_write(Path(bundle["authority"]), authority)
        args = replace_arg(args, "--authority-digest", sha256(Path(bundle["authority"])))
    result = run_cli(*args)
    assert result.returncode != 0
    assert message.lower() in result.stderr.lower()
    assert not entry_files(bundle)


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        ("missing", "required"),
        ("missing_digest", "fields mismatch"),
        ("malformed_digest", "lowercase sha256"),
        ("run_mismatch", "source run mismatch"),
        ("subject_mismatch", "subject mismatch"),
        ("vague_ref", "not 'latest'"),
        ("unsupported_type", "unsupported evidence_type"),
        ("artifact_digest", "artifact digest mismatch"),
    ],
)
def test_evidence_failures_are_rejected_without_append(
    tmp_path: Path, mutation: str, message: str
) -> None:
    bundle = make_bundle(tmp_path)
    args = [str(item) for item in bundle["args"]]
    if mutation == "missing":
        args = remove_arg(args, "--evidence-manifest")
    else:
        manifest = dict(bundle["manifest_value"])
        if mutation == "missing_digest":
            del manifest["artifact_digest"]
        elif mutation == "malformed_digest":
            manifest["artifact_digest"] = "ABC"
        elif mutation == "run_mismatch":
            manifest["source_run_id"] = "run_20260713T170000000000Z_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        elif mutation == "subject_mismatch":
            manifest["subject"] = {"subject_type": "repository", "subject_id": f"other@{HEAD}"}
        elif mutation == "vague_ref":
            manifest["evidence_ref"] = "proof://iteration2/latest"
        elif mutation == "unsupported_type":
            manifest["evidence_type"] = "screenshot"
        else:
            manifest["artifact_digest"] = "0" * 64
        canonical_write(Path(bundle["manifest"]), manifest)
    result = run_cli(*args)
    assert result.returncode != 0
    assert message.lower() in result.stderr.lower()
    assert not entry_files(bundle)


def test_acceptance_id_conflict_is_refused_without_overwrite(tmp_path: Path) -> None:
    bundle = make_bundle(tmp_path)
    assert append(bundle).returncode == 0
    path = entry_files(bundle)[0]
    original = path.read_bytes()
    conflict_args = replace_arg([str(item) for item in bundle["args"]], "--actor-id", "different-actor")
    conflict = run_cli(*conflict_args)
    assert conflict.returncode == 1
    assert "ACCEPTANCE_ID conflict refused" in conflict.stderr
    assert path.read_bytes() == original
    assert len(entry_files(bundle)) == 1


def test_conditionally_accepted_requires_limitations_and_rejected_requires_reason(tmp_path: Path) -> None:
    conditional = make_bundle(tmp_path / "conditional", scope="scope:conditional", suffix="conditional")
    args = replace_arg([str(item) for item in conditional["args"]], "--decision", "CONDITIONALLY_ACCEPTED")
    refused = run_cli(*args)
    assert refused.returncode == 1
    assert "requires explicit limitations" in refused.stderr
    accepted = run_cli(*args, "--limitation", "owner recheck pending")
    assert accepted.returncode == 0, accepted.stderr
    rejected = make_bundle(tmp_path / "rejected", scope="scope:rejected", suffix="rejected")
    args = replace_arg([str(item) for item in rejected["args"]], "--decision", "REJECTED")
    refused = run_cli(*args)
    assert refused.returncode == 1
    assert "requires an explicit reason" in refused.stderr
    assert run_cli(*args, "--reason", "evidence failed").returncode == 0


def test_supersession_preserves_predecessor_and_current_query_uses_sequence(tmp_path: Path) -> None:
    bundle = make_bundle(tmp_path)
    assert append(bundle).returncode == 0
    first_path = entry_files(bundle)[0]
    first_bytes = first_path.read_bytes()
    args = replace_arg([str(item) for item in bundle["args"]], "--acceptance-id", ACCEPTANCE_2)
    args = replace_arg(args, "--effective-at", RECORDED_2)
    args = replace_arg(args, "--recorded-at", RECORDED_2)
    second = run_cli(*args, "--supersedes", ACCEPTANCE_1, "--unresolved", "production authority absent")
    assert second.returncode == 0, second.stderr
    assert first_path.read_bytes() == first_bytes
    files = entry_files(bundle)
    assert len(files) == 2
    assert json.loads(files[1].read_text())["record_sequence"] == 2
    current = run_cli(
        "current", "--root", str(bundle["root"]), "--subject-type", "repository",
        "--subject-id", SUBJECT_ID, "--scope", SCOPE,
    )
    current_value = json.loads(current.stdout)
    assert current_value["current"]["acceptance_id"] == ACCEPTANCE_2
    assert current_value["current"]["supersedes_acceptance_id"] == ACCEPTANCE_1
    history = run_cli(
        "history", "--root", str(bundle["root"]), "--subject-type", "repository",
        "--subject-id", SUBJECT_ID, "--scope", SCOPE,
    )
    history_value = json.loads(history.stdout)
    assert [item["acceptance_id"] for item in history_value["entries"]] == [ACCEPTANCE_1, ACCEPTANCE_2]


def test_superseded_decision_requires_current_predecessor_and_reason(tmp_path: Path) -> None:
    bundle = make_bundle(tmp_path)
    args = replace_arg([str(item) for item in bundle["args"]], "--decision", "SUPERSEDED")
    assert run_cli(*args).returncode == 1
    assert append(bundle).returncode == 0
    args = replace_arg(args, "--acceptance-id", ACCEPTANCE_2)
    args = replace_arg(args, "--effective-at", RECORDED_2)
    args = replace_arg(args, "--recorded-at", RECORDED_2)
    missing_reason = run_cli(*args, "--supersedes", ACCEPTANCE_1)
    assert missing_reason.returncode == 1
    result = run_cli(*args, "--supersedes", ACCEPTANCE_1, "--reason", "replaced by later review")
    assert result.returncode == 0, result.stderr
    current = run_cli(
        "current", "--root", str(bundle["root"]), "--subject-type", "repository",
        "--subject-id", SUBJECT_ID, "--scope", SCOPE,
    )
    value = json.loads(current.stdout)
    assert value["status"] == "SUPERSEDED"
    assert value["is_current_accepted_state"] is False


def test_second_decision_without_exact_current_supersession_is_refused(tmp_path: Path) -> None:
    bundle = make_bundle(tmp_path)
    assert append(bundle).returncode == 0
    args = replace_arg([str(item) for item in bundle["args"]], "--acceptance-id", ACCEPTANCE_2)
    result = run_cli(*args)
    assert result.returncode == 1
    assert "exact supersedes_acceptance_id required" in result.stderr
    wrong = run_cli(*args, "--supersedes", "acceptance_20260713T150000000000Z_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    assert wrong.returncode == 1
    assert "exact supersedes_acceptance_id required" in wrong.stderr


def test_no_decision_query_is_explicit_and_non_production(tmp_path: Path) -> None:
    result = run_cli(
        "current", "--root", str(tmp_path / "missing-ledger"), "--subject-type", "repository",
        "--subject-id", SUBJECT_ID, "--scope", SCOPE,
    )
    assert result.returncode == 0, result.stderr
    value = json.loads(result.stdout)
    assert value == {
        "current": None,
        "is_current_accepted_state": False,
        "production_acceptance_enabled": False,
        "scope": SCOPE,
        "status": "NO_DECISION",
        "subject": {"subject_id": SUBJECT_ID, "subject_type": "repository"},
    }


@pytest.mark.parametrize("mutation", ["truncate", "digest", "future_schema", "filename", "extra_newline"])
def test_corrupt_or_malformed_entry_fails_closed(tmp_path: Path, mutation: str) -> None:
    bundle = make_bundle(tmp_path)
    assert append(bundle).returncode == 0
    path = entry_files(bundle)[0]
    if mutation == "truncate":
        path.write_bytes(path.read_bytes()[:-7])
    elif mutation == "extra_newline":
        path.write_bytes(path.read_bytes() + b"\n")
    elif mutation == "filename":
        path.rename(path.with_name("00000000000000000002-" + ACCEPTANCE_1 + ".jsonl"))
    else:
        value = json.loads(path.read_text())
        if mutation == "digest":
            value["actor_id"] = "tampered"
        else:
            value["schema_version"] = 99
            value["payload_sha256"] = ledger.payload_digest(value)
        canonical_write(path, value)
    result = run_cli("validate", "--root", str(bundle["root"]))
    assert result.returncode == 1


def test_duplicate_id_and_ambiguous_current_are_detected(tmp_path: Path) -> None:
    duplicate = make_bundle(tmp_path / "duplicate")
    assert append(duplicate).returncode == 0
    original = json.loads(entry_files(duplicate)[0].read_text())
    copied = dict(original)
    copied["record_sequence"] = 2
    copied["payload_sha256"] = ledger.payload_digest(copied)
    second_path = Path(duplicate["root"]) / "entries" / ledger._entry_filename(copied)
    canonical_write(second_path, copied)
    result = run_cli("validate", "--root", str(duplicate["root"]))
    assert result.returncode == 1
    assert "duplicate acceptance_id" in result.stderr

    ambiguous = make_bundle(tmp_path / "ambiguous")
    assert append(ambiguous).returncode == 0
    first = json.loads(entry_files(ambiguous)[0].read_text())
    second = dict(first)
    second["acceptance_id"] = ACCEPTANCE_2
    second["record_sequence"] = 2
    second["recorded_at"] = RECORDED_2
    second["effective_at"] = RECORDED_2
    second["payload_sha256"] = ledger.payload_digest(second)
    canonical_write(Path(ambiguous["root"]) / "entries" / ledger._entry_filename(second), second)
    result = run_cli("validate", "--root", str(ambiguous["root"]))
    assert result.returncode == 1
    assert "ambiguous current state" in result.stderr


def test_query_bound_and_history_bound_fail_closed(tmp_path: Path) -> None:
    bundle = make_bundle(tmp_path)
    assert append(bundle).returncode == 0
    args = replace_arg([str(item) for item in bundle["args"]], "--acceptance-id", ACCEPTANCE_2)
    args = replace_arg(args, "--effective-at", RECORDED_2)
    args = replace_arg(args, "--recorded-at", RECORDED_2)
    assert run_cli(*args, "--supersedes", ACCEPTANCE_1).returncode == 0
    current = run_cli(
        "current", "--root", str(bundle["root"]), "--subject-type", "repository",
        "--subject-id", SUBJECT_ID, "--scope", SCOPE, "--max-entries", "1",
    )
    assert current.returncode == 1
    assert "bounded query limit" in current.stderr
    history = run_cli(
        "history", "--root", str(bundle["root"]), "--subject-type", "repository",
        "--subject-id", SUBJECT_ID, "--scope", SCOPE, "--limit", "1",
    )
    assert history.returncode == 1
    assert "history exceeds" in history.stderr


def test_concurrent_exact_replay_has_one_append_and_monotonic_store(tmp_path: Path) -> None:
    bundle = make_bundle(tmp_path)
    command = [str(CLI), *[str(item) for item in bundle["args"]]]
    processes = [subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(8)]
    results = [process.communicate(timeout=15) + (process.returncode,) for process in processes]
    assert sum('"append": "APPENDED"' in stdout for stdout, _stderr, _code in results) == 1
    assert sum('"append": "EXISTS_IDENTICAL"' in stdout for stdout, _stderr, _code in results) == 7
    assert all(code == 0 for _stdout, _stderr, code in results)
    assert len(entry_files(bundle)) == 1
    assert run_cli("validate", "--root", str(bundle["root"])).returncode == 0


def test_concurrent_independent_scopes_get_unique_contiguous_sequences(tmp_path: Path) -> None:
    bundles = [make_bundle(tmp_path, scope=f"scope:parallel-{index}", suffix=f"parallel-{index}") for index in range(8)]
    root = Path(bundles[0]["root"])
    commands: list[list[str]] = []
    for index, bundle in enumerate(bundles):
        args = replace_arg([str(item) for item in bundle["args"]], "--acceptance-id", f"acceptance_20260713T16{10 + index:02d}00000000Z_{index:032x}")
        commands.append([str(CLI), *args])
    processes = [subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for command in commands]
    results = [process.communicate(timeout=15) + (process.returncode,) for process in processes]
    assert all(code == 0 for _stdout, _stderr, code in results), results
    entries = [json.loads(path.read_text()) for path in sorted((root / "entries").glob("*.jsonl"))]
    assert [entry["record_sequence"] for entry in entries] == list(range(1, 9))
    assert run_cli("validate", "--root", str(root)).returncode == 0


def test_lock_timeout_is_nonzero_and_does_not_append(tmp_path: Path) -> None:
    bundle = make_bundle(tmp_path)
    ledger.prepare_store(Path(bundle["root"]))
    lock_path = Path(bundle["root"]) / ".append.lock"
    with lock_path.open("a+b") as lock_handle:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        args = [str(item) for item in bundle["args"]] + ["--lock-timeout", "0.05"]
        result = run_cli(*args)
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
    assert result.returncode == 1
    assert "ledger lock timeout" in result.stderr
    assert not entry_files(bundle)


def test_killed_write_is_detected_and_explicitly_quarantined(tmp_path: Path) -> None:
    bundle = make_bundle(tmp_path)
    child = tmp_path / "killed-writer.py"
    ready = tmp_path / "ready"
    child.write_text(
        """
import json, os, pathlib, sys, time
sys.path.insert(0, os.environ['OPS'])
import acceptance_ledger as ledger
args = ledger.parse_args(json.loads(os.environ['ARGS']))
def interrupted(descriptor, data, on_progress=None):
    written = os.write(descriptor, data[:max(1, len(data)//2)])
    pathlib.Path(os.environ['READY']).write_text(str(written))
    while True: time.sleep(1)
ledger._write_all = interrupted
ledger.append_entry(args)
""",
        encoding="utf-8",
    )
    environment = dict(os.environ)
    environment.update({
        "OPS": str(OPS), "ARGS": json.dumps([str(item) for item in bundle["args"]]), "READY": str(ready),
    })
    process = subprocess.Popen([sys.executable, str(child)], env=environment)
    for _ in range(200):
        if ready.exists():
            break
        time.sleep(0.01)
    assert ready.exists()
    process.send_signal(signal.SIGKILL)
    process.wait(timeout=5)
    assert process.returncode == -signal.SIGKILL
    assert not entry_files(bundle)
    detected = run_cli("validate", "--root", str(bundle["root"]))
    assert detected.returncode == 1
    assert "partial_pending=" in detected.stderr
    quarantined = run_cli("validate", "--root", str(bundle["root"]), "--quarantine-partials")
    assert quarantined.returncode == 0, quarantined.stderr
    assert "quarantined_partials=1" in quarantined.stdout
    assert len(list((Path(bundle["root"]) / "quarantine").iterdir())) == 1


def test_external_reference_drift_is_detected_by_cold_process(tmp_path: Path) -> None:
    bundle = make_bundle(tmp_path)
    assert append(bundle).returncode == 0
    Path(bundle["evidence"]).write_text("tampered\n", encoding="utf-8")
    result = run_cli("validate", "--root", str(bundle["root"]))
    assert result.returncode == 1
    assert "evidence artifact digest no longer matches" in result.stderr


def test_production_root_and_non_tmp_roots_are_refused() -> None:
    current = run_cli(
        "current", "--root", str(ledger.PRODUCTION_ROOT), "--subject-type", "repository",
        "--subject-id", SUBJECT_ID, "--scope", SCOPE,
    )
    assert current.returncode == 1
    assert "isolated storage under /tmp" in current.stderr
    assert not ledger.PRODUCTION_ROOT.exists()


def test_cli_has_no_notifier_habitat_event_bus_or_production_enablement_path() -> None:
    source = (OPS / "acceptance_ledger.py").read_text()
    wrapper = CLI.read_text()
    combined = source + wrapper
    assert "notify-session" not in combined
    assert "notify-proof" not in combined
    assert "discord" not in combined.lower()
    assert "habitat" not in combined.lower()
    assert "event bus" not in combined.lower()
    assert "requests." not in combined
    assert "production_acceptance_enabled\": True" not in combined
    assert not ledger.PRODUCTION_ROOT.exists()
