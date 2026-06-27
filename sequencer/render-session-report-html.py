#!/usr/bin/env python3
"""
render-session-report-html.py — render a session-report.json to standalone HTML.

Usage:
    python3 render-session-report-html.py REPORT_JSON OUTPUT_HTML
    python3 render-session-report-html.py --report-url URL REPORT_JSON OUTPUT_HTML

Reads a session report JSON produced by the harness closeout flow and writes
a single self-contained, dark-themed, mobile-readable HTML file. Designed
to be attached to a Discord message as a .html snapshot.

Properties:
- No external Python dependencies (stdlib only).
- All strings are HTML-escaped.
- Missing fields are rendered as "(none)".
- Invalid JSON exits with a clear non-zero status.
- Does NOT print secrets or the Discord webhook URL.
- Honors --report-url override; otherwise no public link is rendered.

The HTML includes:
- title, status, feature_id, repo, agent, nuc
- summary
- work_done
- validation
- blockers
- failed approaches (if present)
- next actions
- proof directory (if present)
- public report URL (if provided)
- raw JSON in a collapsible <details> block
"""
from __future__ import annotations

import argparse
import html
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


# ---- helpers ---------------------------------------------------------------

STATUS_COLORS = {
    "completed": "#22c55e",
    "pass": "#22c55e",
    "success": "#22c55e",
    "warn": "#f59e0b",
    "warning": "#f59e0b",
    "fail": "#ef4444",
    "failed": "#ef4444",
    "error": "#ef4444",
    "blocked": "#a855f7",
    "partial": "#eab308",
    "unknown": "#94a3b8",
}

STATUS_EMOJI = {
    "completed": "✅",
    "pass": "✅",
    "success": "✅",
    "warn": "⚠️",
    "warning": "⚠️",
    "fail": "❌",
    "failed": "❌",
    "error": "❌",
    "blocked": "⛔",
    "partial": "🟡",
    "unknown": "❔",
}


def esc(value: Any) -> str:
    if value is None:
        return "(none)"
    if not isinstance(value, str):
        value = str(value)
    return html.escape(value, quote=True)


def first_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        try:
            return json.dumps(value, indent=2, ensure_ascii=False)
        except Exception:
            return str(value)
    return str(value)


def get_in(d: Dict[str, Any], path: List[str], default: Any = None) -> Any:
    cur: Any = d
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def status_color(status: str) -> str:
    return STATUS_COLORS.get(str(status or "").lower(), STATUS_COLORS["unknown"])


def status_emoji(status: str) -> str:
    return STATUS_EMOJI.get(str(status or "").lower(), STATUS_EMOJI["unknown"])


def render_list(items: Any) -> str:
    """Render a list/str as <ul>; safely escape."""
    if items is None:
        return "<p class=\"muted\">(none)</p>"
    if isinstance(items, str):
        items = [items]
    if not isinstance(items, list):
        return f"<p>{esc(first_text(items))}</p>"
    if not items:
        return "<p class=\"muted\">(none)</p>"
    rows = "\n".join(f"<li>{esc(first_text(x))}</li>" for x in items)
    return f"<ul class=\"bullets\">\n{rows}\n</ul>"


def render_block(title: str, body_html: str) -> str:
    return (
        f"<section class=\"card\">\n"
        f"  <h2>{esc(title)}</h2>\n"
        f"  {body_html}\n"
        f"</section>\n"
    )


def render_kv(label: str, value: Any) -> str:
    return f"<dt>{esc(label)}</dt><dd>{esc(first_text(value))}</dd>"


def boolish(value: Any) -> Optional[bool]:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"1", "yes", "true", "pass", "passed", "success"}:
            return True
        if lowered in {"0", "no", "false", "fail", "failed", "none"}:
            return False
    return None


def report_test_label(report: Dict[str, Any]) -> str:
    tests = report.get("tests", {})
    if not isinstance(tests, dict):
        tests = {}

    explicit_label = str(tests.get("label") or tests.get("status_label") or "").strip().upper()
    if explicit_label in {"SMOKE ONLY", "TESTS NOT RUN", "TESTS FAIL", "TESTS PASS"}:
        return explicit_label

    details = first_text(tests.get("details", ""))
    validation = first_text(get_in(report, ["validation"], ""))
    combined = f"{details}\n{validation}".upper().replace("-", " ").replace("_", " ")

    if "SMOKE ONLY" in combined or "SMOKE TEST" in combined or "ROUTE SMOKE" in combined:
        return "SMOKE ONLY"

    ran = boolish(tests.get("ran"))
    passed = boolish(tests.get("passed"))
    if ran is False:
        return "TESTS NOT RUN"
    if ran is True and passed is True:
        return "TESTS PASS"
    if ran is True and passed is False:
        return "TESTS FAIL"

    return "TESTS NOT RUN"


# ---- main render -----------------------------------------------------------

def build_html(report: Dict[str, Any], report_url: Optional[str]) -> str:
    status = str(report.get("status", "unknown"))
    color = status_color(status)
    emoji = status_emoji(status)
    title = str(report.get("feature_id") or report.get("session_id") or "session-report")
    summary = first_text(report.get("summary", ""))
    work_done = first_text(report.get("work_done", ""))
    validation = first_text(get_in(report, ["validation"], report.get("tests", {})))
    test_label = report_test_label(report)
    blockers = report.get("blockers", [])
    failed_approaches = report.get("failed_approaches", [])
    next_actions = report.get("next_actions", report.get("recommendation"))
    proof_dir = report.get("proof_dir") or report.get("proof_directory")
    changes = report.get("changes", [])
    raw_json = json.dumps(report, indent=2, ensure_ascii=False)

    # Recommendation as text if dict
    next_actions_html = ""
    if isinstance(next_actions, dict):
        rec_reason = next_actions.get("reasoning", "")
        rec_id = next_actions.get("next_feature_id", "")
        rec_risk = next_actions.get("risk_notes", "")
        bits = []
        if rec_id:
            bits.append(f"<p><strong>Next feature:</strong> {esc(rec_id)}</p>")
        if rec_reason:
            bits.append(f"<p>{esc(rec_reason)}</p>")
        if rec_risk:
            bits.append(f"<p><strong>Risk notes:</strong> {esc(rec_risk)}</p>")
        next_actions_html = "\n".join(bits) or "<p class=\"muted\">(none)</p>"
    elif isinstance(next_actions, str) and next_actions.strip():
        next_actions_html = f"<p>{esc(next_actions)}</p>"
    else:
        next_actions_html = "<p class=\"muted\">(none)</p>"

    # Failed approaches as small list
    if isinstance(failed_approaches, list) and failed_approaches:
        fa_rows = []
        for fa in failed_approaches[:10]:
            if isinstance(fa, dict):
                fa_rows.append(
                    f"<li><strong>{esc(fa.get('feature_id', '?'))}</strong> "
                    f"#{esc(fa.get('attempt_number', '?'))}: "
                    f"{esc(fa.get('approach_description', ''))[:300]}"
                    f"<br><em>Failure:</em> {esc(fa.get('failure_reason', ''))[:300]}</li>"
                )
            else:
                fa_rows.append(f"<li>{esc(first_text(fa))}</li>")
        failed_html = "<ul class=\"bullets\">\n" + "\n".join(fa_rows) + "\n</ul>"
    else:
        failed_html = "<p class=\"muted\">(none)</p>"

    # Blockers
    if isinstance(blockers, list) and blockers:
        b_rows = []
        for b in blockers:
            if isinstance(b, dict):
                b_rows.append(
                    f"<li><strong>{esc(b.get('type', 'manual'))}</strong>: "
                    f"{esc(b.get('description', ''))}</li>"
                )
            else:
                b_rows.append(f"<li>{esc(first_text(b))}</li>")
        blockers_html = "<ul class=\"bullets\">\n" + "\n".join(b_rows) + "\n</ul>"
    else:
        blockers_html = "<p class=\"muted\">(none)</p>"

    # Top metadata card
    meta_pairs = [
        ("feature_id", report.get("feature_id", "")),
        ("status", f"{emoji} {status}"),
        ("test label", test_label),
        ("agent", report.get("agent", "")),
        ("nuc", report.get("nuc", "")),
        ("repo / project", report.get("project", report.get("repo", ""))),
        ("prompt_type", report.get("prompt_type", "")),
        ("session_id", report.get("session_id", "")),
        ("timestamp", report.get("timestamp", "")),
        ("duration (min)", report.get("duration_minutes", "")),
    ]
    meta_html = "\n".join(render_kv(k, v) for k, v in meta_pairs if v not in (None, ""))

    # Public report link
    if report_url:
        link_html = (
            f"<p><a class=\"link\" href=\"{esc(report_url)}\" target=\"_blank\" "
            f"rel=\"noopener noreferrer\">{esc(report_url)}</a></p>"
            f"<p class=\"muted small\">Owner-gated. Login required.</p>"
        )
    else:
        link_html = "<p class=\"muted\">(no public link configured)</p>"

    # Body sections
    summary_html = render_block("Summary", f"<p>{esc(summary) or '<span class=\"muted\">(none)</span>'}</p>")
    work_done_html = render_block("Work Done", f"<p>{esc(work_done) or '<span class=\"muted\">(none)</span>'}</p>")
    test_label_html = render_block("Test Label", f"<p><span class=\"test-label\">{esc(test_label)}</span></p>")
    validation_html = render_block("Validation", f"<p>{esc(validation) or '<span class=\"muted\">(none)</span>'}</p>")
    blockers_section = render_block("Blockers", blockers_html)
    failed_section = render_block("Failed Approaches (SkillOpt buffer)", failed_html)
    next_section = render_block("Next Actions", next_actions_html)
    changes_section = render_block("Files / Changes", render_list(changes))
    proof_section = ""
    if proof_dir:
        proof_section = render_block("Proof Directory", f"<p><code>{esc(proof_dir)}</code></p>")
    link_section = render_block("Public Report Link", link_html)
    raw_section = (
        "<section class=\"card\">\n"
        "  <h2>Raw JSON</h2>\n"
        "  <details>\n"
        f"    <summary class=\"muted\">Click to expand full session report</summary>\n"
        f"    <pre class=\"raw\">{esc(raw_json)}</pre>\n"
        "  </details>\n"
        "</section>\n"
    )

    return f"""<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>{esc(title)} — session report</title>
<style>
  :root {{
    --bg: #0f172a;
    --panel: #111827;
    --panel-2: #1f2937;
    --fg: #e2e8f0;
    --muted: #94a3b8;
    --accent: {color};
    --border: #334155;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0;
    background: var(--bg);
    color: var(--fg);
    font: 15px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    padding: 1.25rem;
  }}
  header {{
    background: var(--panel);
    border: 1px solid var(--border);
    border-left: 4px solid var(--accent);
    border-radius: 8px;
    padding: 1rem 1.25rem;
    margin-bottom: 1rem;
  }}
  header h1 {{
    margin: 0 0 0.25rem 0;
    font-size: 1.25rem;
  }}
  header .sub {{ color: var(--muted); font-size: 0.875rem; }}
  dl.meta {{
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 0.25rem 0.75rem;
    margin: 0.75rem 0 0 0;
  }}
  dl.meta dt {{ color: var(--muted); }}
  dl.meta dd {{ margin: 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.875rem; }}
  .card {{
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1rem 1.25rem;
    margin: 0 0 1rem 0;
  }}
  .card h2 {{
    margin: 0 0 0.5rem 0;
    font-size: 1rem;
    letter-spacing: 0.02em;
    color: var(--accent);
    text-transform: uppercase;
  }}
  ul.bullets {{ margin: 0.25rem 0 0.25rem 1.25rem; padding: 0; }}
  ul.bullets li {{ margin: 0.15rem 0; }}
  .muted {{ color: var(--muted); }}
  .small {{ font-size: 0.8rem; }}
  .test-label {{
    display: inline-block;
    border: 1px solid var(--border);
    border-left: 4px solid var(--accent);
    border-radius: 4px;
    background: var(--panel-2);
    padding: 0.2rem 0.45rem;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.85rem;
    font-weight: 700;
  }}
  code {{ background: var(--panel-2); padding: 0.05rem 0.3rem; border-radius: 4px; }}
  pre.raw {{
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 0.75rem;
    overflow-x: auto;
    font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
  }}
  a.link {{
    color: #60a5fa;
    text-decoration: none;
    word-break: break-all;
  }}
  a.link:hover {{ text-decoration: underline; }}
  @media (max-width: 600px) {{
    body {{ padding: 0.75rem; }}
    header, .card {{ padding: 0.85rem 1rem; }}
  }}
</style>
</head>
<body>
<header>
  <h1>{esc(title)}</h1>
  <div class=\"sub\">Session report — generated by render-session-report-html.py</div>
  <dl class=\"meta\">
{meta_html}
  </dl>
</header>
{link_section}
{summary_html}
{work_done_html}
{test_label_html}
{validation_html}
{blockers_section}
{failed_section}
{next_section}
{changes_section}
{proof_section}
{raw_section}
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render a session-report.json to standalone HTML."
    )
    parser.add_argument(
        "--report-url",
        default=None,
        help="Public report URL to embed (overrides env).",
    )
    parser.add_argument(
        "--public-base-url",
        default=None,
        help="If set and --report-url is not, the renderer will build "
             "<base>/reports/sessions/<session_id>.json as the link.",
    )
    parser.add_argument(
        "report_json",
        type=Path,
        help="Path to session-report.json",
    )
    parser.add_argument(
        "output_html",
        type=Path,
        help="Path to write the HTML file to",
    )
    args = parser.parse_args()

    if not args.report_json.is_file():
        print(f"render-session-report-html: input not found: {args.report_json}", file=sys.stderr)
        return 2

    try:
        raw = args.report_json.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"render-session-report-html: read failed: {exc}", file=sys.stderr)
        return 3

    try:
        report = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(
            f"render-session-report-html: invalid JSON in {args.report_json}: {exc}",
            file=sys.stderr,
        )
        return 4

    if not isinstance(report, dict):
        print(
            "render-session-report-html: top-level JSON value must be an object",
            file=sys.stderr,
        )
        return 5

    report_url = args.report_url
    if not report_url and args.public_base_url:
        sid = str(report.get("session_id") or report.get("timestamp") or "session-report")
        # url-encode minimally (slashes/dots are safe)
        report_url = f"{args.public_base_url.rstrip('/')}/reports/sessions/{sid}.json"

    html_text = build_html(report, report_url)

    try:
        args.output_html.parent.mkdir(parents=True, exist_ok=True)
        args.output_html.write_text(html_text, encoding="utf-8")
    except OSError as exc:
        print(f"render-session-report-html: write failed: {exc}", file=sys.stderr)
        return 6

    print(f"render-session-report-html: wrote {args.output_html} ({len(html_text)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
