#!/usr/bin/env python3
"""Prints a Markdown comparison of a bench/run.py results file.

Usage: bench/report.py [results.json]   (default: newest in bench/results)
"""

import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
COLUMNS = [("chrome", "Chrome"), ("mbga-awake", "MBGA, sleeping off"),
           ("mbga-default", "MBGA, defaults")]


def get(run, *path):
    for key in path:
        if not isinstance(run, dict) or key not in run:
            return None
        run = run[key]
    return run


def fmt(value, unit):
    if value is None:
        return "–"
    if unit == "MB":
        return f"{value:,.0f} MB"
    if unit == "%":
        return f"{value:.1f}%"
    if unit == "mW":
        return f"{value:,.0f} mW"
    if unit == "s":
        return f"{value:.2f} s"
    return f"{value:,.0f}"


ROWS = [
    ("**All 50 tabs loaded** (90 s after the last tab opened)", None, None),
    ("Memory", ("loaded", "total_mb"), "MB"),
    ("Processes", ("loaded", "processes"), ""),
    ("Renderer processes", ("loaded", "by_kind", "renderer", "count"), ""),
    ("Idle CPU (% of one core)", ("idle_loaded", "cpu_percent"), "%"),
    ("Idle power", ("idle_loaded", "power_mw"), "mW"),
    ("Idle wakeups per second", ("idle_loaded", "wakeups_per_s"), ""),
    ("**After 12 minutes untouched**", None, None),
    ("Memory", ("after_idle", "total_mb"), "MB"),
    ("Processes", ("after_idle", "processes"), ""),
    ("Idle CPU (% of one core)", ("idle_after", "cpu_percent"), "%"),
    ("Idle power", ("idle_after", "power_mw"), "mW"),
    ("**Restoring the 50-tab session** (cold launch)", None, None),
    ("First window on screen", ("restore", "first_window_s"), "s"),
    ("Memory after 30 s", ("restore", "at_30s", "total_mb"), "MB"),
    ("Memory after 90 s", ("restore", "at_90s", "total_mb"), "MB"),
]


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else sorted(
        f for f in glob.glob(os.path.join(ROOT, "results", "*.json"))
        if not os.path.basename(f).startswith("trials-"))[-1]
    with open(path) as f:
        results = json.load(f)
    runs = results["runs"]
    cols = [(key, title) for key, title in COLUMNS if key in runs]

    print(f"Benchmark of {results['date']}: 3 profiles, 50 tabs. "
          f"Chrome {results['chrome_version']}, fresh profile.\n")
    print("| | " + " | ".join(title for _, title in cols) + " |")
    print("|---|" + "---:|" * len(cols))
    for label, path_, unit in ROWS:
        if path_ is None:
            print(f"| {label} |" + " |" * len(cols))
            continue
        cells = [fmt(get(runs[key], *path_), unit) for key, _ in cols]
        if all(c == "–" for c in cells):
            continue
        print(f"| {label} | " + " | ".join(cells) + " |")

    print("\nMemory by process type with all tabs loaded:\n")
    kinds = sorted({k for key, _ in cols for k in (get(runs[key], "loaded", "by_kind") or {})})
    print("| Process type | " + " | ".join(title for _, title in cols) + " |")
    print("|---|" + "---:|" * len(cols))
    for kind in kinds:
        cells = []
        for key, _ in cols:
            k = get(runs[key], "loaded", "by_kind", kind)
            cells.append(f"{k['mb']:,.0f} MB ({k['count']})" if k else "–")
        print(f"| {kind} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
