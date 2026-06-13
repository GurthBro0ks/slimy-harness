#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA_PATH="$REPO_ROOT/schema/harness-session-index.schema.json"
DEFAULT_SESSIONS_DIR="/home/slimy/slimy-kb/raw/sessions"
DEFAULT_OUTPUT="/home/slimy/slimy-kb/raw/sessions/harness-session-index.json"

usage() {
  cat <<USAGE
Usage: export-session-index.sh [--dry-run] [--output PATH] [--sessions-dir PATH] [--schema] [--help]

Build a safe, read-only harness session metadata index from JSON reports.

Options:
  --dry-run           Write index JSON to stdout only. This is also the default
                      behavior when --output is omitted.
  --output PATH       Write index JSON to PATH after validation.
  --sessions-dir PATH Read session report JSON files from PATH.
                      Default: $DEFAULT_SESSIONS_DIR
  --schema            Print the JSON schema path and exit.
  --help              Show this help.

Default output path, when an operator explicitly passes --output:
  $DEFAULT_OUTPUT

The exporter ignores non-JSON files, skips generated index files, does not read
environment files, and emits only allowlisted metadata fields. Raw report bodies,
raw logs, raw diffs, and secret-bearing values are not included.
USAGE
}

dry_run=0
output_path=""
sessions_dir="$DEFAULT_SESSIONS_DIR"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --output)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --output requires a path" >&2
        exit 64
      fi
      output_path="$2"
      shift 2
      ;;
    --sessions-dir)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --sessions-dir requires a path" >&2
        exit 64
      fi
      sessions_dir="$2"
      shift 2
      ;;
    --schema)
      printf '%s\n' "$SCHEMA_PATH"
      exit 0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [ ! -d "$sessions_dir" ]; then
  echo "ERROR: sessions directory not found: $sessions_dir" >&2
  exit 66
fi

if [ ! -f "$SCHEMA_PATH" ]; then
  echo "ERROR: schema not found: $SCHEMA_PATH" >&2
  exit 66
fi

if [ -n "$output_path" ] && [ "$dry_run" -eq 1 ]; then
  echo "ERROR: --dry-run cannot be combined with --output" >&2
  exit 64
fi

export HARNESS_SESSION_INDEX_SCHEMA="$SCHEMA_PATH"
export HARNESS_SESSION_INDEX_SESSIONS_DIR="$sessions_dir"
export HARNESS_SESSION_INDEX_OUTPUT="$output_path"

python3 <<'PY'
import datetime as _dt
import json
import os
import re
import socket
import sys
import tempfile
from pathlib import Path

schema_path = Path(os.environ["HARNESS_SESSION_INDEX_SCHEMA"])
sessions_dir = Path(os.environ["HARNESS_SESSION_INDEX_SESSIONS_DIR"])
output_env = os.environ.get("HARNESS_SESSION_INDEX_OUTPUT", "")
output_path = Path(output_env) if output_env else None

SENSITIVE_NAMES = (
    "BOT_" + "TOKEN",
    "OPEN" + "AI_API_" + "KEY",
    "ANTHROPIC_API_" + "KEY",
    "GEMINI_API_" + "KEY",
    "ZAI_API_" + "KEY",
)
HOOK_PATH = "api/" + "web" + "hooks"
HOOK_URL_PATTERN = r"https" + r"://(?:[^/\s]+/)?" + re.escape(HOOK_PATH) + r"/[^\s\"']+"

SENSITIVE_PATTERNS = [
    re.compile(HOOK_URL_PATTERN, re.I),
    re.compile(r"\bsk-[A-Za-z0-9][A-Za-z0-9_-]{12,}\b"),
    re.compile(r"\b[A-Za-z0-9_-]{32,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\b"),
    re.compile(r"(?i)\b(?:pass(?:word)?|secret|token|key)\s*[:=]\s*\S+"),
    *(re.compile(re.escape(name), re.I) for name in SENSITIVE_NAMES),
]

RAW_FIELD_HINTS = (
    "raw",
    "log",
    "logs",
    "diff",
    "patch",
    "body",
    "content",
    "transcript",
    "stdout",
    "stderr",
    "env",
)

MISSING = object()


def is_sensitive_string(value):
    return any(pattern.search(value) for pattern in SENSITIVE_PATTERNS)


def safe_scalar(value, default=None):
    if value is MISSING:
        return default
    if isinstance(value, bool) or value is None:
        return value
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value
    if isinstance(value, str):
        text = value.strip()
        if is_sensitive_string(text):
            return "[REDACTED]"
        if len(text) > 240:
            return text[:237] + "..."
        return text
    return default


def safe_text_list(value):
    if value is MISSING or value is None:
        return []
    if isinstance(value, str):
        item = safe_scalar(value, "")
        return [item] if item else []
    if isinstance(value, list):
        result = []
        for item in value[:25]:
            safe = safe_scalar(item, None)
            if isinstance(safe, str) and safe:
                result.append(safe)
            elif isinstance(safe, (int, float, bool)):
                result.append(str(safe))
        return result
    if isinstance(value, dict):
        result = []
        for key, item in list(value.items())[:25]:
            safe_key = safe_scalar(str(key), "")
            safe_item = safe_scalar(item, "")
            if safe_key and safe_item != "":
                result.append(f"{safe_key}: {safe_item}")
        return result
    return []


def find_value(data, paths):
    for path in paths:
        cur = data
        ok = True
        for part in path:
            if isinstance(cur, dict) and part in cur:
                cur = cur[part]
            else:
                ok = False
                break
        if ok:
            return cur
    return MISSING


def first_scalar(data, paths, default=None):
    return safe_scalar(find_value(data, paths), default)


def boolish(data, paths):
    value = find_value(data, paths)
    if value is MISSING:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in ("yes", "true", "1", "pass", "passed"):
            return True
        if lowered in ("no", "false", "0", "fail", "failed", "none"):
            return False
    return safe_scalar(value, None)


def safe_report_name(path):
    name = path.name
    if is_sensitive_string(name):
        return "[REDACTED]"
    return name


def include_report(path):
    if path.suffix.lower() != ".json":
        return False
    if path.name == "harness-session-index.json":
        return False
    return not path.name.endswith("-session-index.json")


def load_report(path):
    with path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError("top-level JSON is not an object")
    return data


def session_summary(path, data):
    phase = first_scalar(data, [
        ("phase",),
        ("PHASE",),
        ("metadata", "phase"),
        ("result", "phase"),
    ])
    status = first_scalar(data, [
        ("status",),
        ("STATUS",),
        ("result", "status"),
        ("verdict",),
    ])
    result = first_scalar(data, [
        ("result",),
        ("RESULT",),
        ("outcome",),
        ("summary", "result"),
    ])
    if result is None and isinstance(status, str):
        result = status

    manual_qa = first_scalar(data, [
        ("manual_qa_status",),
        ("MANUAL_QA_STATUS",),
        ("manualQAStatus",),
        ("qa", "manual_status"),
    ], "unknown")

    warnings = []
    for paths in (
        [("warnings",), ("WARNINGS",), ("checks", "warnings")],
        [("warning",), ("WARNING",)],
    ):
        warnings.extend(safe_text_list(find_value(data, paths)))
    failures = []
    for paths in (
        [("failures",), ("FAILURES",), ("errors",), ("checks", "failures")],
        [("failure",), ("FAILURE",), ("error",)],
    ):
        failures.extend(safe_text_list(find_value(data, paths)))

    next_action = first_scalar(data, [
        ("next_action",),
        ("NEXT",),
        ("next",),
        ("recommendation",),
    ])

    return {
        "session_id": first_scalar(data, [("session_id",), ("SESSION_ID",), ("id",)], path.stem),
        "phase": phase,
        "result": result,
        "status": status,
        "project": first_scalar(data, [("project",), ("PROJECT",), ("target_project",)]),
        "repo": first_scalar(data, [("repo",), ("repository",), ("TARGET_REPO",), ("target_repo",)]),
        "feature_id": first_scalar(data, [("feature_id",), ("FEATURE_ID",), ("feature", "id")]),
        "machine": first_scalar(data, [("machine",), ("MACHINE",), ("target_machine",), ("TARGET_MACHINE",)]),
        "nuc": first_scalar(data, [("nuc",), ("NUC",), ("machine", "nuc")]),
        "commit": first_scalar(data, [("commit",), ("COMMIT",), ("new_commit",), ("NEW_COMMIT_SHA",)]),
        "head": first_scalar(data, [("head",), ("HEAD",), ("commit_head",)]),
        "pushed": boolish(data, [("pushed",), ("PUSHED",)]),
        "proof_dir": first_scalar(data, [("proof_dir",), ("PROOF_DIR",), ("proof", "dir")]),
        "report_url": first_scalar(data, [("report_url",), ("REPORT_URL",), ("url",)]),
        "timestamp": first_scalar(data, [("timestamp",), ("TIMESTAMP",), ("created_at",)]),
        "started_at": first_scalar(data, [("started_at",), ("STARTED_AT",), ("start_time",)]),
        "finished_at": first_scalar(data, [("finished_at",), ("FINISHED_AT",), ("end_time",)]),
        "duration_minutes": first_scalar(data, [("duration_minutes",), ("DURATION_MINUTES",), ("duration", "minutes")]),
        "manual_qa_status": manual_qa,
        "discord_sent": boolish(data, [("discord_sent",), ("DISCORD_SENT",), ("notification", "discord_sent")]),
        "notify_mode": first_scalar(data, [("notify_mode",), ("NOTIFY_MODE",), ("notification", "mode")]),
        "dedupe_result": first_scalar(data, [("dedupe_result",), ("DEDUPE_RESULT",), ("notification", "dedupe_result")]),
        "services_restarted": boolish(data, [("services_restarted",), ("SERVICES_RESTARTED",)]),
        "caddy_changed": boolish(data, [("caddy_changed",), ("CADDY_CHANGED",)]),
        "dns_changed": boolish(data, [("dns_changed",), ("DNS_CHANGED",)]),
        "cron_changed": boolish(data, [("cron_changed",), ("CRON_CHANGED",)]),
        "timer_changed": boolish(data, [("timer_changed",), ("TIMER_CHANGED",)]),
        "tmux_changed": boolish(data, [("tmux_changed",), ("TMUX_CHANGED",)]),
        "secrets_printed": boolish(data, [("secrets_printed",), ("SECRETS_PRINTED",)]),
        "webhook_values_printed": boolish(data, [("webhook_values_printed",), ("WEBHOOK_VALUES_PRINTED",)]),
        "warnings": warnings[:25],
        "failures": failures[:25],
        "next_action": next_action,
        "source_report": safe_report_name(path),
    }


def iter_values(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from iter_values(item)
    elif isinstance(value, list):
        for item in value:
            yield from iter_values(item)
    else:
        yield value


def reject_sensitive_output(index):
    for value in iter_values(index):
        if isinstance(value, str) and is_sensitive_string(value):
            raise SystemExit("ERROR: generated index failed safety scan")
    encoded = json.dumps(index, sort_keys=True)
    for hint in RAW_FIELD_HINTS:
        needle = f'"{hint}"'
        if needle in encoded.lower():
            raise SystemExit("ERROR: generated index contains raw-field key")


def structural_validate(index):
    required_top = ("schema_version", "generated_at", "source_machine", "sessions")
    for key in required_top:
        if key not in index:
            raise SystemExit(f"ERROR: missing top-level key: {key}")
    if index["schema_version"] != "harness-session-index/v1":
        raise SystemExit("ERROR: unexpected schema_version")
    if not isinstance(index["sessions"], list):
        raise SystemExit("ERROR: sessions is not a list")
    with schema_path.open("r", encoding="utf-8") as fh:
        json.load(fh)


sessions = []
for path in sorted(sessions_dir.iterdir(), key=lambda p: p.name):
    if not path.is_file() or not include_report(path):
        continue
    try:
        data = load_report(path)
    except Exception:
        continue
    sessions.append(session_summary(path, data))

index = {
    "schema_version": "harness-session-index/v1",
    "generated_at": _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "source_machine": socket.gethostname(),
    "sessions": sessions,
}

structural_validate(index)
reject_sensitive_output(index)
payload = json.dumps(index, indent=2, sort_keys=True) + "\n"

if output_path is None:
    sys.stdout.write(payload)
else:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=str(output_path.parent), delete=False) as tmp:
        tmp.write(payload)
        tmp_name = tmp.name
    os.replace(tmp_name, output_path)
    print(f"WROTE={output_path}", file=sys.stderr)
    print(f"SESSION_COUNT={len(sessions)}", file=sys.stderr)
PY
