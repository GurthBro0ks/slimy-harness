#!/usr/bin/env python3
"""Validate and append feature_list.json entries with a file lock."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any


DEFAULT_FEATURE_LIST = Path("/home/slimy/feature_list.json")


class FeatureListError(Exception):
    """User-facing validation or write error."""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise FeatureListError(f"feature list not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise FeatureListError(f"feature list JSON parse failed: {exc}") from exc


def feature_items(data: Any) -> list[Any]:
    if isinstance(data, list):
        return data
    if isinstance(data, dict) and isinstance(data.get("features"), list):
        return data["features"]
    raise FeatureListError('feature list must be a JSON list or an object with a "features" list')


def feature_id(item: Any) -> str | None:
    if not isinstance(item, dict) or "id" not in item:
        return None
    raw_id = item.get("id")
    if raw_id is None:
        return ""
    return str(raw_id)


def duplicate_ids(items: list[Any]) -> list[str]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for item in items:
        item_id = feature_id(item)
        if item_id is None:
            continue
        if item_id in seen:
            duplicates.add(item_id)
        seen.add(item_id)
    return sorted(duplicates)


def validate_no_duplicate_ids(data: Any) -> list[Any]:
    items = feature_items(data)
    duplicates = duplicate_ids(items)
    if duplicates:
        raise FeatureListError(f"duplicate_ids={json.dumps(duplicates, sort_keys=True)}")
    return items


def load_entry(path: Path) -> dict[str, Any]:
    try:
        entry = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise FeatureListError(f"entry JSON not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise FeatureListError(f"entry JSON parse failed: {exc}") from exc
    if not isinstance(entry, dict):
        raise FeatureListError("entry JSON must be an object")
    entry_id = feature_id(entry)
    if not entry_id:
        raise FeatureListError("entry JSON must contain a non-empty id")
    return entry


def dumps_feature_list(data: Any) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def fsync_directory(path: Path) -> None:
    try:
        dir_fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)


def atomic_replace_json(path: Path, data: Any) -> None:
    parent = path.parent
    parent.mkdir(parents=False, exist_ok=True)
    original_stat = path.stat()
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(parent))
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(dumps_feature_list(data))
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_path, stat.S_IMODE(original_stat.st_mode))
        os.replace(temp_path, path)
        fsync_directory(parent)
    except Exception:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass
        raise


def default_lock_file(feature_list: Path) -> Path:
    return feature_list.with_name(f"{feature_list.name}.lock")


def validate_only(feature_list: Path) -> int:
    data = load_json(feature_list)
    items = validate_no_duplicate_ids(data)
    print(f"validate=PASS item_count={len(items)} duplicate_ids=[]")
    return 0


def append_entry(feature_list: Path, entry_path: Path, *, dry_run: bool) -> int:
    entry = load_entry(entry_path)
    data = load_json(feature_list)
    items = validate_no_duplicate_ids(data)
    entry_id = str(entry["id"])
    existing_ids = {feature_id(item) for item in items}
    if entry_id in existing_ids:
        raise FeatureListError(f"duplicate id refused: {entry_id}")
    items.append(entry)
    validate_no_duplicate_ids(data)
    if dry_run:
        print(f"dry_run=PASS would_append_id={entry_id} item_count_after={len(items)}")
        return 0
    atomic_replace_json(feature_list, data)
    written = load_json(feature_list)
    written_items = validate_no_duplicate_ids(written)
    print(f"append=PASS appended_id={entry_id} item_count={len(written_items)}")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate or append feature_list.json safely.")
    parser.add_argument("--feature-list", type=Path, default=DEFAULT_FEATURE_LIST)
    parser.add_argument("--entry-json", type=Path)
    parser.add_argument("--lock-file", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    feature_list = args.feature_list
    lock_file = args.lock_file or default_lock_file(feature_list)
    if not args.validate_only and args.entry_json is None:
        raise FeatureListError("--entry-json is required unless --validate-only is set")
    lock_file.parent.mkdir(parents=True, exist_ok=True)
    with lock_file.open("a+", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        try:
            if args.validate_only:
                return validate_only(feature_list)
            return append_entry(feature_list, args.entry_json, dry_run=args.dry_run)
        finally:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FeatureListError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
