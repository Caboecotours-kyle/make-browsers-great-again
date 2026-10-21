#!/usr/bin/env python3
"""Charts every benchmarked change against the Chromium baseline.

Reads every format-2 results file in bench/results (one per benchmark run,
labelled with the change it measured) and writes bench/results/trend.html:
one small chart per metric, MBGA's value at each change as a line, and the
latest Chromium (and Chrome, if measured) values as reference lines.

Usage: bench/trend.py [output.html]
"""

import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(HERE, "results")


def get(d, *path):
    for key in path:
        if not isinstance(d, dict) or key not in d:
            return None
        d = d[key]
    return d


def metric(group, title, unit, better, mbga_path, base_path=None, digits=0, note=""):
    return {"group": group, "title": title, "unit": unit, "better": better, "digits": digits,
            "mbga": mbga_path, "base": base_path or mbga_path, "note": note}


METRICS = [
    metric("Battery", "50 tabs, idle after 12 min", "Energy Impact", "lower",
           ("heavy", "idle_after", "energy_impact"), digits=1,
           note="Activity Monitor's Energy Impact, summed over the browser's processes"),
    metric("Battery", "50 tabs, idle after 12 min", "CPU power, mW", "lower",
           ("heavy", "idle_after", "power_mw"), digits=1),
    metric("Battery", "Plain article on screen", "Energy Impact", "lower",
           ("battery-static", "idle", "energy_impact"), digits=1),
    metric("Battery", "Ad-heavy page on screen", "Energy Impact", "lower",
           ("battery-busy", "idle", "energy_impact"), digits=1),
    metric("Battery", "Ad-heavy page on screen", "GPU busy, %", "lower",
           ("battery-busy", "idle", "gpu_percent"), digits=1),
    metric("Battery", "1080p video playing", "Energy Impact", "lower",
           ("battery-video", "idle", "energy_impact"), digits=1),
    metric("Battery", "1080p video playing", "GPU busy, %", "lower",
           ("battery-video", "idle", "gpu_percent"), digits=1),
    metric("Battery", "10 ad-heavy tabs in background, first minutes", "Energy Impact", "lower",
           ("battery-background", "early", "energy_impact"), digits=1),
    metric("Battery", "10 ad-heavy tabs in background, after 6 min", "Energy Impact", "lower",
           ("battery-background", "late", "energy_impact"), digits=1),
    metric("Memory", "50 tabs loaded", "MB", "lower", ("heavy", "loaded", "total_mb")),
    metric("Memory", "50 tabs after 12 idle min", "MB", "lower", ("heavy", "after_idle", "total_mb")),
    metric("Memory", "50 tabs after 12 min, MBGA sleeping idle tabs", "MB", "lower",
           ("heavy-sleep", "after_idle", "total_mb"), ("heavy", "after_idle", "total_mb"),
           note="MBGA with its default tab sleeping; Chromium keeps every tab"),
    metric("Memory", "90 s after restoring 50 tabs", "MB", "lower",
           ("heavy", "restore", "at_90s", "total_mb")),
    metric("Speed", "Speedometer 3.1", "score", "higher", ("speedometer", "score"), digits=1),
    metric("Speed", "Cold start to window", "seconds", "lower", ("startup", "first_window_s"),
           digits=2),
    metric("Speed", "Restoring 50 tabs, to window", "seconds", "lower",
           ("heavy", "restore", "first_window_s"), digits=2),
    metric("Speed", "Memory 10 s after a cold start", "MB", "lower", ("startup", "memory_mb")),
]


def load_runs():
    runs = []
    for path in sorted(glob.glob(os.path.join(RESULTS, "*.json"))):
        if os.path.basename(path).startswith("trials-"):
            continue
        with open(path) as f:
            data = json.load(f)
        if data.get("format") == 2:
            data["file"] = os.path.basename(path)
            runs.append(data)
    runs.sort(key=lambda r: r["date"])
    return runs


def build(runs):
    changes = [r for r in runs if "mbga" in r["results"]]
    out = {"changes": [{"label": r.get("label") or r.get("subject") or r["file"],
                        "commit": r.get("commit", ""), "date": r["date"],
                        "dirty": r.get("dirty", False)} for r in changes],
           "metrics": [], "versions": {}}
    for r in runs:
        out["versions"].update(r.get("versions", {}))
    for m in METRICS:
        series = {"mbga": [get(r["results"]["mbga"], *m["mbga"]) for r in changes]}
        for ref in ("chromium", "chrome"):
            values = [get(r["results"].get(ref, {}), *m["base"]) for r in runs]
            values = [v for v in values if v is not None]
            series[ref] = values[-1] if values else None
        if all(v is None for v in series["mbga"]) and series["chromium"] is None:
            continue
        out["metrics"].append({**{k: m[k] for k in ("group", "title", "unit", "better", "digits",
                                                    "note")}, **series})
    return out


PAGE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MBGA vs Chromium: every change</title>
<style>
.viz-root {
  color-scheme: light;
  --surface-1: #fcfcfb; --page: #f9f9f7;
  --text-primary: #0b0b0b; --text-secondary: #52514e; --muted: #898781;
  --grid: #e1e0d9; --axis: #c3c2b7; --border: rgba(11,11,11,0.10);
  --series-1: #2a78d6; --series-2: #eb6834; --series-3: #1baf7a;
  --good: #006300;
}
@media (prefers-color-scheme: dark) {
  :root:where(:not([data-theme="light"])) .viz-root {
    color-scheme: dark;
    --surface-1: #1a1a19; --page: #0d0d0d;
    --text-primary: #f0efec; --text-secondary: #c3c2b7; --muted: #898781;
    --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10);
    --series-1: #3987e5; --series-2: #d95926; --series-3: #199e70;
    --good: #0ca30c;
  }
}
:root[data-theme="dark"] .viz-root {
  color-scheme: dark;
  --surface-1: #1a1a19; --page: #0d0d0d;
  --text-primary: #f0efec; --text-secondary: #c3c2b7; --muted: #898781;
  --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10);
  --series-1: #3987e5; --series-2: #d95926; --series-3: #199e70;
  --good: #0ca30c;
}
body { margin: 0; }
.viz-root { background: var(--page); color: var(--text-primary);
  font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; padding: 20px 24px 28px; }
h1 { font-size: 20px; margin: 0 0 4px; font-weight: 650; }
.sub { color: var(--text-secondary); margin: 0 0 14px; max-width: 900px; }
.legend { display: flex; gap: 18px; flex-wrap: wrap; color: var(--text-secondary); margin: 0 0 16px; }
.legend span { display: inline-flex; align-items: center; gap: 6px; }
.key { width: 18px; height: 2px; border-radius: 1px; display: inline-block; }
h2 { font-size: 13px; text-transform: uppercase; letter-spacing: .04em; color: var(--text-secondary);
  margin: 18px 0 8px; font-weight: 600; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(270px, 1fr)); gap: 12px; }
.card { background: var(--surface-1); border: 1px solid var(--border); border-radius: 10px;
  padding: 12px 12px 6px; position: relative; }
.card h3 { font-size: 13px; font-weight: 600; margin: 0; }
.card .unit { color: var(--muted); font-size: 12px; margin: 0 0 2px; }
.card .now { font-size: 22px; font-weight: 600; margin: 2px 0 0; }
.card .vs { color: var(--text-secondary); font-size: 12px; margin-bottom: 4px; }
.card .vs b { font-weight: 600; color: var(--text-primary); }
svg { display: block; width: 100%; overflow: visible; }
svg text { fill: var(--muted); font-size: 10px; font-variant-numeric: tabular-nums; }
.tip { position: absolute; pointer-events: none; background: var(--surface-1); border: 1px solid var(--border);
  border-radius: 8px; padding: 6px 8px; font-size: 12px; box-shadow: 0 4px 14px rgba(0,0,0,.12);
  display: none; z-index: 2; min-width: 150px; }
.tip .row { display: flex; align-items: center; gap: 6px; }
.tip .row b { font-weight: 600; }
.tip .row span { color: var(--text-secondary); }
.tip .change { color: var(--text-secondary); margin-bottom: 4px; max-width: 220px; }
details { margin-top: 20px; }
summary { cursor: pointer; color: var(--text-secondary); }
table { border-collapse: collapse; margin-top: 8px; font-size: 12px; font-variant-numeric: tabular-nums; }
th, td { border-bottom: 1px solid var(--grid); padding: 4px 8px; text-align: right; white-space: nowrap; }
th:first-child, td:first-child { text-align: left; }
ol.changes { color: var(--text-secondary); padding-left: 22px; margin: 6px 0 0; }
</style>
</head>
<body>
<div class="viz-root">
  <h1>MBGA vs Chromium: every change</h1>
  <p class="sub" id="sub"></p>
  <div class="legend" id="legend"></div>
  <div id="groups"></div>
  <details><summary>Changes</summary><ol class="changes" id="changes"></ol></details>
  <details><summary>Table view</summary><div id="table"></div></details>
</div>
<script>
const DATA = __DATA__;
const NAMES = {mbga: "MBGA", chromium: "Chromium " + (DATA.versions.chromium || ""),
               chrome: "Chrome " + (DATA.versions.chrome || "")};
const COLORS = {mbga: "var(--series-1)", chromium: "var(--series-2)", chrome: "var(--series-3)"};
const fmt = (v, d) => v == null ? "–" : v.toLocaleString("en-US", {minimumFractionDigits: d, maximumFractionDigits: d});
const el = (tag, attrs = {}, text) => {
  const ns = ["svg", "line", "path", "circle", "text", "rect", "g"].includes(tag) ? "http://www.w3.org/2000/svg" : null;
  const e = ns ? document.createElementNS(ns, tag) : document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  if (text != null) e.textContent = text;
  return e;
};
const changes = DATA.changes;
document.getElementById("sub").textContent =
  `${changes.length} benchmarked change${changes.length === 1 ? "" : "s"}, latest ${changes.length ? changes[changes.length - 1].date : "–"}. ` +
  "Each change is measured on the scenarios it targets, so some charts have fewer points. " +
  "Reference lines are the latest Chromium" + (DATA.versions.chrome ? " and Chrome" : "") + " runs.";
const hasChrome = DATA.metrics.some(m => m.chrome != null);
const legend = document.getElementById("legend");
for (const k of ["mbga", "chromium"].concat(hasChrome ? ["chrome"] : [])) {
  const s = el("span"); s.append(el("i", {class: "key", style: `background:${COLORS[k]}`}), NAMES[k]);
  legend.append(s);
}
const list = document.getElementById("changes");
changes.forEach(c => list.append(el("li", {}, `${c.label}${c.commit ? " (" + c.commit + (c.dirty ? ", uncommitted" : "") + ")" : ""} · ${c.date}`)));

const W = 260, H = 120, PAD = {l: 34, r: 8, t: 8, b: 16};
function niceMax(v) {
  if (v <= 0) return 1;
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  for (const m of [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]) if (m * p >= v) return m * p;
  return 10 * p;
}
function chart(card, m) {
  const vals = m.mbga.filter(v => v != null).concat([m.chromium, m.chrome].filter(v => v != null));
  const max = niceMax(Math.max(...vals) * 1.08);
  const n = Math.max(changes.length, 1);
  const x = i => PAD.l + (n === 1 ? (W - PAD.l - PAD.r) / 2 : i * (W - PAD.l - PAD.r) / (n - 1));
  const y = v => PAD.t + (1 - v / max) * (H - PAD.t - PAD.b);
  const svg = el("svg", {viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": `${m.title}, ${m.unit}`});
  for (const t of [0, max / 2, max]) {
    svg.append(el("line", {x1: PAD.l, x2: W - PAD.r, y1: y(t), y2: y(t), stroke: t === 0 ? "var(--axis)" : "var(--grid)", "stroke-width": 1}));
    svg.append(el("text", {x: PAD.l - 5, y: y(t) + 3, "text-anchor": "end"}, fmt(t, t < 10 && t % 1 ? 1 : 0)));
  }
  for (const ref of ["chrome", "chromium"]) {
    if (m[ref] == null) continue;
    svg.append(el("line", {x1: PAD.l, x2: W - PAD.r, y1: y(m[ref]), y2: y(m[ref]), stroke: COLORS[ref], "stroke-width": 2, "stroke-linecap": "round"}));
  }
  const pts = m.mbga.map((v, i) => v == null ? null : [x(i), y(v)]).filter(Boolean);
  if (pts.length > 1) svg.append(el("path", {d: "M" + pts.map(p => p.join(",")).join("L"), fill: "none", stroke: COLORS.mbga, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round"}));
  for (const p of pts) svg.append(el("circle", {cx: p[0], cy: p[1], r: 4, fill: COLORS.mbga, stroke: "var(--surface-1)", "stroke-width": 2}));
  const cross = el("line", {y1: PAD.t, y2: H - PAD.b, stroke: "var(--axis)", "stroke-width": 1, visibility: "hidden"});
  svg.append(cross);
  const hit = el("rect", {x: PAD.l - 6, y: 0, width: W - PAD.l - PAD.r + 12, height: H, fill: "transparent", tabindex: 0});
  svg.append(hit);
  card.append(svg);
  const tip = el("div", {class: "tip"});
  card.append(tip);
  const show = i => {
    cross.setAttribute("x1", x(i)); cross.setAttribute("x2", x(i)); cross.setAttribute("visibility", "visible");
    tip.replaceChildren(el("div", {class: "change"}, changes[i] ? changes[i].label : ""));
    for (const k of ["mbga", "chromium", "chrome"]) {
      const v = k === "mbga" ? m.mbga[i] : m[k];
      if (v == null) continue;
      const row = el("div", {class: "row"});
      row.append(el("i", {class: "key", style: `background:${COLORS[k]}`}), el("b", {}, fmt(v, m.digits)), el("span", {}, NAMES[k]));
      tip.append(row);
    }
    const rect = svg.getBoundingClientRect(), scale = rect.width / W;
    tip.style.display = "block";
    const left = 12 + x(i) * scale + 10;
    tip.style.left = Math.min(left, card.clientWidth - tip.offsetWidth - 4) + "px";
    tip.style.top = (svg.offsetTop + 4) + "px";
  };
  const hide = () => { tip.style.display = "none"; cross.setAttribute("visibility", "hidden"); };
  hit.addEventListener("pointermove", e => {
    const rect = svg.getBoundingClientRect();
    const px = (e.clientX - rect.left) * W / rect.width;
    let best = 0;
    for (let i = 0; i < n; i++) if (Math.abs(x(i) - px) < Math.abs(x(best) - px)) best = i;
    show(best);
  });
  hit.addEventListener("pointerleave", hide);
  hit.addEventListener("focus", () => show(changes.length - 1));
  hit.addEventListener("blur", hide);
}
const groups = document.getElementById("groups");
for (const g of [...new Set(DATA.metrics.map(m => m.group))]) {
  groups.append(el("h2", {}, g));
  const grid = el("div", {class: "grid"});
  groups.append(grid);
  for (const m of DATA.metrics.filter(m => m.group === g)) {
    const card = el("div", {class: "card"});
    card.append(el("h3", {}, m.title), el("p", {class: "unit"}, `${m.unit}, ${m.better} is better`));
    const latest = [...m.mbga].reverse().find(v => v != null);
    card.append(el("div", {class: "now"}, latest == null ? "not measured yet" : fmt(latest, m.digits)));
    const vs = el("div", {class: "vs"});
    if (latest != null && m.chromium) {
      const ratio = latest / m.chromium;
      const b = el("b", {}, ratio >= 0.995 && ratio <= 1.005 ? "same as" : `${fmt(ratio * 100, 0)}% of`);
      vs.append(b, ` Chromium (${fmt(m.chromium, m.digits)})`);
    } else if (m.chromium != null) {
      vs.append(`Chromium ${fmt(m.chromium, m.digits)}`);
    }
    if (m.note) vs.title = m.note;
    card.append(vs);
    chart(card, m);
    grid.append(card);
  }
}
const table = el("table");
const head = el("tr");
head.append(el("th", {}, "Metric"));
changes.forEach((c, i) => head.append(el("th", {title: c.label}, `#${i + 1}`)));
head.append(el("th", {}, "Chromium"));
if (hasChrome) head.append(el("th", {}, "Chrome"));
table.append(head);
for (const m of DATA.metrics) {
  const tr = el("tr");
  tr.append(el("td", {}, `${m.title} (${m.unit})`));
  m.mbga.forEach(v => tr.append(el("td", {}, fmt(v, m.digits))));
  tr.append(el("td", {}, fmt(m.chromium, m.digits)));
  if (hasChrome) tr.append(el("td", {}, fmt(m.chrome, m.digits)));
  table.append(tr);
}
document.getElementById("table").append(table);
</script>
</body>
</html>
"""


def render(runs):
    return PAGE.replace("__DATA__", json.dumps(build(runs)).replace("</", "<\\/"))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(RESULTS, "trend.html")
    with open(out, "w") as f:
        f.write(render(load_runs()))
    print(out)


if __name__ == "__main__":
    main()
