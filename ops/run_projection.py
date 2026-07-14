#!/usr/bin/env python3
"""Read-only validation for run-projection.v1 JSON files."""

from __future__ import annotations

import argparse
import json
import stat
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

from jsonschema import Draft202012Validator, FormatChecker


SCHEMA_VERSION = "run-projection.v1"
RESULT_SCHEMA_VERSION = "run-projection-validator.v1"
DEFAULT_SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schema" / "run-projection.v1.schema.json"
MAX_FILE_BYTES = 2 * 1024 * 1024
MAX_DIRECTORY_FILES = 1000


class RunProjectionValidationError(Exception):
    """A safe, deterministic validation failure without raw input content."""

    def __init__(self, error_class: str, message: str):
        super().__init__(message)
        self.error_class = error_class
        self.safe_message = message


@dataclass(frozen=True)
class FileValidationResult:
    path: str
    valid: bool
    error_class: str | None
    errors: tuple[str, ...]


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise RunProjectionValidationError("invalid_json", "duplicate JSON object key refused")
        result[key] = value
    return result


def _load_json_file(path: Path) -> Any:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as exc:
        raise RunProjectionValidationError("missing_path", "path does not exist") from exc
    if path.is_symlink() or not stat.S_ISREG(mode):
        raise RunProjectionValidationError("invalid_path", "path must be a regular non-symlink file")
    if path.stat().st_size > MAX_FILE_BYTES:
        raise RunProjectionValidationError("file_too_large", "file exceeds the 2 MiB validation limit")
    try:
        raw = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise RunProjectionValidationError("invalid_json", "file is not valid UTF-8 JSON") from exc
    except OSError as exc:
        raise RunProjectionValidationError("read_error", "file could not be read safely") from exc
    try:
        return json.loads(raw, object_pairs_hook=_no_duplicate_keys)
    except RunProjectionValidationError:
        raise
    except json.JSONDecodeError as exc:
        raise RunProjectionValidationError(
            "invalid_json", f"JSON parse failed at line {exc.lineno}, column {exc.colno}"
        ) from exc


def _load_schema(schema_path: Path = DEFAULT_SCHEMA_PATH) -> dict[str, Any]:
    schema = _load_json_file(schema_path)
    if not isinstance(schema, dict):
        raise RunProjectionValidationError("schema_unavailable", "validator schema is not a JSON object")
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as exc:
        raise RunProjectionValidationError("schema_unavailable", "validator schema is invalid") from exc
    return schema


def _json_path(parts: Iterable[Any]) -> str:
    path = "$"
    for part in parts:
        path += f"[{part}]" if isinstance(part, int) else f".{part}"
    return path


def _safe_schema_error(error: Any) -> str:
    keyword = str(error.validator or "schema")
    return f"schema rule {keyword} failed at {_json_path(error.absolute_path)}"


def _validate_semantics(document: dict[str, Any]) -> None:
    run_id = document["run"]["run_id"]
    if document["links"]["workspace_path"] != f"/runs/{run_id}":
        raise RunProjectionValidationError(
            "schema_mismatch", "workspace_path does not match the canonical run_id"
        )
    continuation = document["continuation"]
    if continuation is not None:
        if continuation["run_id"] != run_id:
            raise RunProjectionValidationError(
                "schema_mismatch", "continuation run_id does not match the canonical run_id"
            )
        expected_url = f"https://habitat.slimyai.xyz/runs/{run_id}"
        if continuation["workspace_url"] != expected_url:
            raise RunProjectionValidationError(
                "schema_mismatch", "continuation workspace_url does not match the canonical run_id"
            )


def validate_document(document: Any, schema: dict[str, Any] | None = None) -> None:
    if not isinstance(document, dict):
        raise RunProjectionValidationError("schema_mismatch", "projection must be a JSON object")
    version = document.get("schema_version")
    if version is not None and version != SCHEMA_VERSION:
        raise RunProjectionValidationError(
            "unsupported_schema_version", "unsupported schema_version refused"
        )
    validator = Draft202012Validator(schema or _load_schema(), format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(document), key=lambda item: (list(item.absolute_path), item.message))
    if errors:
        safe_errors = tuple(_safe_schema_error(error) for error in errors[:20])
        raise RunProjectionValidationError("schema_mismatch", "; ".join(safe_errors))
    _validate_semantics(document)


def validate_file(path: Path, schema: dict[str, Any] | None = None) -> FileValidationResult:
    try:
        document = _load_json_file(path)
        validate_document(document, schema)
    except RunProjectionValidationError as exc:
        return FileValidationResult(
            path=str(path), valid=False, error_class=exc.error_class, errors=(exc.safe_message,)
        )
    return FileValidationResult(path=str(path), valid=True, error_class=None, errors=())


def _directory_files(path: Path) -> list[Path]:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as exc:
        raise RunProjectionValidationError("missing_path", "path does not exist") from exc
    if path.is_symlink() or not stat.S_ISDIR(mode):
        raise RunProjectionValidationError("invalid_path", "path must be a real directory")
    files = sorted(
        (candidate for candidate in path.iterdir() if candidate.name.endswith(".json")),
        key=lambda candidate: candidate.name,
    )
    if len(files) > MAX_DIRECTORY_FILES:
        raise RunProjectionValidationError(
            "directory_too_large", f"directory exceeds the {MAX_DIRECTORY_FILES}-file validation limit"
        )
    if not files:
        raise RunProjectionValidationError("no_matching_files", "directory contains no matching JSON files")
    return files


def validate_target(path: Path, schema_path: Path = DEFAULT_SCHEMA_PATH) -> dict[str, Any]:
    try:
        schema = _load_schema(schema_path)
        if path.is_dir() and not path.is_symlink():
            paths = _directory_files(path)
        else:
            paths = [path]
        results = [validate_file(candidate, schema) for candidate in paths]
        target_error = None
    except RunProjectionValidationError as exc:
        results = []
        target_error = {"error_class": exc.error_class, "message": exc.safe_message}

    valid_count = sum(result.valid for result in results)
    invalid_count = len(results) - valid_count + (1 if target_error else 0)
    return {
        "schema_version": RESULT_SCHEMA_VERSION,
        "target": str(path),
        "valid": invalid_count == 0,
        "files": [asdict(result) for result in results],
        "target_error": target_error,
        "summary": {
            "total": len(results),
            "valid": valid_count,
            "invalid": invalid_count,
        },
    }


def _render_text(result: dict[str, Any]) -> str:
    lines = [
        f"Run projection validation: {'PASS' if result['valid'] else 'FAIL'}",
        f"Target: {result['target']}",
    ]
    for item in result["files"]:
        if item["valid"]:
            lines.append(f"PASS {item['path']}")
        else:
            lines.append(f"FAIL {item['path']} [{item['error_class']}] {item['errors'][0]}")
    if result["target_error"]:
        target_error = result["target_error"]
        lines.append(f"FAIL [{target_error['error_class']}] {target_error['message']}")
    summary = result["summary"]
    lines.append(
        f"Summary: total={summary['total']} valid={summary['valid']} invalid={summary['invalid']}"
    )
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Read and validate one run-projection.v1 JSON file or every .json file "
            "directly inside one directory. Input files are never modified."
        )
    )
    parser.add_argument("path", type=Path, help="Projection JSON file or directory of JSON files")
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format (default: text); json includes a deterministic machine-readable summary",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    result = validate_target(args.path)
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    else:
        print(_render_text(result))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    sys.exit(main())
