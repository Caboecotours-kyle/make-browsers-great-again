#!/usr/bin/env python3
"""Measures engine options one at a time on the 50-tab workload.

Each trial runs MBGA with tab sleeping off, loads every tab, and records the
total footprint 90 s later. The baseline runs first and last to show drift.

Usage: bench/trials.py [name ...]    (default: all trials below)
Results: bench/results/trials-<timestamp>.json
"""

import importlib.util
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# BENCH_LATE=180 also samples 180 s after the last tab opened.
LATE = int(os.environ.get("BENCH_LATE", "0"))
spec = importlib.util.spec_from_file_location("run", os.path.join(HERE, "run.py"))
run = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run)

# Relative to MBGA's built-in defaults (shell/engine/MBEngine.mm). Earlier
# rounds measured these options one by one against the old defaults; their
# switch sets are recorded in bench/results/trials-*.json.
LEAN = ("--disable-features=MediaRouter,DialMediaRouteProvider,Translate "
        "--disable-client-side-phishing-detection --disable-sync")
TRIALS = {
    "defaults": "",
    "strict-isolation": "--site-per-process",
    "limit4": "--renderer-process-limit=4",
    "limit6": "--renderer-process-limit=6",
    "no-quic": "--disable-quic",
    "lean": LEAN,
    "limit4+no-quic": "--renderer-process-limit=4 --disable-quic",
    "limit6+no-quic": "--renderer-process-limit=6 --disable-quic",
    "limit4+no-quic+lean": "--renderer-process-limit=4 --disable-quic " + LEAN,
    "limit6+no-quic+lean": "--renderer-process-limit=6 --disable-quic " + LEAN,
}
BEST = TRIALS["limit4+no-quic"]
TRIALS.update({
    "best": BEST,
    "best+no-strong-cache": BEST + " --disable-features=MemoryCacheStrongReference",
    "best+reclaim-tiles": BEST + " --enable-features=ReclaimPrepaintTilesWhenIdle,ReclaimOldPrepaintTiles",
    "best+purge-on-freeze": BEST + " --enable-features=MemoryPurgeOnFreeze",
    "best+small-young-gen": BEST + " --js-flags=--max-semi-space-size=1",
})


def main():
    names = sys.argv[1:] or (list(TRIALS) + ["defaults"])
    run.build_tools()
    os.makedirs(run.WORK, exist_ok=True)
    results = []
    for name in names:
        os.environ["MBGA_ENGINE_SWITCHES"] = TRIALS[name]
        r = run.run_mbga("mbga-trial", 10**8, 1000, idle=False, restore_test=False,
                         idle_cpu=False, late_sample=LATE)
        loaded = r["loaded"]
        late = r.get("late", {}).get("total_mb")
        results.append({"trial": name, "switches": TRIALS[name], "total_mb": loaded["total_mb"],
                        "late_mb": late,
                        "processes": loaded["processes"], "tabs_with_title": r["tabs_with_title"],
                        "by_kind": loaded["by_kind"]})
        run.log(f"trial {name}: {loaded['total_mb']:.0f} MB, {loaded['processes']} processes"
                + (f", {late:.0f} MB at {LATE}s" if late else ""))
    out = os.path.join(HERE, "results", time.strftime("trials-%Y%m%d-%H%M%S.json"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        json.dump(results, f, indent=2)
    base = [r["total_mb"] for r in results if r["trial"] == "defaults"]
    ref = sum(base) / len(base) if base else results[0]["total_mb"]
    print(f"\n{'trial':24} {'MB':>7} {'vs base':>8} {'procs':>6}  renderer MB")
    for r in results:
        rend = r["by_kind"].get("renderer", {}).get("mb", 0)
        print(f"{r['trial']:24} {r['total_mb']:7.0f} {r['total_mb'] / ref - 1:+8.1%} "
              f"{r['processes']:6}  {rend:7.0f}")
    print(f"\nresults: {out}")


if __name__ == "__main__":
    main()
