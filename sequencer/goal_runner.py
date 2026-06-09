#!/usr/bin/env python3
"""
goal_runner.py — inner retry loop controller (Phase 1: dry-run only)

State machine that takes ONE feature and loops
  build -> truth-gate -> evaluate -> fix
until the feature passes, gets stuck, or hits a hard boundary.

Module-level functions (testable):
  count_stuck_signals(current_qa_result, previous_qa_result) -> int
  load_feature(feature_list_path, feature_id) -> dict
  build_attempt_prompt(feature, attempt_num, fix_packet, max_attempts) -> str

Phase 1 contract: --dry-run is REQUIRED. No tmux dispatch. No Discord.
No real mutation of feature_list.json. No git worktrees.
"""

import argparse
import datetime
import hashlib
import json
import logging
import os
import subprocess
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

def _configure_logging():
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] [goal_runner] %(levelname)s %(message)s",
        stream=sys.stderr,
    )


log = logging.getLogger("goal_runner")


# ---------------------------------------------------------------------------
# Module-level testable functions
# ---------------------------------------------------------------------------

def count_stuck_signals(current_qa_result, previous_qa_result):
    """Return an integer count of stuck signals between two qa-result dicts.

    Signals (per spec):
      1. current error_signatures overlap with previous error_signatures
      2. current changed_files is empty
      3. current changed_files == previous changed_files AND error overlap
      4. current test_pass_count <= previous test_pass_count
      5. session_status == "blocked"  -> +2 (agent self-reported)
    """
    if not current_qa_result:
        return 0
    if not previous_qa_result:
        return 0

    signals = 0

    curr_sigs = set(current_qa_result.get("error_signatures") or [])
    prev_sigs = set(previous_qa_result.get("error_signatures") or [])
    overlap = bool(curr_sigs & prev_sigs)

    curr_changed = current_qa_result.get("changed_files") or []
    prev_changed = previous_qa_result.get("changed_files") or []

    if overlap:
        signals += 1
    if not curr_changed:
        signals += 1
    if overlap and curr_changed and curr_changed == prev_changed:
        signals += 1

    curr_pass = current_qa_result.get("test_pass_count")
    prev_pass = previous_qa_result.get("test_pass_count")
    if curr_pass is not None and prev_pass is not None:
        if curr_pass <= prev_pass:
            signals += 1

    if current_qa_result.get("session_status") == "blocked":
        signals += 2

    return signals


def load_feature(feature_list_path, feature_id):
    """Load a single feature dict from feature_list.json by id.

    Tolerates both {"features": [...]} and bare [...] forms.
    Returns dict or None if not found.
    Raises FileNotFoundError if feature_list_path is missing.
    """
    p = Path(feature_list_path)
    if not p.is_file():
        raise FileNotFoundError(f"feature list not found: {feature_list_path}")
    with p.open() as f:
        fl = json.load(f)
    if isinstance(fl, dict):
        features = fl.get("features", [])
    elif isinstance(fl, list):
        features = fl
    else:
        features = []
    for feat in features:
        if feat.get("id") == feature_id:
            return feat
    return None


def build_attempt_prompt(feature, attempt_num, fix_packet, max_attempts):
    """Build the agent prompt for an attempt.

    Attempt 1: startup + feature + truth-gate + shutdown-addon
    Attempt 2+: above + RETRY CONTEXT block
    Attempt == max_attempts: adds SYSTEMATIC DEBUGGING mode-switch
    """
    feature_id = feature.get("id", "unknown")
    project = feature.get("project", "unknown")
    description = feature.get("description", "").strip()
    steps = feature.get("steps") or []

    truth_gate_lines = []
    for s in steps:
        if isinstance(s, str) and s.strip():
            truth_gate_lines.append(f"  - {s.strip()}")

    truth_gate_block = (
        "Truth gate commands (must all pass):\n" + "\n".join(truth_gate_lines)
        if truth_gate_lines
        else "Truth gate commands: (none discovered — agent must rely on session-report content)"
    )

    prompt_parts = [
        "cat /home/slimy/AGENTS.md",
        "cat /home/slimy/claude-progress.md",
        "source /home/slimy/init.sh",
        "",
        "MANDATORY STARTUP (do all before writing any code):",
        "1. cat /home/slimy/AGENTS.md",
        "2. cat /home/slimy/claude-progress.md",
        "3. cat /home/slimy/feature_list.json",
        "4. cat /home/slimy/server-state.md",
        "5. source /home/slimy/init.sh",
        "",
        f"You are an autonomous agent dispatched by the SlimyAI goal-runner.",
        "",
        f"YOUR TASK: Fix feature {feature_id} in project {project}.",
        "",
        "Feature description:",
        description or "(no description)",
        "",
        truth_gate_block,
        "",
        "MANDATORY SHUTDOWN:",
        "1. Update /home/slimy/claude-progress.md",
        "2. Do NOT set passes:true (leave for QA)",
        "3. git commit in the project repo",
        "4. Run truth gate (lint/tests) and verify",
        "",
        "## SEQUENCER SHUTDOWN (do this LAST)",
        "",
        "Write /home/slimy/session-report.json with this structure:",
        "{",
        '  "session_id": "<ISO-8601>",',
        '  "agent": "opencode",',
        '  "nuc": "nuc1",',
        f'  "project": "{project}",',
        f'  "feature_id": "{feature_id}",',
        '  "prompt_type": "A",',
        '  "status": "completed|partial|failed|blocked",',
        '  "summary": "<1-2 sentences>",',
        '  "changes": ["file1", "file2"],',
        '  "tests": {"ran": true, "passed": false, "details": "..."},',
        '  "blockers": [],',
        '  "recommendation": {"next_feature_id": null, "reasoning": "", "risk_notes": ""},',
        '  "kb_learnings": [],',
        '  "duration_minutes": 0,',
        '  "timestamp": "<ISO-8601>"',
        "}",
        "",
        'Validate: python3 -c "import json; json.load(open(\'/home/slimy/session-report.json\'))"',
    ]

    # RETRY CONTEXT block (attempt >= 2)
    if attempt_num >= 2 and fix_packet:
        failing = fix_packet.get("failing_commands") or []
        sigs = fix_packet.get("error_signatures") or []
        last_sig = sigs[-1] if sigs else "(none)"
        prev_attempt = max(attempt_num - 1, 1)
        same_sig = "YES" if sigs else "NO"
        changed_files = fix_packet.get("changed_files") or []
        changed_files_str = ", ".join(changed_files) if changed_files else "none"
        failed_approaches = fix_packet.get("failed_approaches") or []
        qa_fix_brief = fix_packet.get("qa_fix_brief") or "(no brief)"

        failing_block = []
        for fc in failing[:5]:
            cmd = fc.get("command", "?")
            stderr_head = (fc.get("stderr_head") or "")[:200]
            failing_block.append(f"  - command: {cmd}\n    stderr: {stderr_head}")

        fa_block = []
        for fa in failed_approaches[:10]:
            fa_block.append(f"  - {fa}")

        prompt_parts.extend([
            "",
            "## RETRY CONTEXT — READ THIS FIRST",
            f"This is attempt {attempt_num} of {max_attempts}. Previous attempts failed.",
            "",
            "### Failing gates (from last qa-result.json):",
            "\n".join(failing_block) if failing_block else "  (none recorded)",
            "",
            f"### Error signature (md5): {last_sig}  — same as last attempt? {same_sig}",
            "",
            f"### Files changed in last attempt: {changed_files_str}",
            "",
            "### What was tried and did not work:",
            "\n".join(fa_block) if fa_block else "  (none recorded)",
            "",
            f"### QA gate recommendation: {qa_fix_brief}",
            "",
            "DO NOT repeat a failed approach. Try a different strategy.",
            "If you believe the task cannot be completed as specified, write status: \"blocked\".",
        ])

    # MODE SWITCH at last attempt
    if attempt_num >= max_attempts:
        prompt_parts.extend([
            "",
            f"## MODE: SYSTEMATIC DEBUGGING (attempt {attempt_num} of {max_attempts} — last chance)",
            "You are NOT in feature-build mode anymore.",
            "Do NOT add broad new architecture.",
            "1. Reproduce the exact failure first.",
            "2. Identify the smallest root cause.",
            "3. Patch only that cause.",
            "4. Verify the patch fixes the gate failure.",
            "If you cannot reproduce, write status: \"blocked\".",
        ])

    return "\n".join(prompt_parts)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now_iso():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _read_json(path):
    p = Path(path)
    if not p.is_file():
        return None
    with p.open() as f:
        return json.load(f)


def _write_json(path, data):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".tmp")
    with tmp.open("w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, p)


def _append_event(goal_dir, event_obj):
    p = Path(goal_dir) / "events.jsonl"
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a") as f:
        f.write(json.dumps(event_obj) + "\n")


def _file_unchanged(path, new_content):
    p = Path(path)
    if not p.is_file():
        return False
    return p.read_text() == new_content


def _discover_truth_gate_commands(feature):
    """Return list[str] of truth gate commands, or [] if none."""
    for key in ("steps", "truth_gates", "validation_commands", "acceptance"):
        v = feature.get(key)
        if isinstance(v, list) and v:
            return [str(x) for x in v if x]
    return []


def _git_base_sha(project_dir):
    """Read base SHA via git -C <dir> rev-parse HEAD; 'unknown' if not a git repo."""
    if not project_dir:
        return "unknown"
    p = Path(project_dir)
    if not p.is_dir():
        return "unknown"
    if not (p / ".git").exists():
        return "unknown"
    try:
        out = subprocess.run(
            ["git", "-C", str(p), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True, timeout=10
        )
        return out.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

REJECT_STATUS = ("completed", "abandoned", "done", "accepted")


def _should_reject(feature):
    if feature.get("passes") is True:
        return "passes==true"
    if feature.get("status") in REJECT_STATUS:
        return f"status={feature.get('status')}"
    return None


def _read_last_event(goal_dir):
    p = Path(goal_dir) / "events.jsonl"
    if not p.is_file():
        return None
    last = None
    with p.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                last = json.loads(line)
            except json.JSONDecodeError:
                continue
    return last


def _resume_state(goal_dir, current_attempt):
    """Return a label describing the resume point, or None if fresh."""
    last = _read_last_event(goal_dir)
    if not last:
        return None
    evt = last.get("event")
    if evt == "awaiting_report":
        return "COLLECT"
    if evt in ("goal_started", "attempt_started"):
        # Check if the prompt for this attempt already exists
        prompt_path = Path(goal_dir) / f"attempt-{current_attempt}" / "prompt.md"
        if prompt_path.is_file():
            return "COLLECT"
        return "BUILD"
    return None


def _run_qa_gate(feature_id, attempt_dir, feature_list_path, dry_run=True):
    """Invoke sequencer/qa-gate.sh and return the qa-result dict (or None)."""
    repo_root = Path(__file__).resolve().parent.parent
    qa_gate = repo_root / "sequencer" / "qa-gate.sh"
    if not qa_gate.is_file():
        log.error("qa-gate.sh not found at %s", qa_gate)
        return None
    env = os.environ.copy()
    env["QA_GATE_DRY_RUN"] = "1" if dry_run else "0"
    cmd = [
        "bash", str(qa_gate),
        feature_id,
        str(Path(attempt_dir) / "session-report.json"),
        str(attempt_dir),
        str(feature_list_path),
    ]
    log.info("Running qa-gate: %s", " ".join(cmd))
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=120)
        if result.returncode != 0:
            log.warning("qa-gate.sh exited with %d: %s", result.returncode, result.stderr.strip())
    except subprocess.TimeoutExpired:
        log.error("qa-gate.sh timed out")
        return None
    return _read_json(Path(attempt_dir) / "qa-result.json")


def _build_fix_packet(feature_id, attempt, goal_dir, feature_list_path):
    """Invoke sequencer/build_fix_packet.py. Returns dict or None."""
    repo_root = Path(__file__).resolve().parent.parent
    bp = repo_root / "sequencer" / "build_fix_packet.py"
    if not bp.is_file():
        log.error("build_fix_packet.py not found at %s", bp)
        return None
    cmd = [
        sys.executable, str(bp),
        "--feature-id", feature_id,
        "--attempt", str(attempt),
        "--goal-dir", str(goal_dir),
        "--feature-list", str(feature_list_path),
    ]
    log.info("Running build_fix_packet: %s", " ".join(cmd))
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            log.warning("build_fix_packet.py exited %d: %s", result.returncode, result.stderr.strip())
    except subprocess.TimeoutExpired:
        log.error("build_fix_packet.py timed out")
        return None
    return _read_json(Path(goal_dir) / f"attempt-{attempt}" / "fix-packet.json")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    _configure_logging()
    parser = argparse.ArgumentParser(description="SlimyAI goal-runner (Phase 1: dry-run)")
    parser.add_argument("feature_id", help="Feature ID from feature_list.json")
    parser.add_argument("--max-attempts", type=int, default=3)
    parser.add_argument("--wall-clock-minutes", type=int, default=90)
    parser.add_argument("--dry-run", action="store_true",
                        help="Phase 1 mode: write prompt, do not dispatch a real agent.")
    parser.add_argument("--notify-mode", default="dry-run",
                        choices=("dry-run", "runtime", "disabled"))
    parser.add_argument("--goals-dir", default="/home/slimy/harness-logs/goals")
    parser.add_argument("--feature-list", default="/home/slimy/feature_list.json")
    args = parser.parse_args(argv)

    if not args.dry_run:
        log.error("Phase 1 contract: --dry-run is REQUIRED. Refusing to run in real mode.")
        return 2

    # ---- INIT ----
    try:
        feature = load_feature(args.feature_list, args.feature_id)
    except FileNotFoundError as e:
        log.error("init: %s", e)
        return 2
    if feature is None:
        log.error("init: feature %r not found in %s", args.feature_id, args.feature_list)
        return 2
    reject = _should_reject(feature)
    if reject:
        log.error("init: feature %r rejected (%s)", args.feature_id, reject)
        return 2

    project = feature.get("project", "unknown")
    project_path = feature.get("path") or f"/opt/slimy/{project}"
    truth_gates = _discover_truth_gate_commands(feature)
    truth_gate_status = "discovered" if truth_gates else "missing"
    if truth_gate_status == "missing":
        log.warning("No truth gate commands found for %s", args.feature_id)

    goals_root = Path(args.goals_dir)
    goal_dir = goals_root / args.feature_id
    base_sha = _git_base_sha(project_path)
    log.info("base SHA for %s: %s", project_path, base_sha)

    # Create goal dir + initial state
    goal_dir.mkdir(parents=True, exist_ok=True)
    goal_path = goal_dir / "goal.json"
    events_path = goal_dir / "events.jsonl"

    fresh = not goal_path.is_file()
    if fresh:
        goal_state = {
            "feature_id": args.feature_id,
            "status": "running",
            "started": _now_iso(),
            "current_attempt": 1,
            "max_attempts": args.max_attempts,
            "wall_clock_limit_minutes": args.wall_clock_minutes,
            "project": project,
            "project_path": project_path,
            "truth_gate_status": truth_gate_status,
            "truth_gate_commands": truth_gates,
            "attempts": [],
        }
        _write_json(goal_path, goal_state)
        _append_event(goal_dir, {"event": "goal_started", "ts": _now_iso(),
                                 "feature_id": args.feature_id})
        log.info("created goal dir: %s", goal_dir)

    # ---- RESUME CHECK ----
    goal_state = _read_json(goal_path)
    current_attempt = goal_state.get("current_attempt", 1)
    resume = _resume_state(goal_dir, current_attempt)
    if resume:
        log.info("resuming: state=%s attempt=%d", resume, current_attempt)

    # ---- ATTEMPT LOOP ----
    while current_attempt <= args.max_attempts:
        attempt_dir = goal_dir / f"attempt-{current_attempt}"
        attempt_dir.mkdir(parents=True, exist_ok=True)

        # CHECKPOINT
        if not resume or resume == "BUILD":
            _append_event(goal_dir, {"event": "checkpoint", "ts": _now_iso(),
                                     "attempt": current_attempt, "base_sha": base_sha,
                                     "would_worktree": f"/tmp/slimy-goals/{args.feature_id}/attempt-{current_attempt}/worktree"})
            log.info("CHECKPOINT attempt=%d base_sha=%s (worktree would be created in real mode)", current_attempt, base_sha)
            resume = None

        # BUILD
        if not resume or resume == "BUILD":
            fix_packet = None
            if current_attempt >= 2:
                fix_packet = _build_fix_packet(args.feature_id, current_attempt - 1,
                                               goal_dir, args.feature_list)
            prompt = build_attempt_prompt(feature, current_attempt, fix_packet, args.max_attempts)
            prompt_path = attempt_dir / "prompt.md"
            if not _file_unchanged(prompt_path, prompt):
                prompt_path.write_text(prompt)
                _append_event(goal_dir, {"event": "prompt_written", "ts": _now_iso(),
                                         "attempt": current_attempt, "path": str(prompt_path)})
                log.info("wrote prompt to %s", prompt_path)
            else:
                log.info("prompt unchanged; left in place at %s", prompt_path)
            _append_event(goal_dir, {"event": "attempt_started", "ts": _now_iso(),
                                     "attempt": current_attempt})
            log.info("DISPATCH_SKIPPED: dry-run mode (no tmux launch)")
            resume = None

        # COLLECT
        report_path = attempt_dir / "session-report.json"
        if not report_path.is_file():
            msg = (f"dry-run: prompt written to {attempt_dir / 'prompt.md'}. "
                   f"No session report found. Place a session report at "
                   f"{report_path} and re-run to continue.")
            log.info(msg)
            _append_event(goal_dir, {"event": "awaiting_report", "ts": _now_iso(),
                                     "attempt": current_attempt, "path": str(report_path)})
            return 0

        log.info("found session-report.json at %s", report_path)
        _append_event(goal_dir, {"event": "report_collected", "ts": _now_iso(),
                                 "attempt": current_attempt, "path": str(report_path)})

        # GATE
        qa_result = _run_qa_gate(args.feature_id, attempt_dir, args.feature_list, dry_run=True)
        if qa_result is None:
            log.error("qa-gate produced no result for attempt %d", current_attempt)
            _append_event(goal_dir, {"event": "gate_error", "ts": _now_iso(),
                                     "attempt": current_attempt})
            return 2

        # DECIDE
        verdict = qa_result.get("verdict")
        prev_attempt = current_attempt - 1
        prev_qa = _read_json(goal_dir / f"attempt-{prev_attempt}" / "qa-result.json")
        signals = count_stuck_signals(qa_result, prev_qa) if current_attempt > 1 else 0

        decision_log = {
            "event": "decision",
            "ts": _now_iso(),
            "attempt": current_attempt,
            "verdict": verdict,
            "stuck_signals": signals,
        }
        _append_event(goal_dir, decision_log)

        if verdict == "pass":
            _append_event(goal_dir, {"event": "goal_passed", "ts": _now_iso(),
                                     "attempt": current_attempt})
            goal_state = _read_json(goal_path)
            goal_state["status"] = "passed"
            goal_state["ended"] = _now_iso()
            goal_state.setdefault("attempts", []).append({
                "number": current_attempt, "started": goal_state.get("started"),
                "ended": _now_iso(), "verdict": "pass", "stuck_signals": signals,
            })
            _write_json(goal_path, goal_state)
            _write_result_md(goal_dir, goal_state, feature, args)
            log.info("GOAL PASSED on attempt %d", current_attempt)
            log.info("DRY-RUN: would notify Discord (notify-mode=%s)", args.notify_mode)
            log.info("DRY-RUN: auto-close would set passes:true (not done by goal-runner)")
            return 0

        if signals >= 3:
            _escalate(goal_dir, goal_path, current_attempt, signals,
                      f"stuck_signals={signals} >= 3 on attempt {current_attempt}", args, feature)
            return 2

        if current_attempt >= args.max_attempts:
            _escalate(goal_dir, goal_path, current_attempt, signals,
                      f"max_attempts={args.max_attempts} reached", args, feature)
            return 2

        if signals == 2:
            log.info("RETRY: signals=%d — next attempt will use DEBUG mode prompt", signals)
        else:
            log.info("RETRY: signals=%d", signals)

        # loop continuation
        current_attempt += 1
        goal_state = _read_json(goal_path)
        goal_state["current_attempt"] = current_attempt
        _write_json(goal_path, goal_state)
        resume = None  # fresh attempt

    # should not reach here
    _escalate(goal_dir, goal_path, current_attempt, 0,
              "loop exited unexpectedly", args, feature)
    return 2


def _escalate(goal_dir, goal_path, attempt, signals, reason, args, feature):
    _append_event(goal_dir, {"event": "goal_escalated", "ts": _now_iso(),
                             "attempt": attempt, "reason": reason,
                             "stuck_signals": signals})
    goal_state = _read_json(goal_path)
    goal_state["status"] = "escalated"
    goal_state["ended"] = _now_iso()
    goal_state.setdefault("attempts", []).append({
        "number": attempt, "ended": _now_iso(), "verdict": "fail",
        "stuck_signals": signals, "escalation_reason": reason,
    })
    _write_json(goal_path, goal_state)
    _write_result_md(goal_dir, goal_state, feature, args)
    log.error("GOAL ESCALATED: %s (signals=%d)", reason, signals)
    log.info("DRY-RUN: would block feature %s in feature_list.json", args.feature_id)
    log.info("DRY-RUN: would notify Discord (notify-mode=%s)", args.notify_mode)


def _write_result_md(goal_dir, goal_state, feature, args):
    lines = [
        f"# Goal Result: {args.feature_id}",
        "",
        f"- Status: **{goal_state.get('status')}**",
        f"- Started: {goal_state.get('started')}",
        f"- Ended:   {goal_state.get('ended', '(in progress)')}",
        f"- Attempts: {len(goal_state.get('attempts', []))} of {args.max_attempts}",
        f"- Project: {goal_state.get('project')} ({goal_state.get('project_path')})",
        f"- Truth gate: {goal_state.get('truth_gate_status')}",
        "",
        "## Attempts",
        "",
    ]
    for a in goal_state.get("attempts", []):
        lines.append(
            f"- attempt {a.get('number')}: verdict={a.get('verdict')}, "
            f"stuck_signals={a.get('stuck_signals')}, "
            f"reason={a.get('escalation_reason', '-')}"
        )
    lines.extend([
        "",
        "## What goal-runner would do in real mode",
        "",
        f"- notify-mode: {args.notify_mode}",
        f"- DRY-RUN: this entire run did not dispatch a real agent.",
        "- In real mode, successful attempts would be merged; failed attempts archived.",
        "- feature_list.json is NOT modified by goal-runner; auto-close.sh owns passes:true.",
        "",
    ])
    p = goal_dir / "RESULT.md"
    p.write_text("\n".join(lines))


if __name__ == "__main__":
    sys.exit(main())
