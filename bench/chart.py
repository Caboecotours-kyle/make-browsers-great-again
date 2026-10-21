#!/usr/bin/env python3
"""Renders bench/run.py results as a self-contained HTML page.

Usage: bench/chart.py [--inline] [results.json [control.json]] [-o out.html]
  control.json  results of the chrome-control / mbga-awake-control runs
  --inline      no page background or title, text in the host page's theme
"""

import glob
import html
import json
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SERIES = [("chrome", "Chrome", 1), ("mbga-awake", "MBGA, sleeping off", 2),
          ("mbga-default", "MBGA, defaults", 3)]
# Control runs are shown under the series they control for.
CONTROL = {"chrome": "chrome-control", "mbga-awake": "mbga-awake-control"}

# (title, path, unit, note, mark half of the largest value)
PANELS = [
    ("Memory with all 50 tabs loaded", ("loaded", "total_mb"), "MB",
     "90 s after the last tab opened. Dashed line: half of Chrome.", True),
    ("Memory after 12 minutes untouched", ("after_idle", "total_mb"), "MB",
     "Same session, nobody touching it. MBGA's defaults also put idle tabs to sleep.", True),
    ("Idle power after 12 minutes", ("idle_after", "power_mw"), "mW",
     "Average over 2 minutes of idling, summed over every process.", False),
    ("Memory 90 s after restoring the session", ("restore", "at_90s", "total_mb"), "MB",
     "Cold launch with the saved 50-tab session.", False),
]
CONTROL_PANELS = [
    ("Idle CPU, blank tab on screen", ("idle_loaded", "cpu_percent"), "%",
     "Control run: every window shows a blank tab, so only background tabs cost CPU. "
     "% of one core.", False),
    ("Idle power, blank tab on screen", ("idle_loaded", "power_mw"), "mW",
     "Same control run, average over 2 minutes.", False),
]


def get(d, *path):
    for k in path:
        if not isinstance(d, dict) or k not in d:
            return None
        d = d[k]
    return d


def tooltip(run, path):
    base = get(run, *path[:-1]) or {}
    parts = []
    if "processes" in base:
        parts.append(f"{base['processes']} processes")
    renderers = get(base, "by_kind", "renderer", "count")
    if renderers is not None:
        parts.append(f"{renderers} renderer{'' if renderers == 1 else 's'}")
    if "cpu_percent" in base:
        parts.append(f"CPU {base['cpu_percent']:.1f}% of one core")
    return " · ".join(parts)


def panel(runs, title, path, unit, note, half_mark=False):
    values = [(key, name, slot, get(runs.get(key, {}), *path)) for key, name, slot in SERIES]
    measured = [v for *_, v in values if v is not None]
    top = max(measured) if measured else 1
    rows = []
    mark = '<span class="half" aria-hidden="true"></span>' if half_mark else ""
    for key, name, slot, value in values:
        if value is None:
            rows.append(f'<div class="row"><span class="label">{name}</span>'
                        f'<span class="na">not measured in this run</span></div>')
            continue
        frac = max(value / top, 0.005)
        shown = (f"{value:.1f}" if unit == "%" else "<1" if value < 1 and unit == "mW"
                 else f"{value:,.0f}")
        tip = html.escape(f"{name}: {shown} {unit}" +
                          (f" · {tooltip(runs[key], path)}" if tooltip(runs[key], path) else ""))
        rows.append(
            f'<div class="row" data-tip="{tip}"><span class="label">{name}</span>'
            f'<span class="track">{mark}<span class="bar s{slot}" style="width:calc((100% - var(--label-room)) * {frac:.4f})"></span>'
            f'<span class="value">{html.escape(shown)} {unit}</span></span></div>')
    return (f'<section><h2>{title}</h2><p class="note">{note}</p>'
            + "".join(rows) + "</section>")


def table(runs):
    rows = [
        ("Memory, all loaded", ("loaded", "total_mb"), "MB"),
        ("Processes, all loaded", ("loaded", "processes"), ""),
        ("Renderers, all loaded", ("loaded", "by_kind", "renderer", "count"), ""),
        ("Idle CPU, all loaded", ("idle_loaded", "cpu_percent"), "%"),
        ("Idle power, all loaded", ("idle_loaded", "power_mw"), "mW"),
        ("Memory after 12 min", ("after_idle", "total_mb"), "MB"),
        ("Idle CPU after 12 min", ("idle_after", "cpu_percent"), "%"),
        ("Idle power after 12 min", ("idle_after", "power_mw"), "mW"),
        ("Restore: first window", ("restore", "first_window_s"), "s"),
        ("Restore: memory at 30 s", ("restore", "at_30s", "total_mb"), "MB"),
        ("Restore: memory at 90 s", ("restore", "at_90s", "total_mb"), "MB"),
    ]
    head = "".join(f"<th>{name}</th>" for _, name, _ in SERIES)
    body = []
    for label, path, unit in rows:
        cells = []
        for key, _, _ in SERIES:
            v = get(runs.get(key, {}), *path)
            if v is None:
                cells.append("<td>–</td>")
            elif unit in ("%", "s"):
                cells.append(f"<td>{v:.2f} {unit}</td>" if unit == "s" else f"<td>{v:.1f}%</td>")
            elif unit == "mW" and v < 1:
                cells.append("<td>&lt;1 mW</td>")
            else:
                cells.append(f"<td>{v:,.0f} {unit}</td>")
        body.append(f"<tr><th scope=row>{label}</th>{''.join(cells)}</tr>")
    return f"<table><thead><tr><th></th>{head}</tr></thead><tbody>{''.join(body)}</tbody></table>"


INLINE_CSS = """
.viz-root.inline { background:transparent; padding:0; color:var(--foreground, var(--text-primary));
  font-family:var(--font-sans, -apple-system, sans-serif); }
.inline .sub, .inline .note, .inline .label, .inline .legend, .inline .na, .inline summary,
.inline th[scope=row], .inline thead th:first-child, .inline .foot {
  color:var(--muted-foreground, var(--text-secondary)); }
.inline section, .inline th, .inline td { border-color:var(--border, var(--rule)); }
.inline .half { border-left-color:var(--muted-foreground, var(--text-secondary)); }
.inline .value { background:var(--background, transparent); }
.inline #tip { background:var(--popover, var(--surface-2)); color:var(--popover-foreground, inherit);
  border-color:var(--border, var(--rule)); }
"""

# Picks the dark palette steps when the host page is dark.
INLINE_JS = """
const bg = getComputedStyle(document.documentElement).getPropertyValue('--background').trim();
if (bg) {
  const probe = document.createElement('div'); probe.style.color = bg; document.body.appendChild(probe);
  const [r, g, b] = getComputedStyle(probe).color.match(/[\\d.]+/g).map(Number); probe.remove();
  document.documentElement.dataset.theme = (0.2126*r + 0.7152*g + 0.0722*b) / 255 < 0.5 ? 'dark' : 'light';
}
"""

CSS = """
.viz-root { color-scheme: light; --surface-1:#fcfcfb; --surface-2:#f1f0ec; --text-primary:#0b0b0b;
  --text-secondary:#52514e; --rule:#e2e1dc; --series-1:#2a78d6; --series-2:#eb6834; --series-3:#1baf7a; }
@media (prefers-color-scheme: dark) { :root:where(:not([data-theme="light"])) .viz-root {
  color-scheme: dark; --surface-1:#1a1a19; --surface-2:#262624; --text-primary:#f0efec;
  --text-secondary:#c3c2b7; --rule:#3a3a37; --series-1:#3987e5; --series-2:#d95926; --series-3:#199e70; } }
:root[data-theme="dark"] .viz-root { color-scheme: dark; --surface-1:#1a1a19; --surface-2:#262624;
  --text-primary:#f0efec; --text-secondary:#c3c2b7; --rule:#3a3a37; --series-1:#3987e5;
  --series-2:#d95926; --series-3:#199e70; }
body { margin:0; }
.viz-root { background:var(--surface-1); color:var(--text-primary); padding:28px 32px 40px;
  font:14px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
h1 { font-size:20px; margin:0 0 4px; } h2 { font-size:15px; margin:0 0 2px; }
.sub, .note { color:var(--text-secondary); margin:0 0 14px; } .note { font-size:12.5px; margin-bottom:12px; }
.legend { display:flex; gap:18px; margin:14px 0 22px; color:var(--text-secondary); font-size:13px; }
.legend span::before { content:""; display:inline-block; width:10px; height:10px; border-radius:3px;
  margin-right:6px; vertical-align:-1px; background:var(--c); }
.grid { display:grid; grid-template-columns:repeat(auto-fit, minmax(320px, 1fr)); gap:28px 40px; }
section { border-top:1px solid var(--rule); padding-top:14px; }
.row { display:grid; grid-template-columns:132px 1fr; align-items:center; min-height:30px; }
.label { color:var(--text-secondary); font-size:13px; }
.track { position:relative; display:flex; align-items:center; gap:8px; --label-room:84px; }
.bar { height:18px; border-radius:0 4px 4px 0; display:block; flex-shrink:0; }
.half { position:absolute; left:calc((100% - var(--label-room)) * 0.5); top:-6px; bottom:-6px;
  border-left:1px dashed var(--text-secondary); opacity:.6; }
.s1 { background:var(--series-1); } .s2 { background:var(--series-2); } .s3 { background:var(--series-3); }
.value { font-variant-numeric:tabular-nums; font-size:13px; white-space:nowrap;
  position:relative; z-index:1; padding:0 4px; margin-left:-4px; background:var(--surface-1); }
.na { color:var(--text-secondary); font-size:12.5px; font-style:italic; }
.row[data-tip] { cursor:default; } .row[data-tip]:hover .bar { filter:brightness(1.08); }
#tip { position:fixed; pointer-events:none; background:var(--surface-2); color:var(--text-primary);
  border:1px solid var(--rule); border-radius:8px; padding:6px 10px; font-size:12.5px; display:none;
  box-shadow:0 4px 14px rgba(0,0,0,.12); max-width:360px; }
details { margin-top:30px; } summary { cursor:pointer; color:var(--text-secondary); }
table { border-collapse:collapse; margin-top:12px; font-variant-numeric:tabular-nums; font-size:13px; }
th, td { padding:6px 14px; border-bottom:1px solid var(--rule); text-align:right; }
th[scope=row], thead th:first-child { text-align:left; color:var(--text-secondary); font-weight:500; }
.foot { color:var(--text-secondary); font-size:12.5px; margin-top:22px; max-width:900px; }
"""

JS = """
const tip = document.getElementById('tip');
document.querySelectorAll('.row[data-tip]').forEach(row => {
  row.addEventListener('mousemove', e => {
    tip.textContent = row.dataset.tip; tip.style.display = 'block';
    tip.style.left = (e.clientX + 14) + 'px'; tip.style.top = (e.clientY + 12) + 'px';
  });
  row.addEventListener('mouseleave', () => tip.style.display = 'none');
});
"""


def main():
    args = sys.argv[1:]
    inline = "--inline" in args
    args = [a for a in args if a != "--inline"]
    out = None
    if "-o" in args:
        i = args.index("-o")
        out = args[i + 1]
        del args[i:i + 2]
    src = args[0] if args else sorted(
        f for f in glob.glob(os.path.join(ROOT, "results", "*.json"))
        if not os.path.basename(f).startswith("trials-"))[-1]
    with open(src) as f:
        results = json.load(f)
    runs = results["runs"]
    control_runs = {}
    if len(args) > 1:
        with open(args[1]) as f:
            ctl = json.load(f)["runs"]
        control_runs = {key: ctl[c] for key, c in CONTROL.items() if c in ctl}
    out = out or os.path.splitext(src)[0] + (".inline.html" if inline else ".html")

    legend = "".join(f'<span style="--c:var(--series-{slot})">{name}</span>'
                     for _, name, slot in SERIES)
    panels = "".join(panel(runs, *p) for p in PANELS)
    if control_runs:
        panels += "".join(panel(control_runs, *p) for p in CONTROL_PANELS)
    title = "" if inline else "<h1>MBGA vs Chrome: 3 profiles, 50 tabs</h1>"
    page = f"""<!doctype html><html><head><meta charset="utf-8">
<title>MBGA vs Chrome: 3 profiles, 50 tabs</title>
<style>{CSS}{INLINE_CSS if inline else ""}</style></head>
<body><div class="viz-root{' inline' if inline else ''}">
{title}
<p class="sub">{results['date']} · Chrome {results['chrome_version']} (fresh profile) · MBGA on
Chromium 154 · Apple M1 Max, 64 GB · physical memory footprint summed over every process</p>
<div class="legend">{legend}</div>
<div class="grid">{panels}</div>
<details><summary>All measurements as a table</summary>{table(runs)}</details>
<p class="foot">Same 50 URLs in both browsers, split over three profiles (MBGA: favorites, pinned
tabs and folders, Today tabs; Chrome: one window per profile). Real sites, so page content
varies between runs. Arc itself was not measured; Chrome stands in as a stock Chromium browser.</p>
<div id="tip" role="tooltip"></div></div>
<script>{INLINE_JS if inline else ""}{JS}</script></body></html>"""
    with open(out, "w") as f:
        f.write(page)
    print(out)


if __name__ == "__main__":
    main()
