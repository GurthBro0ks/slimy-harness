# Harness Proof Metadata Standard

When a direct-task agent completes, it should write `harness-metadata.json` to
the proof directory before calling `notify-proof-dir-complete.sh`.

## Standard Closeout Snippet

```bash
PROOF="${PROOF:?missing proof dir}"
cd /path/to/current/repo

python3 > "$PROOF/harness-metadata.json" << PYEOF
import json, os, subprocess

def git_out(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return ""

def infer_nuc():
    import socket
    h = socket.gethostname().lower()
    if "nuc1" in h:
        return "nuc1"
    elif "nuc2" in h:
        return "nuc2"
    return "unknown"

metadata = {
    "feature_id": "FEATURE_ID_HERE",
    "task_title": "TASK TITLE HERE",
    "status": "completed",
    "agent": "opencode",
    "source_nuc": infer_nuc(),
    "source_hostname": socket.gethostname(),
    "repo_name": os.path.basename(git_out("git rev-parse --show-toplevel") or os.getcwd()),
    "repo_path": git_out("git rev-parse --show-toplevel") or os.getcwd(),
    "commit": git_out("git rev-parse --short HEAD"),
    "branch": git_out("git branch --show-current"),
    "proof_dir": os.environ.get("PROOF", ""),
    "summary": "Short task summary"
}

print(json.dumps(metadata, indent=2, ensure_ascii=False))
PYEOF

bash /home/slimy/slimy-harness/sequencer/notify-proof-dir-complete.sh \
  --proof-dir "$PROOF" \
  --repo-path "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

## Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| feature_id | string | recommended | Matches feature_list.json id |
| task_title | string | optional | Human-readable title for Discord card |
| status | string | recommended | completed, pass, warn, fail, blocked |
| agent | string | recommended | opencode, claude, codex, manual |
| source_nuc | string | auto-inferred | nuc1, nuc2, or unknown |
| source_hostname | string | auto-inferred | Full hostname |
| repo_name | string | auto-inferred | Repository display name |
| repo_path | string | auto-inferred | Filesystem path to repo root |
| commit | string | auto-inferred | Short commit hash |
| branch | string | optional | Git branch name |
| proof_dir | string | auto-filled | Proof directory path |
| summary | string | recommended | Short task summary (max 500 chars) |

## Behavior

1. If `harness-metadata.json` exists in the proof dir, the notifier uses it as source of truth.
2. CLI flags (`--repo-name`, `--source-nuc`, etc.) override metadata file values.
3. Missing fields are inferred from the environment (hostname, git repo, etc.).
4. If a field cannot be inferred, it is set to `"unknown"` (never `"?"`).
5. The resolved metadata is written to `$PROOF/harness-metadata.resolved.json`.
6. No secrets or webhook URLs are ever included.
