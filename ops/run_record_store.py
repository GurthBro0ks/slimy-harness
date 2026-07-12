#!/usr/bin/env python3
"""Create and validate immutable Slimy Harness run-creation records."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import socket
import stat
import sys
import unicodedata
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


DEFAULT_ROOT = Path("/home/slimy/harness-logs/run-records")
SCHEMA_ID = "slimy-harness.run-created.v1"
SCHEMA_VERSION = 1
SUBJECT_TYPES = frozenset({"run", "feature", "policy", "waiver", "document", "deviation"})
RUN_ID_RE = re.compile(r"^run_[0-9]{8}T[0-9]{12}Z_[0-9a-f]{32}$")
SLUG_RE = re.compile(r"^[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?$")
SHA_RE = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
SUBJECT_ID_RE = re.compile(r"^[^\s\x00-\x1f\x7f]{1,256}$")
EXPECTED_KEYS = {
    "actor",
    "authority",
    "created_at",
    "machine",
    "payload_sha256",
    "project_id",
    "record_type",
    "repository",
    "run_id",
    "schema_id",
    "sequence",
    "subject_id",
    "subject_type",
    "v",
}


class RunRecordError(Exception):
    """A deterministic validation or safe-write failure."""


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n").encode(
        "utf-8"
    )


def payload_digest(record: dict[str, Any]) -> str:
    payload = dict(record)
    payload.pop("payload_sha256", None)
    return hashlib.sha256(canonical_json(payload)).hexdigest()


def generate_run_id(now: datetime | None = None) -> str:
    instant = now or datetime.now(timezone.utc)
    if instant.tzinfo is None:
        raise RunRecordError("RUN_ID time must be timezone-aware")
    stamp = instant.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    return f"run_{stamp}_{uuid.uuid4().hex}"


def canonical_timestamp(raw: str | None = None) -> str:
    if raw is None:
        instant = datetime.now(timezone.utc)
    else:
        if not raw.endswith("Z"):
            raise RunRecordError("created_at must be UTC and end in Z")
        try:
            instant = datetime.fromisoformat(raw[:-1] + "+00:00")
        except ValueError as exc:
            raise RunRecordError("created_at must be an RFC3339 timestamp") from exc
    if instant.utcoffset() != timezone.utc.utcoffset(instant):
        raise RunRecordError("created_at must be UTC")
    return instant.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def normalize_subject(subject_type: str, subject_id: str | None, run_id: str) -> tuple[str, str]:
    normalized_type = subject_type.strip().lower()
    if normalized_type not in SUBJECT_TYPES:
        raise RunRecordError(f"unknown subject_type refused: {subject_type!r}")
    raw_id = run_id if subject_id is None and normalized_type == "run" else subject_id
    if raw_id is None:
        raise RunRecordError("subject_id is required unless subject_type=run")
    normalized_id = unicodedata.normalize("NFC", raw_id.strip())
    if not SUBJECT_ID_RE.fullmatch(normalized_id):
        raise RunRecordError("subject_id must be 1-256 non-whitespace, non-control characters")
    if normalized_type == "run" and normalized_id != run_id:
        raise RunRecordError("subject_id must equal RUN_ID when subject_type=run")
    return normalized_type, normalized_id


def _require_string(value: Any, name: str, *, maximum: int = 512) -> str:
    if not isinstance(value, str) or not value or value != value.strip() or len(value) > maximum:
        raise RunRecordError(f"{name} must be a non-empty canonical string (max {maximum})")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise RunRecordError(f"{name} must not contain control characters")
    return value


def validate_record(record: Any) -> dict[str, Any]:
    if not isinstance(record, dict):
        raise RunRecordError("record must be a JSON object")
    keys = set(record)
    if keys != EXPECTED_KEYS:
        missing = sorted(EXPECTED_KEYS - keys)
        extra = sorted(keys - EXPECTED_KEYS)
        raise RunRecordError(f"schema fields mismatch missing={missing} extra={extra}")
    if record["v"] != SCHEMA_VERSION or record["schema_id"] != SCHEMA_ID:
        raise RunRecordError("unsupported schema identity")
    if record["record_type"] != "CREATED" or record["sequence"] != 1:
        raise RunRecordError("creation record must be record_type=CREATED and sequence=1")
    if not isinstance(record["run_id"], str) or not RUN_ID_RE.fullmatch(record["run_id"]):
        raise RunRecordError("invalid RUN_ID format")
    if record["subject_type"] not in SUBJECT_TYPES:
        raise RunRecordError("unknown subject_type")
    normalized_type, normalized_id = normalize_subject(
        record["subject_type"], record["subject_id"], record["run_id"]
    )
    if normalized_type != record["subject_type"] or normalized_id != record["subject_id"]:
        raise RunRecordError("subject identity is not canonical")
    if not isinstance(record["project_id"], str) or not SLUG_RE.fullmatch(record["project_id"]):
        raise RunRecordError("project_id must be a lowercase slug")
    repository = record["repository"]
    if not isinstance(repository, dict) or set(repository) != {"head_sha", "path", "remote_url"}:
        raise RunRecordError("repository must contain exactly path, remote_url, and head_sha")
    repo_path = _require_string(repository["path"], "repository.path", maximum=4096)
    if not Path(repo_path).is_absolute() or Path(repo_path) != Path(repo_path).resolve(strict=False):
        raise RunRecordError("repository.path must be an absolute normalized path")
    _require_string(repository["remote_url"], "repository.remote_url", maximum=2048)
    if not isinstance(repository["head_sha"], str) or not SHA_RE.fullmatch(repository["head_sha"]):
        raise RunRecordError("repository.head_sha must be a lowercase SHA-1 or SHA-256")
    machine = record["machine"]
    if not isinstance(machine, dict) or set(machine) != {"hostname", "id"}:
        raise RunRecordError("machine must contain exactly id and hostname")
    if machine["id"] not in {"nuc1", "nuc2"}:
        raise RunRecordError("machine.id must be nuc1 or nuc2")
    _require_string(machine["hostname"], "machine.hostname", maximum=253)
    _require_string(record["actor"], "actor", maximum=128)
    _require_string(record["authority"], "authority", maximum=1024)
    if canonical_timestamp(record["created_at"]) != record["created_at"]:
        raise RunRecordError("created_at is not canonical")
    if not isinstance(record["payload_sha256"], str) or not re.fullmatch(
        r"[0-9a-f]{64}", record["payload_sha256"]
    ):
        raise RunRecordError("payload_sha256 must be lowercase SHA-256")
    if payload_digest(record) != record["payload_sha256"]:
        raise RunRecordError("payload digest mismatch")
    return record


def _no_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise RunRecordError(f"duplicate JSON key refused: {key}")
        result[key] = value
    return result


def validate_record_bytes(data: bytes) -> dict[str, Any]:
    if not data.endswith(b"\n") or data.count(b"\n") != 1:
        raise RunRecordError("record must be exactly one newline-terminated JSONL entry")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RunRecordError("record is not valid UTF-8") from exc
    try:
        record = json.loads(text, object_pairs_hook=_no_duplicate_object_keys)
    except json.JSONDecodeError as exc:
        raise RunRecordError(f"record JSON parse failed at byte {exc.pos}") from exc
    validated = validate_record(record)
    if canonical_json(validated) != data:
        raise RunRecordError("record bytes are not canonical JSON")
    return validated


def validate_record_file(path: Path) -> dict[str, Any]:
    try:
        if not stat.S_ISREG(path.lstat().st_mode) or path.is_symlink():
            raise RunRecordError(f"record is not a regular non-symlink file: {path}")
        data = path.read_bytes()
    except FileNotFoundError as exc:
        raise RunRecordError(f"record not found: {path}") from exc
    record = validate_record_bytes(data)
    expected_name = f"{record['run_id']}.jsonl"
    if path.name != expected_name:
        raise RunRecordError(f"record filename mismatch expected={expected_name}")
    return record


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def prepare_store(root: Path) -> tuple[Path, Path, Path]:
    if root.exists() and (root.is_symlink() or not root.is_dir()):
        raise RunRecordError(f"store root must be a real directory: {root}")
    root_preexisted = root.exists()
    root.mkdir(parents=True, exist_ok=True)
    if not root_preexisted:
        fsync_directory(root.parent)
    records = root / "records"
    pending = root / "pending"
    quarantine = root / "quarantine"
    for directory in (records, pending, quarantine):
        preexisted = directory.exists()
        if directory.exists() and (directory.is_symlink() or not directory.is_dir()):
            raise RunRecordError(f"store component must be a real directory: {directory}")
        directory.mkdir(mode=0o750, exist_ok=True)
        if not preexisted:
            fsync_directory(root)
    fsync_directory(root)
    return records, pending, quarantine


def build_record(args: argparse.Namespace) -> dict[str, Any]:
    run_id = args.run_id or generate_run_id()
    if not RUN_ID_RE.fullmatch(run_id):
        raise RunRecordError("invalid RUN_ID format")
    subject_type, subject_id = normalize_subject(args.subject_type, args.subject_id, run_id)
    record: dict[str, Any] = {
        "v": SCHEMA_VERSION,
        "schema_id": SCHEMA_ID,
        "record_type": "CREATED",
        "sequence": 1,
        "run_id": run_id,
        "subject_type": subject_type,
        "subject_id": subject_id,
        "project_id": args.project_id,
        "repository": {
            "path": str(args.repository_path.resolve(strict=False)),
            "remote_url": args.repository_remote,
            "head_sha": args.repository_head,
        },
        "machine": {"id": args.machine, "hostname": args.hostname},
        "actor": args.actor,
        "authority": args.authority,
        "created_at": canonical_timestamp(args.created_at),
    }
    record["payload_sha256"] = payload_digest(record)
    return validate_record(record)


def _write_all(descriptor: int, data: bytes, on_progress: Callable[[int], None] | None = None) -> None:
    written = 0
    while written < len(data):
        count = os.write(descriptor, data[written:])
        if count <= 0:
            raise RunRecordError("short write while creating pending record")
        written += count
        if on_progress is not None:
            on_progress(written)


def create_record(
    root: Path, record: dict[str, Any], *, on_write_progress: Callable[[int], None] | None = None
) -> tuple[str, Path]:
    validated = validate_record(record)
    data = canonical_json(validated)
    records, pending, _quarantine = prepare_store(root)
    target = records / f"{validated['run_id']}.jsonl"
    lock_path = root / ".create.lock"
    lock_flags = os.O_RDWR | os.O_CREAT | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0)
    try:
        lock_descriptor = os.open(lock_path, lock_flags, 0o640)
    except OSError as exc:
        raise RunRecordError(f"cannot safely open store lock: {lock_path}: {exc}") from exc
    if not stat.S_ISREG(os.fstat(lock_descriptor).st_mode):
        os.close(lock_descriptor)
        raise RunRecordError(f"store lock is not a regular file: {lock_path}")
    with os.fdopen(lock_descriptor, "a+b") as lock_handle:
        os.fchmod(lock_handle.fileno(), 0o640)
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        try:
            if target.exists():
                validate_record_file(target)
                existing = target.read_bytes()
                if existing == data:
                    return "EXISTS_IDENTICAL", target
                raise RunRecordError(f"RUN_ID collision refused: {validated['run_id']}")
            pending_path = pending / f".{validated['run_id']}.{uuid.uuid4().hex}.pending"
            descriptor = os.open(pending_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o640)
            linked = False
            remove_pending = True
            try:
                _write_all(descriptor, data, on_write_progress)
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
            try:
                os.link(pending_path, target)
                linked = True
                fsync_directory(records)
                validate_record_file(target)
            except FileExistsError as exc:
                raise RunRecordError(f"RUN_ID collision refused: {validated['run_id']}") from exc
            except Exception:
                if linked:
                    target.unlink(missing_ok=True)
                    fsync_directory(records)
                remove_pending = False
                raise
            finally:
                if remove_pending:
                    pending_path.unlink(missing_ok=True)
                    fsync_directory(pending)
            return "CREATED", target
        finally:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)


def validate_store(root: Path, *, quarantine_partials: bool = False) -> tuple[int, int]:
    if not root.is_dir() or root.is_symlink():
        raise RunRecordError(f"store root not found or unsafe: {root}")
    records = root / "records"
    pending = root / "pending"
    quarantine = root / "quarantine"
    components = (records, pending, quarantine)
    if any(path.is_symlink() or not path.is_dir() for path in components):
        raise RunRecordError("store is incomplete: records, pending, and quarantine directories are required")
    errors: list[str] = []
    valid_count = 0
    for path in sorted(records.iterdir()):
        try:
            validate_record_file(path)
            valid_count += 1
        except RunRecordError as exc:
            errors.append(f"malformed_record={path}: {exc}")
    partials = sorted(pending.iterdir())
    if quarantine_partials:
        for path in partials:
            if path.is_symlink() or not path.is_file():
                errors.append(f"unsafe_pending={path}")
                continue
            destination = quarantine / f"{path.name}.{uuid.uuid4().hex}.quarantined"
            os.replace(path, destination)
            fsync_directory(quarantine)
            fsync_directory(pending)
            print(f"quarantined={destination}")
    elif partials:
        errors.extend(f"partial_pending={path}" for path in partials)
    if errors:
        raise RunRecordError("; ".join(errors))
    return valid_count, len(partials)


def add_create_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--run-id")
    parser.add_argument("--subject-type", required=True)
    parser.add_argument("--subject-id")
    parser.add_argument("--project-id", required=True)
    parser.add_argument("--repository-path", type=Path, required=True)
    parser.add_argument("--repository-remote", required=True)
    parser.add_argument("--repository-head", required=True)
    parser.add_argument("--machine", choices=("nuc1", "nuc2"), required=True)
    parser.add_argument("--hostname", default=socket.gethostname())
    parser.add_argument("--actor", required=True)
    parser.add_argument("--authority", required=True)
    parser.add_argument("--created-at")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    create = subparsers.add_parser("create", help="Create one immutable CREATED record.")
    add_create_arguments(create)
    validate = subparsers.add_parser("validate", help="Validate one canonical record file.")
    validate.add_argument("record", type=Path)
    validate_store_parser = subparsers.add_parser("validate-store", help="Validate a complete record store.")
    validate_store_parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    validate_store_parser.add_argument("--quarantine-partials", action="store_true")
    generate = subparsers.add_parser("generate-id", help="Generate a canonical RUN_ID without writing.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    if args.command == "generate-id":
        print(generate_run_id())
        return 0
    if args.command == "validate":
        record = validate_record_file(args.record)
        print(f"validate=PASS run_id={record['run_id']} schema_id={SCHEMA_ID}")
        return 0
    if args.command == "validate-store":
        count, partial_count = validate_store(args.root, quarantine_partials=args.quarantine_partials)
        print(f"validate_store=PASS record_count={count} quarantined_partials={partial_count}")
        return 0
    record = build_record(args)
    result, path = create_record(args.root, record)
    print(f"create={result} run_id={record['run_id']} record={path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RunRecordError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
