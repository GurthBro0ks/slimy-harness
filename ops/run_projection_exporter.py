#!/usr/bin/env python3
"""Isolated atomic writer for fixture-only run-projection.v1 snapshots.

RW2-A deliberately accepts only explicit, pre-existing real directories below
/tmp.  Production storage, source assembly, lifecycle wiring, ledger reads, and
notification behavior are outside this module's boundary.
"""

from __future__ import annotations

import argparse
import copy
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import time
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from jsonschema import Draft202012Validator, FormatChecker

import run_projection


PRODUCTION_ROOT = Path("/home/slimy/harness-logs/run-projections")
TMP_ROOT = Path("/tmp")
INDEX_FILENAME = "index.json"
LOCK_FILENAME = ".run-projection.lock"
INDEX_SCHEMA_VERSION = "run-projection-index.v1"
PRODUCER_ID = "run-projection-exporter@rw2a"
SOURCE_MACHINE = "nuc1"
MAX_INDEX_ENTRIES = 50
MAX_INPUT_BYTES = 2 * 1024 * 1024
DEFAULT_LOCK_TIMEOUT_SECONDS = 5.0
INDEX_SCHEMA_PATH = (
    Path(__file__).resolve().parent.parent / "schema" / "run-projection-index.v1.schema.json"
)
RUN_ID_RE = re.compile(r"^run_[0-9]{8}T[0-9]{12}Z_[0-9a-f]{32}$")
PENDING_MARKER = ".pending."
SENSITIVE_FILENAME_RE = re.compile(
    r"(?:^|[._-])(?:secret|token|password|private[_-]?key|api[_-]?key|"
    r"webhook|credential|cookie|session)(?:[._-]|$)",
    re.IGNORECASE,
)
FORBIDDEN_VALUE_PATTERNS = (
    re.compile(r"discord(?:app)?[.]com/api/webhooks/", re.IGNORECASE),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----", re.IGNORECASE),
    re.compile(r"\bAuthorization:\s*Bearer\s+\S+", re.IGNORECASE),
    re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{16,}", re.IGNORECASE),
    re.compile(
        r"\b[A-Z0-9_]*(?:SECRET|TOKEN|PASSWORD|PRIVATE_KEY|API_KEY|WEBHOOK)"
        r"[A-Z0-9_]*\s*=\s*[^\s,}\]]+",
        re.IGNORECASE,
    ),
    re.compile(r"\bAPPROVAL_(?:NONCE|STATEMENT)\s*=\s*[^\s,}\]]+", re.IGNORECASE),
)


class ProjectionExporterError(Exception):
    """A deterministic failure that never includes raw candidate content."""

    def __init__(
        self,
        error_class: str,
        message: str,
        *,
        state: str = "NO_OUTPUT_CHANGE",
    ) -> None:
        super().__init__(message)
        self.error_class = error_class
        self.safe_message = message
        self.state = state


@dataclass(frozen=True)
class WriteResult:
    status: str
    state: str
    run_id: str
    projection_path: str
    index_path: str
    index_entries: int


@dataclass(frozen=True)
class StoreValidationResult:
    valid: bool
    root: str
    projection_count: int
    index_entries: int
    pending_files: tuple[str, ...]
    errors: tuple[str, ...]


FailureHook = Callable[[str], None]


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"
    ).encode("utf-8")


def canonical_timestamp(now: datetime | None = None) -> str:
    instant = now or datetime.now(timezone.utc)
    if instant.tzinfo is None or instant.utcoffset() is None:
        raise ProjectionExporterError("invalid_writer_time", "writer time must be timezone-aware")
    return instant.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def self_digest(document: dict[str, Any]) -> str:
    payload = copy.deepcopy(document)
    integrity = payload.get("integrity")
    if not isinstance(integrity, dict) or "digest" not in integrity:
        raise ProjectionExporterError("integrity_missing", "integrity.digest is required")
    integrity["digest"] = None
    return hashlib.sha256(canonical_json(payload)).hexdigest()


def apply_self_digest(document: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(document)
    result["integrity"]["digest"] = None
    result["integrity"]["digest"] = self_digest(result)
    return result


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ProjectionExporterError("invalid_json", "duplicate JSON object key refused")
        result[key] = value
    return result


def _read_json_object(path: Path, label: str) -> tuple[dict[str, Any], bytes]:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as exc:
        raise ProjectionExporterError("missing_input", f"{label} does not exist") from exc
    if path.is_symlink() or not stat.S_ISREG(mode):
        raise ProjectionExporterError("unsafe_input", f"{label} must be a regular non-symlink file")
    if path.stat().st_size > MAX_INPUT_BYTES:
        raise ProjectionExporterError("input_too_large", f"{label} exceeds the 2 MiB limit")
    try:
        raw = path.read_bytes()
        document = json.loads(raw.decode("utf-8"), object_pairs_hook=_no_duplicate_keys)
    except ProjectionExporterError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProjectionExporterError("invalid_json", f"{label} is not valid UTF-8 JSON") from exc
    if not isinstance(document, dict):
        raise ProjectionExporterError("invalid_json", f"{label} must be a JSON object")
    return document, raw


def _safe_output_scan(document: dict[str, Any]) -> None:
    encoded = canonical_json(document).decode("utf-8")
    if any(pattern.search(encoded) for pattern in FORBIDDEN_VALUE_PATTERNS):
        raise ProjectionExporterError(
            "redaction_failure", "candidate contains a forbidden secret-like value"
        )
    artifacts = document.get("artifacts", {})
    displayed = artifacts.get("displayed_files", []) if isinstance(artifacts, dict) else []
    if any(isinstance(name, str) and SENSITIVE_FILENAME_RE.search(Path(name).name) for name in displayed):
        raise ProjectionExporterError(
            "redaction_failure", "candidate contains a sensitive artifact filename"
        )


def _validate_rw2a_boundary(document: dict[str, Any]) -> None:
    flags = document.get("flags")
    acceptance = document.get("acceptance")
    state = document.get("state")
    if not isinstance(flags, dict) or (
        flags.get("test_fixture_only") is not True
        or flags.get("production_acceptance_enabled") is not False
        or flags.get("production_storage_active") is not False
    ):
        raise ProjectionExporterError(
            "rw2a_boundary", "RW2-A requires fixture-only, production-disabled flags"
        )
    if not isinstance(acceptance, dict) or (
        acceptance.get("source") != "not_production_active"
        or acceptance.get("read_at") is not None
        or acceptance.get("acceptance_id") is not None
        or acceptance.get("scope") is not None
        or acceptance.get("superseded_by") is not None
    ):
        raise ProjectionExporterError(
            "rw2a_boundary", "RW2-A requires an honest empty acceptance block"
        )
    if not isinstance(state, dict) or state.get("acceptance") not in {"NO_DECISION", "UNKNOWN"}:
        raise ProjectionExporterError(
            "rw2a_boundary", "RW2-A cannot export an accepted-state assertion"
        )


def validate_projection_document(document: dict[str, Any], *, require_digest: bool) -> None:
    try:
        run_projection.validate_document(document)
    except run_projection.RunProjectionValidationError as exc:
        raise ProjectionExporterError(exc.error_class, exc.safe_message) from exc
    _validate_rw2a_boundary(document)
    _safe_output_scan(document)
    digest = document["integrity"]["digest"]
    if require_digest:
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ProjectionExporterError("integrity_mismatch", "projection digest is missing")
        if digest != self_digest(document):
            raise ProjectionExporterError("integrity_mismatch", "projection digest mismatch")
    elif digest is not None:
        raise ProjectionExporterError(
            "candidate_digest_present", "candidate integrity.digest must be null before export"
        )


def prepare_projection(document: dict[str, Any], *, now: datetime | None = None) -> dict[str, Any]:
    validate_projection_document(document, require_digest=False)
    result = copy.deepcopy(document)
    run_id = result["run"]["run_id"]
    result["generated_at"] = canonical_timestamp(now)
    result["generated_by"] = PRODUCER_ID
    result["source_machine"] = SOURCE_MACHINE
    result["links"]["workspace_path"] = f"/runs/{run_id}"
    result = apply_self_digest(result)
    validate_projection_document(result, require_digest=True)
    return result


def _load_index_schema() -> dict[str, Any]:
    document, _raw = _read_json_object(INDEX_SCHEMA_PATH, "index schema")
    try:
        Draft202012Validator.check_schema(document)
    except Exception as exc:
        raise ProjectionExporterError("schema_unavailable", "index schema is invalid") from exc
    return document


def _safe_schema_error(error: Any) -> str:
    path = "$" + "".join(
        f"[{part}]" if isinstance(part, int) else f".{part}" for part in error.absolute_path
    )
    return f"index schema rule {error.validator or 'schema'} failed at {path}"


def validate_index_document(document: dict[str, Any], *, require_digest: bool = True) -> None:
    if document.get("schema_version") != INDEX_SCHEMA_VERSION:
        raise ProjectionExporterError(
            "unsupported_index_schema", "unsupported index schema_version refused"
        )
    validator = Draft202012Validator(_load_index_schema(), format_checker=FormatChecker())
    errors = sorted(
        validator.iter_errors(document), key=lambda item: (list(item.absolute_path), item.message)
    )
    if errors:
        raise ProjectionExporterError("index_schema_mismatch", _safe_schema_error(errors[0]))
    if document["generated_by"] != PRODUCER_ID or document["source_machine"] != SOURCE_MACHINE:
        raise ProjectionExporterError("index_provenance", "index producer provenance mismatch")
    runs = document["runs"]
    identities = [entry["run_id"] for entry in runs]
    if len(identities) != len(set(identities)):
        raise ProjectionExporterError("index_duplicate", "index contains duplicate RUN_ID entries")
    expected = sorted(runs, key=lambda entry: (entry["run_created_at"], entry["run_id"]), reverse=True)
    if runs != expected:
        raise ProjectionExporterError("index_order", "index entries are not canonically ordered")
    for entry in runs:
        if entry["workspace_path"] != f"/runs/{entry['run_id']}":
            raise ProjectionExporterError("index_identity", "index workspace_path mismatch")
    digest = document["integrity"]["digest"]
    if require_digest:
        if not isinstance(digest, str) or digest != self_digest(document):
            raise ProjectionExporterError("integrity_mismatch", "index digest mismatch")


def _index_entry(projection: dict[str, Any]) -> dict[str, Any]:
    state = projection["state"]
    return {
        "run_id": projection["run"]["run_id"],
        "subject_type": projection["run"]["subject_type"],
        "subject_id": projection["run"]["subject_id"],
        "project_id": projection["run"]["project_id"],
        "phase": projection["run"]["phase"],
        "run_created_at": projection["run"]["created_at"],
        "projection_generated_at": projection["generated_at"],
        "execution": state["execution"],
        "evidence": state["evidence"],
        "review": state["review"],
        "acceptance": state["acceptance"],
        "owner_action": state["owner_action"],
        "notification": state["notification"],
        "test_fixture_only": projection["flags"]["test_fixture_only"],
        "production_acceptance_enabled": projection["flags"]["production_acceptance_enabled"],
        "report_url": projection["links"]["report_url"],
        "workspace_path": projection["links"]["workspace_path"],
    }


def build_index(
    current: dict[str, Any] | None,
    projection: dict[str, Any],
) -> dict[str, Any]:
    entries = {} if current is None else {entry["run_id"]: copy.deepcopy(entry) for entry in current["runs"]}
    new_entry = _index_entry(projection)
    entries[new_entry["run_id"]] = new_entry
    ordered = sorted(
        entries.values(), key=lambda entry: (entry["run_created_at"], entry["run_id"]), reverse=True
    )[:MAX_INDEX_ENTRIES]
    document = {
        "schema_version": INDEX_SCHEMA_VERSION,
        "generated_at": projection["generated_at"],
        "generated_by": PRODUCER_ID,
        "source_machine": SOURCE_MACHINE,
        "runs": ordered,
        "integrity": {"digest": None},
    }
    result = apply_self_digest(document)
    validate_index_document(result)
    return result


def ensure_isolated_root(root: Path) -> Path:
    if root == PRODUCTION_ROOT:
        raise ProjectionExporterError("production_root_refused", "production projection root refused")
    if not root.is_absolute():
        raise ProjectionExporterError("unsafe_root", "root must be absolute")
    try:
        resolved = root.resolve(strict=True)
        mode = root.lstat().st_mode
    except FileNotFoundError as exc:
        raise ProjectionExporterError("missing_root", "root must already exist") from exc
    except OSError as exc:
        raise ProjectionExporterError("unsafe_root", "root could not be resolved safely") from exc
    if root != resolved or root.is_symlink() or not stat.S_ISDIR(mode):
        raise ProjectionExporterError("unsafe_root", "root must be a normalized real directory")
    if root == TMP_ROOT or TMP_ROOT not in root.parents:
        raise ProjectionExporterError("non_tmp_root_refused", "RW2-A root must be beneath /tmp")
    return root


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _open_lock(root: Path, timeout_seconds: float) -> Any:
    if timeout_seconds < 0 or timeout_seconds > 60:
        raise ProjectionExporterError("invalid_lock_timeout", "lock timeout must be between 0 and 60 seconds")
    path = root / LOCK_FILENAME
    flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags, 0o640)
    except OSError as exc:
        raise ProjectionExporterError("unsafe_lock", "lock file could not be opened safely") from exc
    if not stat.S_ISREG(os.fstat(descriptor).st_mode):
        os.close(descriptor)
        raise ProjectionExporterError("unsafe_lock", "lock must be a regular file")
    os.fchmod(descriptor, 0o640)
    handle = os.fdopen(descriptor, "a+b")
    deadline = time.monotonic() + timeout_seconds
    while True:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle
        except BlockingIOError:
            if time.monotonic() >= deadline:
                handle.close()
                raise ProjectionExporterError("lock_timeout", "projection root lock timed out")
            time.sleep(min(0.01, max(0.0, deadline - time.monotonic())))


def _revalidate_locked_root(
    root: Path,
    expected_root_identity: tuple[int, int],
    lock_handle: Any,
) -> None:
    ensure_isolated_root(root)
    try:
        root_status = os.stat(root, follow_symlinks=False)
        lock_status = os.stat(root / LOCK_FILENAME, follow_symlinks=False)
        handle_status = os.fstat(lock_handle.fileno())
    except OSError as exc:
        raise ProjectionExporterError(
            "unsafe_root", "root or lock changed while acquiring the lock"
        ) from exc
    if (root_status.st_dev, root_status.st_ino) != expected_root_identity:
        raise ProjectionExporterError(
            "unsafe_root", "root changed while acquiring the lock"
        )
    if not stat.S_ISREG(lock_status.st_mode) or (
        lock_status.st_dev,
        lock_status.st_ino,
    ) != (handle_status.st_dev, handle_status.st_ino):
        raise ProjectionExporterError(
            "unsafe_lock", "lock changed while acquiring the lock"
        )


def _validate_existing_target(path: Path) -> dict[str, Any] | None:
    if not path.exists() and not path.is_symlink():
        return None
    document, raw = _read_json_object(path, "existing projection")
    validate_projection_document(document, require_digest=True)
    if path.name != f"{document['run']['run_id']}.json":
        raise ProjectionExporterError("target_identity", "existing projection filename mismatch")
    if raw != canonical_json(document):
        raise ProjectionExporterError("noncanonical_output", "existing projection is not canonical JSON")
    return document


def _load_existing_index(root: Path) -> dict[str, Any] | None:
    path = root / INDEX_FILENAME
    detail_json = [candidate for candidate in root.iterdir() if candidate.name.endswith(".json") and candidate.name != INDEX_FILENAME]
    if not path.exists() and not path.is_symlink():
        if detail_json:
            raise ProjectionExporterError(
                "index_missing", "non-empty projection root requires a valid index"
            )
        return None
    document, raw = _read_json_object(path, "existing index")
    validate_index_document(document)
    if raw != canonical_json(document):
        raise ProjectionExporterError("noncanonical_output", "existing index is not canonical JSON")
    return document


def _write_all(descriptor: int, data: bytes) -> None:
    written = 0
    while written < len(data):
        count = os.write(descriptor, data[written:])
        if count <= 0:
            raise ProjectionExporterError("short_write", "pending file write did not complete")
        written += count


def _write_pending(path: Path, data: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o640)
    try:
        os.fchmod(descriptor, 0o640)
        _write_all(descriptor, data)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _validate_projection_bytes(data: bytes) -> dict[str, Any]:
    try:
        document = json.loads(data.decode("utf-8"), object_pairs_hook=_no_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProjectionExporterError("invalid_json", "projection bytes are invalid") from exc
    if not isinstance(document, dict) or data != canonical_json(document):
        raise ProjectionExporterError("noncanonical_output", "projection bytes are not canonical")
    validate_projection_document(document, require_digest=True)
    return document


def _validate_index_bytes(data: bytes) -> dict[str, Any]:
    try:
        document = json.loads(data.decode("utf-8"), object_pairs_hook=_no_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProjectionExporterError("invalid_json", "index bytes are invalid") from exc
    if not isinstance(document, dict) or data != canonical_json(document):
        raise ProjectionExporterError("noncanonical_output", "index bytes are not canonical")
    validate_index_document(document)
    return document


def _call_hook(hook: FailureHook | None, stage: str) -> None:
    if hook is not None:
        hook(stage)


def write_projection(
    root: Path,
    input_path: Path,
    *,
    now: datetime | None = None,
    lock_timeout_seconds: float = DEFAULT_LOCK_TIMEOUT_SECONDS,
    failure_hook: FailureHook | None = None,
) -> WriteResult:
    safe_root = ensure_isolated_root(root)
    root_status = os.stat(safe_root, follow_symlinks=False)
    root_identity = (root_status.st_dev, root_status.st_ino)
    try:
        resolved_input = input_path.resolve(strict=True)
    except OSError as exc:
        raise ProjectionExporterError("missing_input", "candidate does not exist") from exc
    if safe_root == resolved_input.parent or safe_root in resolved_input.parents:
        raise ProjectionExporterError("unsafe_input", "candidate must be outside the projection root")
    candidate, _raw = _read_json_object(input_path, "candidate")
    projection = prepare_projection(candidate, now=now)
    run_id = projection["run"]["run_id"]
    target = safe_root / f"{run_id}.json"
    index_path = safe_root / INDEX_FILENAME
    lock_handle = _open_lock(safe_root, lock_timeout_seconds)
    try:
        _revalidate_locked_root(safe_root, root_identity, lock_handle)
        target_existed = _validate_existing_target(target) is not None
        current_index = _load_existing_index(safe_root)
        index = build_index(current_index, projection)
        run_bytes = canonical_json(projection)
        index_bytes = canonical_json(index)
        run_pending = safe_root / f".{target.name}{PENDING_MARKER}{os.getpid()}.{uuid.uuid4().hex}"
        index_pending = safe_root / f".{INDEX_FILENAME}{PENDING_MARKER}{os.getpid()}.{uuid.uuid4().hex}"
        run_replaced = False
        index_replaced = False
        try:
            _write_pending(run_pending, run_bytes)
            _validate_projection_bytes(run_pending.read_bytes())
            _call_hook(failure_hook, "after_run_pending_validation")
            _write_pending(index_pending, index_bytes)
            _validate_index_bytes(index_pending.read_bytes())
            _call_hook(failure_hook, "after_index_pending_validation")
            _call_hook(failure_hook, "before_run_replace")
            os.replace(run_pending, target)
            run_replaced = True
            fsync_directory(safe_root)
            _validate_existing_target(target)
            _call_hook(failure_hook, "after_run_replace")
            _call_hook(failure_hook, "before_index_replace")
            os.replace(index_pending, index_path)
            index_replaced = True
            fsync_directory(safe_root)
            _load_existing_index(safe_root)
            _call_hook(failure_hook, "after_index_replace")
        except Exception as exc:
            if not run_replaced:
                run_pending.unlink(missing_ok=True)
            if not index_replaced:
                index_pending.unlink(missing_ok=True)
            if run_replaced and not index_replaced:
                raise ProjectionExporterError(
                    "partial_commit",
                    "run projection is valid but index remains last-known-good; retry is required",
                    state="RUN_VALID_INDEX_LKG",
                ) from exc
            if run_replaced and index_replaced:
                raise ProjectionExporterError(
                    "post_commit_failure",
                    "run and index were replaced but final durability or validation failed; retry is required",
                    state="RUN_AND_INDEX_REPLACED_VALIDATION_UNKNOWN",
                ) from exc
            if isinstance(exc, ProjectionExporterError):
                raise
            raise ProjectionExporterError("write_failure", "atomic projection write failed") from exc
        return WriteResult(
            status="UPDATED" if target_existed else "CREATED",
            state="RUN_AND_INDEX_VALID",
            run_id=run_id,
            projection_path=str(target),
            index_path=str(index_path),
            index_entries=len(index["runs"]),
        )
    finally:
        try:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        finally:
            lock_handle.close()


def _projection_from_path(path: Path) -> dict[str, Any]:
    document, raw = _read_json_object(path, "projection")
    validate_projection_document(document, require_digest=True)
    if path.name != f"{document['run']['run_id']}.json":
        raise ProjectionExporterError("target_identity", "projection filename mismatch")
    if raw != canonical_json(document):
        raise ProjectionExporterError("noncanonical_output", "projection is not canonical JSON")
    return document


def validate_store(root: Path) -> StoreValidationResult:
    safe_root = ensure_isolated_root(root)
    errors: list[str] = []
    pending: list[str] = []
    projections: dict[str, dict[str, Any]] = {}
    index: dict[str, Any] | None = None
    allowed_non_json = {LOCK_FILENAME}
    for path in sorted(safe_root.iterdir(), key=lambda item: item.name):
        if PENDING_MARKER in path.name:
            pending.append(path.name)
            continue
        if path.name in allowed_non_json:
            try:
                if path.is_symlink() or not stat.S_ISREG(path.lstat().st_mode):
                    errors.append("unsafe lock file")
            except OSError:
                errors.append("unsafe lock file")
            continue
        if path.name == INDEX_FILENAME:
            try:
                index, raw = _read_json_object(path, "index")
                validate_index_document(index)
                if raw != canonical_json(index):
                    raise ProjectionExporterError("noncanonical_output", "index is not canonical")
            except ProjectionExporterError as exc:
                errors.append(f"index: {exc.safe_message}")
            continue
        if path.name.endswith(".json"):
            if not RUN_ID_RE.fullmatch(path.name[:-5]):
                errors.append(f"unexpected JSON file: {path.name}")
                continue
            try:
                projection = _projection_from_path(path)
                projections[projection["run"]["run_id"]] = projection
            except ProjectionExporterError as exc:
                errors.append(f"projection {path.name}: {exc.safe_message}")
            continue
        errors.append(f"unexpected root entry: {path.name}")
    if pending:
        errors.append("pending crash leftovers are present")
    if projections and index is None:
        errors.append("index is missing for a non-empty projection root")
    if index is not None:
        for entry in index["runs"]:
            projection = projections.get(entry["run_id"])
            if projection is None:
                errors.append(f"index detail missing: {entry['run_id']}")
            elif entry != _index_entry(projection):
                errors.append(f"index detail mismatch: {entry['run_id']}")
    return StoreValidationResult(
        valid=not errors,
        root=str(safe_root),
        projection_count=len(projections),
        index_entries=0 if index is None else len(index["runs"]),
        pending_files=tuple(pending),
        errors=tuple(errors),
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Write and validate isolated fixture-only run projections beneath /tmp."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    write = subparsers.add_parser("write", help="Atomically write one explicit candidate and index.")
    write.add_argument("--root", required=True, type=Path)
    write.add_argument("--input", required=True, type=Path)
    write.add_argument(
        "--lock-timeout-seconds",
        type=float,
        default=DEFAULT_LOCK_TIMEOUT_SECONDS,
        help="Bounded local lock wait, 0..60 seconds (default: 5).",
    )
    validate = subparsers.add_parser(
        "validate-store", help="Report store, index, digest, and crash-leftover validity."
    )
    validate.add_argument("--root", required=True, type=Path)
    validate.add_argument("--format", choices=("text", "json"), default="text")
    return parser


def _render_validation(result: StoreValidationResult) -> str:
    lines = [
        f"Run projection store validation: {'PASS' if result.valid else 'FAIL'}",
        f"Root: {result.root}",
        f"Projections: {result.projection_count}",
        f"Index entries: {result.index_entries}",
        f"Pending files: {len(result.pending_files)}",
    ]
    lines.extend(f"ERROR {error}" for error in result.errors)
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "write":
            result = write_projection(
                args.root,
                args.input,
                lock_timeout_seconds=args.lock_timeout_seconds,
            )
            print(json.dumps(asdict(result), ensure_ascii=False, sort_keys=True))
            return 0
        result = validate_store(args.root)
        if args.format == "json":
            print(json.dumps(asdict(result), ensure_ascii=False, sort_keys=True))
        else:
            print(_render_validation(result))
        return 0 if result.valid else 1
    except ProjectionExporterError as exc:
        print(
            f"ERROR [{exc.error_class}] state={exc.state} {exc.safe_message}",
            file=sys.stderr,
        )
        return 75 if exc.state == "RUN_VALID_INDEX_LKG" else 1


if __name__ == "__main__":
    sys.exit(main())
