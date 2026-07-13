#!/usr/bin/env python3
"""Append and query an isolated, authority- and evidence-bound acceptance ledger."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

from run_record_store import (
    RUN_ID_RE,
    SUBJECT_TYPES,
    RunRecordError,
    _write_all,
    canonical_json,
    canonical_timestamp,
    fsync_directory,
    normalize_subject,
    validate_record_file,
)


SCHEMA_VERSION = 1
SCHEMA_ID = "slimy-harness.acceptance-decision.v1"
LEDGER_ENTRY_TYPE = "ACCEPTANCE_DECISION"
DECISIONS = frozenset({"ACCEPTED", "CONDITIONALLY_ACCEPTED", "REJECTED", "SUPERSEDED"})
AUTHORITY_TYPES = frozenset({"test_fixture"})
EVIDENCE_TYPES = frozenset({"proof_manifest", "qa_record", "test_report"})
PRODUCTION_ROOT = Path("/home/slimy/harness-logs/acceptance-ledger")
MAX_QUERY_ENTRIES = 10_000
MAX_FILE_BYTES = 10 * 1024 * 1024
ACCEPTANCE_ID_RE = re.compile(r"^acceptance_[0-9]{8}T[0-9]{12}Z_[0-9a-f]{32}$")
DIGEST_RE = re.compile(r"^[0-9a-f]{64}$")
REF_RE = re.compile(r"^(?:fixture|proof|qa|test)://[a-z0-9][a-z0-9._/@:-]{2,255}$")
ENTRY_KEYS = {
    "schema_version", "schema_id", "ledger_entry_type", "acceptance_id", "decision",
    "run_id", "run_record_path", "subject", "scope", "actor_id", "authority",
    "evidence", "limitations", "unresolved", "reason", "supersedes_acceptance_id",
    "effective_at", "recorded_at", "record_sequence", "production_acceptance_enabled",
    "payload_sha256",
}
AUTHORITY_KEYS = {
    "authority_type", "authority_ref", "authority_scope", "authority_digest",
    "artifact_path", "issued_at", "effective_at", "expires_at",
    "authority_authentication", "production_authority_verification",
}
EVIDENCE_KEYS = {
    "evidence_type", "evidence_ref", "evidence_digest", "source_run_id", "subject",
    "validation_summary", "evidence_created_at", "manifest_path", "artifact_path",
}
AUTHORITY_ARTIFACT_KEYS = {
    "schema_version", "authority_artifact_type", "authority_type", "authority_ref",
    "authority_scope", "issued_at", "effective_at", "expires_at",
    "authority_authentication", "production_authority_verification",
    "production_acceptance_enabled",
}
EVIDENCE_MANIFEST_KEYS = {
    "schema_version", "evidence_manifest_type", "evidence_type", "evidence_ref",
    "source_run_id", "subject", "validation_summary", "evidence_created_at",
    "artifact_path", "artifact_digest",
}


class AcceptanceLedgerError(Exception):
    """A deterministic validation, query, or safe-write failure."""


def _translate_run_error(action: Callable[[], Any]) -> Any:
    try:
        return action()
    except RunRecordError as exc:
        raise AcceptanceLedgerError(str(exc)) from exc


def generate_acceptance_id(now: datetime | None = None) -> str:
    stamp = _translate_run_error(lambda: canonical_timestamp(now.isoformat().replace("+00:00", "Z"))) if now else canonical_timestamp()
    compact = stamp.replace("-", "").replace(":", "").replace(".", "")
    return f"acceptance_{compact}_{uuid.uuid4().hex}"


def payload_digest(entry: dict[str, Any]) -> str:
    payload = dict(entry)
    payload.pop("payload_sha256", None)
    return hashlib.sha256(canonical_json(payload)).hexdigest()


def _require_text(value: Any, name: str, *, maximum: int = 1024) -> str:
    if not isinstance(value, str) or not value or value != value.strip() or len(value) > maximum:
        raise AcceptanceLedgerError(f"{name} must be a non-empty canonical string (max {maximum})")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise AcceptanceLedgerError(f"{name} must not contain control characters")
    return value


def _canonical_time(value: Any, name: str) -> str:
    if not isinstance(value, str):
        raise AcceptanceLedgerError(f"{name} must be a canonical UTC timestamp")
    try:
        canonical = canonical_timestamp(value)
    except RunRecordError as exc:
        raise AcceptanceLedgerError(f"{name}: {exc}") from exc
    if canonical != value:
        raise AcceptanceLedgerError(f"{name} is not canonical")
    return value


def _parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value[:-1] + "+00:00")


def _validate_ref(value: Any, name: str, *, schemes: tuple[str, ...]) -> str:
    reference = _require_text(value, name, maximum=264)
    if not REF_RE.fullmatch(reference) or not reference.startswith(tuple(f"{scheme}://" for scheme in schemes)):
        raise AcceptanceLedgerError(f"{name} has an unsupported or vague reference format")
    if "latest" in re.split(r"[/:._@-]+", reference.lower()):
        raise AcceptanceLedgerError(f"{name} must identify exact evidence or authority, not 'latest'")
    return reference


def _validate_digest(value: Any, name: str) -> str:
    if not isinstance(value, str) or not DIGEST_RE.fullmatch(value):
        raise AcceptanceLedgerError(f"{name} must be a lowercase sha256 digest")
    return value


def _validate_string_list(value: Any, name: str) -> list[str]:
    if not isinstance(value, list) or len(value) > 64:
        raise AcceptanceLedgerError(f"{name} must be a bounded list")
    result = [_require_text(item, f"{name} item", maximum=1024) for item in value]
    if len(result) != len(set(result)):
        raise AcceptanceLedgerError(f"{name} must not contain duplicates")
    return result


def _ensure_isolated_root(root: Path) -> Path:
    resolved = root.resolve(strict=False)
    if root != resolved or not root.is_absolute():
        raise AcceptanceLedgerError("ledger root must be an absolute normalized path")
    if resolved == PRODUCTION_ROOT or Path("/tmp") not in resolved.parents:
        raise AcceptanceLedgerError("Iteration 2 ledger root must be explicit isolated storage under /tmp")
    if resolved.exists() and (resolved.is_symlink() or not resolved.is_dir()):
        raise AcceptanceLedgerError(f"ledger root must be a real directory: {resolved}")
    return resolved


def _require_isolated_file(path: Path, isolation_base: Path, name: str) -> Path:
    resolved = path.resolve(strict=False)
    if path != resolved or not path.is_absolute() or isolation_base not in resolved.parents:
        raise AcceptanceLedgerError(f"{name} must be an absolute normalized file under {isolation_base}")
    try:
        file_stat = resolved.lstat()
    except FileNotFoundError as exc:
        raise AcceptanceLedgerError(f"{name} not found: {resolved}") from exc
    if resolved.is_symlink() or not stat.S_ISREG(file_stat.st_mode):
        raise AcceptanceLedgerError(f"{name} must be a regular non-symlink file: {resolved}")
    if file_stat.st_size > MAX_FILE_BYTES:
        raise AcceptanceLedgerError(f"{name} exceeds the {MAX_FILE_BYTES}-byte bound")
    return resolved


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise AcceptanceLedgerError(f"duplicate JSON key refused: {key}")
        result[key] = value
    return result


def _load_canonical_json(path: Path, isolation_base: Path, name: str) -> tuple[dict[str, Any], bytes]:
    safe_path = _require_isolated_file(path, isolation_base, name)
    data = safe_path.read_bytes()
    if not data.endswith(b"\n") or data.count(b"\n") != 1:
        raise AcceptanceLedgerError(f"{name} must be exactly one newline-terminated canonical JSON object")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_no_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AcceptanceLedgerError(f"{name} is not valid canonical JSON: {exc}") from exc
    if not isinstance(value, dict) or canonical_json(value) != data:
        raise AcceptanceLedgerError(f"{name} bytes are not canonical JSON")
    return value, data


def _validate_subject(value: Any, run_id: str) -> dict[str, str]:
    if not isinstance(value, dict) or set(value) != {"subject_type", "subject_id"}:
        raise AcceptanceLedgerError("subject must contain exactly subject_type and subject_id")
    try:
        subject_type, subject_id = normalize_subject(value["subject_type"], value["subject_id"], run_id)
    except RunRecordError as exc:
        raise AcceptanceLedgerError(str(exc)) from exc
    if value != {"subject_type": subject_type, "subject_id": subject_id}:
        raise AcceptanceLedgerError("subject identity is not canonical")
    return value


def validate_entry(entry: Any) -> dict[str, Any]:
    if not isinstance(entry, dict) or set(entry) != ENTRY_KEYS:
        missing = sorted(ENTRY_KEYS - set(entry if isinstance(entry, dict) else {}))
        extra = sorted(set(entry if isinstance(entry, dict) else {}) - ENTRY_KEYS)
        raise AcceptanceLedgerError(f"schema fields mismatch missing={missing} extra={extra}")
    if entry["schema_version"] != SCHEMA_VERSION or entry["schema_id"] != SCHEMA_ID:
        raise AcceptanceLedgerError("unsupported acceptance schema identity")
    if entry["ledger_entry_type"] != LEDGER_ENTRY_TYPE:
        raise AcceptanceLedgerError("unsupported ledger_entry_type")
    if not isinstance(entry["acceptance_id"], str) or not ACCEPTANCE_ID_RE.fullmatch(entry["acceptance_id"]):
        raise AcceptanceLedgerError("invalid ACCEPTANCE_ID format")
    if entry["decision"] not in DECISIONS:
        raise AcceptanceLedgerError("unsupported decision")
    if not isinstance(entry["run_id"], str) or not RUN_ID_RE.fullmatch(entry["run_id"]):
        raise AcceptanceLedgerError("invalid RUN_ID format")
    _require_text(entry["run_record_path"], "run_record_path", maximum=4096)
    _validate_subject(entry["subject"], entry["run_id"])
    _require_text(entry["scope"], "scope", maximum=256)
    actor = _require_text(entry["actor_id"], "actor_id", maximum=128)
    authority = entry["authority"]
    if not isinstance(authority, dict) or set(authority) != AUTHORITY_KEYS:
        raise AcceptanceLedgerError("authority fields mismatch")
    if authority["authority_type"] not in AUTHORITY_TYPES:
        raise AcceptanceLedgerError("unsupported authority_type; production authority verification is not implemented")
    authority_ref = _validate_ref(authority["authority_ref"], "authority_ref", schemes=("fixture",))
    if actor == authority_ref:
        raise AcceptanceLedgerError("actor identity alone cannot serve as authority_ref")
    _require_text(authority["authority_scope"], "authority_scope", maximum=256)
    _validate_digest(authority["authority_digest"], "authority_digest")
    _require_text(authority["artifact_path"], "authority.artifact_path", maximum=4096)
    _canonical_time(authority["issued_at"], "authority.issued_at")
    _canonical_time(authority["effective_at"], "authority.effective_at")
    if authority["expires_at"] is not None:
        _canonical_time(authority["expires_at"], "authority.expires_at")
    if authority["authority_authentication"] != "TEST_FIXTURE_ONLY":
        raise AcceptanceLedgerError("authority authentication must remain TEST_FIXTURE_ONLY")
    if authority["production_authority_verification"] != "NOT_IMPLEMENTED":
        raise AcceptanceLedgerError("production authority verification must remain NOT_IMPLEMENTED")
    if not isinstance(entry["evidence"], list) or not entry["evidence"]:
        raise AcceptanceLedgerError("at least one exact evidence reference is required")
    seen_evidence: set[tuple[str, str]] = set()
    for item in entry["evidence"]:
        if not isinstance(item, dict) or set(item) != EVIDENCE_KEYS:
            raise AcceptanceLedgerError("evidence fields mismatch")
        if item["evidence_type"] not in EVIDENCE_TYPES:
            raise AcceptanceLedgerError("unsupported evidence_type")
        _validate_ref(item["evidence_ref"], "evidence_ref", schemes=("proof", "qa", "test"))
        _validate_digest(item["evidence_digest"], "evidence_digest")
        if item["source_run_id"] != entry["run_id"]:
            raise AcceptanceLedgerError("evidence source run mismatch")
        if _validate_subject(item["subject"], entry["run_id"]) != entry["subject"]:
            raise AcceptanceLedgerError("evidence subject mismatch")
        _require_text(item["validation_summary"], "validation_summary", maximum=4096)
        _canonical_time(item["evidence_created_at"], "evidence_created_at")
        _require_text(item["manifest_path"], "evidence.manifest_path", maximum=4096)
        _require_text(item["artifact_path"], "evidence.artifact_path", maximum=4096)
        identity = (item["evidence_type"], item["evidence_ref"])
        if identity in seen_evidence:
            raise AcceptanceLedgerError("duplicate evidence reference refused")
        seen_evidence.add(identity)
    limitations = _validate_string_list(entry["limitations"], "limitations")
    _validate_string_list(entry["unresolved"], "unresolved")
    if entry["reason"] is not None:
        _require_text(entry["reason"], "reason", maximum=2048)
    if entry["decision"] == "CONDITIONALLY_ACCEPTED" and not limitations:
        raise AcceptanceLedgerError("CONDITIONALLY_ACCEPTED requires explicit limitations")
    if entry["decision"] in {"REJECTED", "SUPERSEDED"} and entry["reason"] is None:
        raise AcceptanceLedgerError(f"{entry['decision']} requires an explicit reason")
    supersedes = entry["supersedes_acceptance_id"]
    if supersedes is not None and (not isinstance(supersedes, str) or not ACCEPTANCE_ID_RE.fullmatch(supersedes)):
        raise AcceptanceLedgerError("invalid supersedes_acceptance_id")
    if entry["decision"] == "SUPERSEDED" and supersedes is None:
        raise AcceptanceLedgerError("SUPERSEDED requires a predecessor")
    effective_at = _canonical_time(entry["effective_at"], "effective_at")
    recorded_at = _canonical_time(entry["recorded_at"], "recorded_at")
    if _parse_time(effective_at) > _parse_time(recorded_at):
        raise AcceptanceLedgerError("effective_at cannot be later than recorded_at")
    if not isinstance(entry["record_sequence"], int) or isinstance(entry["record_sequence"], bool) or entry["record_sequence"] < 1:
        raise AcceptanceLedgerError("record_sequence must be a positive integer")
    if entry["production_acceptance_enabled"] is not False:
        raise AcceptanceLedgerError("production acceptance must remain disabled")
    _validate_digest(entry["payload_sha256"], "payload_sha256")
    if payload_digest(entry) != entry["payload_sha256"]:
        raise AcceptanceLedgerError("payload digest mismatch")
    return entry


def validate_entry_bytes(data: bytes) -> dict[str, Any]:
    if not data.endswith(b"\n") or data.count(b"\n") != 1:
        raise AcceptanceLedgerError("ledger entry must be exactly one newline-terminated JSONL object")
    try:
        entry = json.loads(data.decode("utf-8"), object_pairs_hook=_no_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AcceptanceLedgerError(f"ledger entry parse failed: {exc}") from exc
    validated = validate_entry(entry)
    if canonical_json(validated) != data:
        raise AcceptanceLedgerError("ledger entry bytes are not canonical JSON")
    return validated


def _entry_filename(entry: dict[str, Any]) -> str:
    return f"{entry['record_sequence']:020d}-{entry['acceptance_id']}.jsonl"


def validate_entry_file(path: Path) -> dict[str, Any]:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as exc:
        raise AcceptanceLedgerError(f"ledger entry not found: {path}") from exc
    if path.is_symlink() or not stat.S_ISREG(mode):
        raise AcceptanceLedgerError(f"ledger entry is not a regular non-symlink file: {path}")
    entry = validate_entry_bytes(path.read_bytes())
    if path.name != _entry_filename(entry):
        raise AcceptanceLedgerError(f"ledger entry filename mismatch expected={_entry_filename(entry)}")
    return entry


def _artifact_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_authority(args: argparse.Namespace, isolation_base: Path) -> dict[str, Any]:
    artifact, data = _load_canonical_json(args.authority_file, isolation_base, "authority artifact")
    if set(artifact) != AUTHORITY_ARTIFACT_KEYS:
        raise AcceptanceLedgerError("authority artifact fields mismatch")
    if artifact["schema_version"] != 1 or artifact["authority_artifact_type"] != "TEST_AUTHORITY_DECLARATION":
        raise AcceptanceLedgerError("unsupported authority artifact schema")
    if args.authority_type not in AUTHORITY_TYPES or artifact["authority_type"] != args.authority_type:
        raise AcceptanceLedgerError("authority_type mismatch or unsupported production authority")
    reference = _validate_ref(args.authority_ref, "authority_ref", schemes=("fixture",))
    if artifact["authority_ref"] != reference:
        raise AcceptanceLedgerError("authority_ref mismatch")
    scope = _require_text(args.authority_scope, "authority_scope", maximum=256)
    if artifact["authority_scope"] != scope or scope != args.scope:
        raise AcceptanceLedgerError("authority scope mismatch")
    digest = _validate_digest(args.authority_digest, "authority_digest")
    if hashlib.sha256(data).hexdigest() != digest:
        raise AcceptanceLedgerError("authority digest mismatch")
    issued_at = _canonical_time(artifact["issued_at"], "authority issued_at")
    authority_effective = _canonical_time(artifact["effective_at"], "authority effective_at")
    expires_at = artifact["expires_at"]
    if expires_at is not None:
        expires_at = _canonical_time(expires_at, "authority expires_at")
    if _parse_time(authority_effective) < _parse_time(issued_at):
        raise AcceptanceLedgerError("authority cannot become effective before issuance")
    decision_effective = _parse_time(args.effective_at)
    recorded = _parse_time(args.recorded_at)
    if decision_effective < _parse_time(authority_effective):
        raise AcceptanceLedgerError("authority is not effective for this decision")
    if expires_at is not None and (decision_effective >= _parse_time(expires_at) or recorded >= _parse_time(expires_at)):
        raise AcceptanceLedgerError("authority fixture is expired")
    if artifact["authority_authentication"] != "TEST_FIXTURE_ONLY" or artifact["production_authority_verification"] != "NOT_IMPLEMENTED" or artifact["production_acceptance_enabled"] is not False:
        raise AcceptanceLedgerError("authority fixture must visibly preserve non-production boundaries")
    return {
        "authority_type": args.authority_type,
        "authority_ref": reference,
        "authority_scope": scope,
        "authority_digest": digest,
        "artifact_path": str(args.authority_file),
        "issued_at": issued_at,
        "effective_at": authority_effective,
        "expires_at": expires_at,
        "authority_authentication": "TEST_FIXTURE_ONLY",
        "production_authority_verification": "NOT_IMPLEMENTED",
    }


def _load_evidence(manifest_path: Path, isolation_base: Path, run_record: dict[str, Any]) -> dict[str, Any]:
    manifest, _data = _load_canonical_json(manifest_path, isolation_base, "evidence manifest")
    if set(manifest) != EVIDENCE_MANIFEST_KEYS:
        raise AcceptanceLedgerError("evidence manifest fields mismatch")
    if manifest["schema_version"] != 1 or manifest["evidence_manifest_type"] != "ACCEPTANCE_EVIDENCE":
        raise AcceptanceLedgerError("unsupported evidence manifest schema")
    evidence_type = manifest["evidence_type"]
    if evidence_type not in EVIDENCE_TYPES:
        raise AcceptanceLedgerError("unsupported evidence_type")
    evidence_ref = _validate_ref(manifest["evidence_ref"], "evidence_ref", schemes=("proof", "qa", "test"))
    if manifest["source_run_id"] != run_record["run_id"]:
        raise AcceptanceLedgerError("evidence source run mismatch")
    subject = _validate_subject(manifest["subject"], run_record["run_id"])
    expected_subject = {"subject_type": run_record["subject_type"], "subject_id": run_record["subject_id"]}
    if subject != expected_subject:
        raise AcceptanceLedgerError("evidence subject mismatch")
    validation_summary = _require_text(manifest["validation_summary"], "validation_summary", maximum=4096)
    evidence_created_at = _canonical_time(manifest["evidence_created_at"], "evidence_created_at")
    artifact_path = _require_isolated_file(Path(manifest["artifact_path"]), isolation_base, "evidence artifact")
    artifact_digest = _validate_digest(manifest["artifact_digest"], "evidence artifact_digest")
    if _artifact_sha256(artifact_path) != artifact_digest:
        raise AcceptanceLedgerError("evidence artifact digest mismatch")
    return {
        "evidence_type": evidence_type,
        "evidence_ref": evidence_ref,
        "evidence_digest": artifact_digest,
        "source_run_id": run_record["run_id"],
        "subject": subject,
        "validation_summary": validation_summary,
        "evidence_created_at": evidence_created_at,
        "manifest_path": str(manifest_path),
        "artifact_path": str(artifact_path),
    }


def build_entry(args: argparse.Namespace, sequence: int) -> dict[str, Any]:
    root = _ensure_isolated_root(args.root)
    isolation_base = root.parent
    run_path = _require_isolated_file(args.run_record, isolation_base, "run record")
    run_record = _translate_run_error(lambda: validate_record_file(run_path))
    authority = _load_authority(args, isolation_base)
    evidence = [_load_evidence(path, isolation_base, run_record) for path in args.evidence_manifest]
    entry: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "schema_id": SCHEMA_ID,
        "ledger_entry_type": LEDGER_ENTRY_TYPE,
        "acceptance_id": args.acceptance_id,
        "decision": args.decision,
        "run_id": run_record["run_id"],
        "run_record_path": str(run_path),
        "subject": {"subject_type": run_record["subject_type"], "subject_id": run_record["subject_id"]},
        "scope": args.scope,
        "actor_id": args.actor_id,
        "authority": authority,
        "evidence": evidence,
        "limitations": list(args.limitation),
        "unresolved": list(args.unresolved),
        "reason": args.reason,
        "supersedes_acceptance_id": args.supersedes,
        "effective_at": args.effective_at,
        "recorded_at": args.recorded_at,
        "record_sequence": sequence,
        "production_acceptance_enabled": False,
    }
    entry["payload_sha256"] = payload_digest(entry)
    return validate_entry(entry)


def prepare_store(root: Path) -> tuple[Path, Path, Path]:
    root = _ensure_isolated_root(root)
    root_preexisted = root.exists()
    root.mkdir(parents=True, exist_ok=True)
    if not root_preexisted:
        fsync_directory(root.parent)
    entries = root / "entries"
    pending = root / "pending"
    quarantine = root / "quarantine"
    for directory in (entries, pending, quarantine):
        preexisted = directory.exists()
        if preexisted and (directory.is_symlink() or not directory.is_dir()):
            raise AcceptanceLedgerError(f"ledger component must be a real directory: {directory}")
        directory.mkdir(mode=0o750, exist_ok=True)
        if not preexisted:
            fsync_directory(root)
    fsync_directory(root)
    return entries, pending, quarantine


def _validate_external_references(entry: dict[str, Any], root: Path) -> None:
    isolation_base = root.parent
    run_path = _require_isolated_file(Path(entry["run_record_path"]), isolation_base, "run record")
    run_record = _translate_run_error(lambda: validate_record_file(run_path))
    if run_record["run_id"] != entry["run_id"] or {
        "subject_type": run_record["subject_type"], "subject_id": run_record["subject_id"]
    } != entry["subject"]:
        raise AcceptanceLedgerError("ledger entry no longer matches its run record")
    authority_path = Path(entry["authority"]["artifact_path"])
    authority, authority_bytes = _load_canonical_json(authority_path, isolation_base, "authority artifact")
    if set(authority) != AUTHORITY_ARTIFACT_KEYS:
        raise AcceptanceLedgerError("authority artifact fields mismatch")
    if authority["schema_version"] != 1 or authority["authority_artifact_type"] != "TEST_AUTHORITY_DECLARATION":
        raise AcceptanceLedgerError("unsupported authority artifact schema")
    if hashlib.sha256(authority_bytes).hexdigest() != entry["authority"]["authority_digest"]:
        raise AcceptanceLedgerError("authority artifact digest no longer matches")
    for key in ("authority_type", "authority_ref", "authority_scope", "issued_at", "effective_at", "expires_at", "authority_authentication", "production_authority_verification"):
        if authority[key] != entry["authority"][key]:
            raise AcceptanceLedgerError(f"authority artifact mismatch: {key}")
    if authority.get("production_acceptance_enabled") is not False:
        raise AcceptanceLedgerError("authority artifact no longer preserves production boundary")
    for evidence in entry["evidence"]:
        manifest, _manifest_bytes = _load_canonical_json(Path(evidence["manifest_path"]), isolation_base, "evidence manifest")
        if set(manifest) != EVIDENCE_MANIFEST_KEYS:
            raise AcceptanceLedgerError("evidence manifest fields mismatch")
        if manifest["schema_version"] != 1 or manifest["evidence_manifest_type"] != "ACCEPTANCE_EVIDENCE":
            raise AcceptanceLedgerError("unsupported evidence manifest schema")
        if manifest["evidence_type"] != evidence["evidence_type"] or manifest["evidence_ref"] != evidence["evidence_ref"]:
            raise AcceptanceLedgerError("evidence manifest identity mismatch")
        if manifest["source_run_id"] != entry["run_id"] or manifest["subject"] != entry["subject"]:
            raise AcceptanceLedgerError("evidence manifest run or subject mismatch")
        if manifest["validation_summary"] != evidence["validation_summary"] or manifest["evidence_created_at"] != evidence["evidence_created_at"]:
            raise AcceptanceLedgerError("evidence manifest provenance mismatch")
        artifact_path = _require_isolated_file(Path(evidence["artifact_path"]), isolation_base, "evidence artifact")
        if manifest["artifact_path"] != str(artifact_path) or manifest["artifact_digest"] != evidence["evidence_digest"]:
            raise AcceptanceLedgerError("evidence manifest artifact mismatch")
        if _artifact_sha256(artifact_path) != evidence["evidence_digest"]:
            raise AcceptanceLedgerError("evidence artifact digest no longer matches")


def load_ledger(
    root: Path,
    *,
    max_entries: int = MAX_QUERY_ENTRIES,
    allow_missing: bool = False,
    ignore_pending: Path | None = None,
    ignore_all_pending: bool = False,
) -> list[dict[str, Any]]:
    root = _ensure_isolated_root(root)
    if not root.exists():
        if allow_missing:
            return []
        raise AcceptanceLedgerError(f"ledger root not found: {root}")
    entries_dir, pending, quarantine = (root / "entries", root / "pending", root / "quarantine")
    if any(path.is_symlink() or not path.is_dir() for path in (entries_dir, pending, quarantine)):
        raise AcceptanceLedgerError("ledger store is incomplete")
    paths = sorted(entries_dir.iterdir())
    if len(paths) > max_entries:
        raise AcceptanceLedgerError(f"ledger exceeds bounded query limit max_entries={max_entries}")
    entries: list[dict[str, Any]] = []
    by_id: dict[str, dict[str, Any]] = {}
    current: dict[tuple[str, str, str], dict[str, Any]] = {}
    for expected_sequence, path in enumerate(paths, 1):
        entry = validate_entry_file(path)
        if entry["record_sequence"] != expected_sequence:
            raise AcceptanceLedgerError(
                f"out-of-order or missing sequence expected={expected_sequence} actual={entry['record_sequence']}"
            )
        acceptance_id = entry["acceptance_id"]
        if acceptance_id in by_id:
            raise AcceptanceLedgerError(f"duplicate acceptance_id detected: {acceptance_id}")
        _validate_external_references(entry, root)
        key = (entry["subject"]["subject_type"], entry["subject"]["subject_id"], entry["scope"])
        predecessor_id = entry["supersedes_acceptance_id"]
        if predecessor_id is None:
            if key in current:
                raise AcceptanceLedgerError("ambiguous current state: later decision omitted required supersession")
        else:
            predecessor = by_id.get(predecessor_id)
            if predecessor is None:
                raise AcceptanceLedgerError("supersession predecessor missing or not earlier")
            predecessor_key = (
                predecessor["subject"]["subject_type"], predecessor["subject"]["subject_id"], predecessor["scope"]
            )
            if predecessor_key != key:
                raise AcceptanceLedgerError("supersession predecessor scope or subject mismatch")
            if key not in current or current[key]["acceptance_id"] != predecessor_id:
                raise AcceptanceLedgerError("supersession predecessor is not the current decision")
        current[key] = entry
        by_id[acceptance_id] = entry
        entries.append(entry)
    partials = [] if ignore_all_pending else [
        path for path in sorted(pending.iterdir()) if path != ignore_pending
    ]
    if partials:
        raise AcceptanceLedgerError("; ".join(f"partial_pending={path}" for path in partials))
    return entries


def validate_store(root: Path, *, quarantine_partials: bool = False, max_entries: int = MAX_QUERY_ENTRIES) -> tuple[int, int]:
    root = _ensure_isolated_root(root)
    if not root.exists():
        raise AcceptanceLedgerError(f"ledger root not found: {root}")
    entries_dir, pending, quarantine = (root / "entries", root / "pending", root / "quarantine")
    if any(path.is_symlink() or not path.is_dir() for path in (entries_dir, pending, quarantine)):
        raise AcceptanceLedgerError("ledger store is incomplete")
    partials = sorted(pending.iterdir())
    if quarantine_partials:
        entries = load_ledger(root, max_entries=max_entries, ignore_all_pending=True)
        for path in partials:
            if path.is_symlink() or not path.is_file():
                raise AcceptanceLedgerError(f"unsafe pending artifact: {path}")
            destination = quarantine / f"{path.name}.{uuid.uuid4().hex}.quarantined"
            os.replace(path, destination)
            fsync_directory(quarantine)
            fsync_directory(pending)
            print(f"quarantined={destination}")
        return len(entries), len(partials)
    entries = load_ledger(root, max_entries=max_entries)
    return len(entries), len(partials)


def _open_lock(root: Path) -> int:
    path = root / ".append.lock"
    flags = os.O_RDWR | os.O_CREAT | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags, 0o640)
    except OSError as exc:
        raise AcceptanceLedgerError(f"cannot safely open ledger lock: {path}: {exc}") from exc
    if not stat.S_ISREG(os.fstat(descriptor).st_mode):
        os.close(descriptor)
        raise AcceptanceLedgerError("ledger lock is not a regular file")
    return descriptor


def _acquire_lock(descriptor: int, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while True:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except BlockingIOError:
            if time.monotonic() >= deadline:
                raise AcceptanceLedgerError(f"ledger lock timeout after {timeout:.3f}s")
            time.sleep(min(0.01, max(0.001, timeout / 10)))


def append_entry(
    args: argparse.Namespace, *, on_write_progress: Callable[[int], None] | None = None
) -> tuple[str, dict[str, Any], Path]:
    _ensure_isolated_root(args.root)
    build_entry(args, 1)  # Validate every external input before creating the store.
    entries_dir, pending, _quarantine = prepare_store(args.root)
    descriptor = _open_lock(args.root)
    with os.fdopen(descriptor, "a+b") as lock_handle:
        os.fchmod(lock_handle.fileno(), 0o640)
        _acquire_lock(lock_handle.fileno(), args.lock_timeout)
        try:
            entries = load_ledger(args.root)
            existing = next((item for item in entries if item["acceptance_id"] == args.acceptance_id), None)
            if existing is not None:
                candidate = build_entry(args, existing["record_sequence"])
                if canonical_json(candidate) == canonical_json(existing):
                    return "EXISTS_IDENTICAL", existing, entries_dir / _entry_filename(existing)
                raise AcceptanceLedgerError(f"ACCEPTANCE_ID conflict refused: {args.acceptance_id}")
            candidate = build_entry(args, len(entries) + 1)
            key = (candidate["subject"]["subject_type"], candidate["subject"]["subject_id"], candidate["scope"])
            relevant = [
                item for item in entries
                if (item["subject"]["subject_type"], item["subject"]["subject_id"], item["scope"]) == key
            ]
            current = relevant[-1] if relevant else None
            if current is None and candidate["supersedes_acceptance_id"] is not None:
                raise AcceptanceLedgerError("supersession supplied but no current decision exists")
            if current is not None and candidate["supersedes_acceptance_id"] != current["acceptance_id"]:
                raise AcceptanceLedgerError(
                    f"current decision exists; exact supersedes_acceptance_id required: {current['acceptance_id']}"
                )
            data = canonical_json(candidate)
            target = entries_dir / _entry_filename(candidate)
            pending_path = pending / f".{candidate['acceptance_id']}.{uuid.uuid4().hex}.pending"
            write_descriptor = os.open(pending_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o640)
            linked = False
            remove_pending = True
            try:
                _write_all(write_descriptor, data, on_write_progress)
                os.fsync(write_descriptor)
            finally:
                os.close(write_descriptor)
            try:
                os.link(pending_path, target)
                linked = True
                fsync_directory(entries_dir)
                load_ledger(args.root, ignore_pending=pending_path)
            except FileExistsError as exc:
                raise AcceptanceLedgerError(f"ledger sequence collision refused: {candidate['record_sequence']}") from exc
            except Exception:
                if linked:
                    target.unlink(missing_ok=True)
                    fsync_directory(entries_dir)
                remove_pending = False
                raise
            finally:
                if remove_pending:
                    pending_path.unlink(missing_ok=True)
                    fsync_directory(pending)
            return "APPENDED", candidate, target
        finally:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)


def _normalize_query_subject(subject_type: str, subject_id: str) -> tuple[str, str]:
    run_id = subject_id if subject_type.strip().lower() == "run" else "run_20000101T000000000000Z_00000000000000000000000000000000"
    try:
        return normalize_subject(subject_type, subject_id, run_id)
    except RunRecordError as exc:
        raise AcceptanceLedgerError(str(exc)) from exc


def query_current(root: Path, subject_type: str, subject_id: str, scope: str, *, max_entries: int) -> dict[str, Any]:
    normalized_type, normalized_id = _normalize_query_subject(subject_type, subject_id)
    normalized_scope = _require_text(scope, "scope", maximum=256)
    entries = load_ledger(root, max_entries=max_entries, allow_missing=True)
    relevant = [
        item for item in entries
        if item["subject"] == {"subject_type": normalized_type, "subject_id": normalized_id}
        and item["scope"] == normalized_scope
    ]
    if not relevant:
        return {
            "status": "NO_DECISION", "is_current_accepted_state": False,
            "subject": {"subject_type": normalized_type, "subject_id": normalized_id},
            "scope": normalized_scope, "current": None, "production_acceptance_enabled": False,
        }
    current = relevant[-1]
    return {
        "status": current["decision"],
        "is_current_accepted_state": current["decision"] in {"ACCEPTED", "CONDITIONALLY_ACCEPTED"},
        "subject": current["subject"],
        "scope": current["scope"],
        "current": {
            "acceptance_id": current["acceptance_id"],
            "decision": current["decision"],
            "run_id": current["run_id"],
            "evidence": current["evidence"],
            "authority": current["authority"],
            "limitations": current["limitations"],
            "unresolved": current["unresolved"],
            "reason": current["reason"],
            "supersedes_acceptance_id": current["supersedes_acceptance_id"],
            "effective_at": current["effective_at"],
            "recorded_at": current["recorded_at"],
            "record_sequence": current["record_sequence"],
        },
        "production_acceptance_enabled": False,
    }


def query_history(root: Path, subject_type: str, subject_id: str, scope: str, *, max_entries: int, limit: int) -> dict[str, Any]:
    normalized_type, normalized_id = _normalize_query_subject(subject_type, subject_id)
    normalized_scope = _require_text(scope, "scope", maximum=256)
    if limit < 1 or limit > max_entries:
        raise AcceptanceLedgerError("history limit must be between 1 and max_entries")
    entries = load_ledger(root, max_entries=max_entries, allow_missing=True)
    relevant = [
        item for item in entries
        if item["subject"] == {"subject_type": normalized_type, "subject_id": normalized_id}
        and item["scope"] == normalized_scope
    ]
    if len(relevant) > limit:
        raise AcceptanceLedgerError(f"history exceeds requested bounded limit={limit}")
    return {
        "status": "HISTORY", "subject": {"subject_type": normalized_type, "subject_id": normalized_id},
        "scope": normalized_scope, "entry_count": len(relevant), "entries": relevant,
        "production_acceptance_enabled": False,
    }


def _emit(value: dict[str, Any], output_format: str) -> None:
    if output_format == "json":
        print(json.dumps(value, sort_keys=True))
        return
    for key, item in value.items():
        rendered = json.dumps(item, sort_keys=True) if isinstance(item, (dict, list)) else str(item)
        print(f"{key}={rendered}")


def _add_query_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--subject-type", choices=sorted(SUBJECT_TYPES), required=True)
    parser.add_argument("--subject-id", required=True)
    parser.add_argument("--scope", required=True)
    parser.add_argument("--max-entries", type=int, default=MAX_QUERY_ENTRIES)
    parser.add_argument("--format", choices=("json", "text"), default="json")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    append = subparsers.add_parser("append", help="Append one immutable isolated acceptance decision.")
    append.add_argument("--root", type=Path, required=True, help="Explicit isolated ledger root under /tmp.")
    append.add_argument("--run-record", type=Path, required=True)
    append.add_argument("--acceptance-id")
    append.add_argument("--decision", choices=sorted(DECISIONS), required=True)
    append.add_argument("--scope", required=True)
    append.add_argument("--actor-id", required=True)
    append.add_argument("--authority-file", type=Path, required=True)
    append.add_argument("--authority-type", choices=sorted(AUTHORITY_TYPES), required=True)
    append.add_argument("--authority-ref", required=True)
    append.add_argument("--authority-scope", required=True)
    append.add_argument("--authority-digest", required=True)
    append.add_argument("--evidence-manifest", type=Path, action="append", required=True)
    append.add_argument("--limitation", action="append", default=[])
    append.add_argument("--unresolved", action="append", default=[])
    append.add_argument("--reason")
    append.add_argument("--supersedes")
    append.add_argument("--effective-at")
    append.add_argument("--recorded-at")
    append.add_argument("--lock-timeout", type=float, default=5.0)
    append.add_argument("--format", choices=("json", "text"), default="json")
    validate = subparsers.add_parser("validate", help="Validate the complete isolated ledger and references.")
    validate.add_argument("--root", type=Path, required=True)
    validate.add_argument("--quarantine-partials", action="store_true")
    validate.add_argument("--max-entries", type=int, default=MAX_QUERY_ENTRIES)
    validate_entry_parser = subparsers.add_parser("validate-entry", help="Validate one canonical entry file.")
    validate_entry_parser.add_argument("entry", type=Path)
    current = subparsers.add_parser("current", help="Answer current accepted state in one bounded query.")
    _add_query_arguments(current)
    history = subparsers.add_parser("history", help="Return complete bounded history for one subject and scope.")
    _add_query_arguments(history)
    history.add_argument("--limit", type=int, default=1000)
    subparsers.add_parser("generate-id", help="Generate an ACCEPTANCE_ID without writing.")
    args = parser.parse_args(argv)
    if args.command == "append":
        if args.lock_timeout < 0 or args.lock_timeout > 300:
            parser.error("--lock-timeout must be between 0 and 300 seconds")
        args.acceptance_id = args.acceptance_id or generate_acceptance_id()
        if not ACCEPTANCE_ID_RE.fullmatch(args.acceptance_id):
            parser.error("--acceptance-id has invalid format")
        args.recorded_at = canonical_timestamp(args.recorded_at)
        args.effective_at = canonical_timestamp(args.effective_at or args.recorded_at)
    elif hasattr(args, "max_entries") and (args.max_entries < 1 or args.max_entries > 100_000):
        parser.error("--max-entries must be between 1 and 100000")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    if args.command == "generate-id":
        print(generate_acceptance_id())
        return 0
    if args.command == "append":
        result, entry, path = append_entry(args)
        _emit({
            "append": result, "acceptance_id": entry["acceptance_id"],
            "record_sequence": entry["record_sequence"], "decision": entry["decision"],
            "record": str(path), "production_acceptance_enabled": False,
        }, args.format)
        return 0
    if args.command == "validate":
        count, quarantined = validate_store(
            args.root, quarantine_partials=args.quarantine_partials, max_entries=args.max_entries
        )
        print(f"validate=PASS entry_count={count} quarantined_partials={quarantined} production_acceptance_enabled=no")
        return 0
    if args.command == "validate-entry":
        entry = validate_entry_file(args.entry)
        print(f"validate_entry=PASS acceptance_id={entry['acceptance_id']} schema_id={SCHEMA_ID}")
        return 0
    if args.command == "current":
        _emit(query_current(args.root, args.subject_type, args.subject_id, args.scope, max_entries=args.max_entries), args.format)
        return 0
    _emit(
        query_history(
            args.root, args.subject_type, args.subject_id, args.scope,
            max_entries=args.max_entries, limit=args.limit,
        ),
        args.format,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AcceptanceLedgerError, RunRecordError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
