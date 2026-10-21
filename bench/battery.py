"""Battery scenarios on local test pages (bench/pages), identical for every
browser and every run:

battery-static      A plain article on screen.
battery-busy        An ad-heavy news page on screen: ticker, spinner, animated
                    banner, analytics timers, two cross-site ad frames (one
                    animated, one with a muted looping video).
battery-video       A 1080p VP9 video playing.
battery-background  Ten busy pages in background tabs with the plain article
                    on screen; measured early (0:30-2:30) and late (6:00-8:00,
                    after Chromium's 5-minute intensive timer throttling).
"""

import os
import time

from browsers import MBGA
from common import (DEVTOOLS_PORT, WORK, DevTools, activate, log, measure_window, page_targets,
                    page_url, sleep_until, wait_for_window, window_bounds)

WINDOW = 120
SETTLE = 30
if os.environ.get("BENCH_QUICK"):
    WINDOW, SETTLE = 10, 5

BACKGROUND_TABS = 10


def pages(scenario):
    """(background pages, page on screen)."""
    if scenario == "battery-background":
        return [page_url(f"busy.html?tab={i}") for i in range(BACKGROUND_TABS)], page_url("static.html")
    return [], page_url(scenario.split("-", 1)[1] + ".html")


def run(browser, scenario):
    background, front = pages(scenario)
    data = os.path.join(WORK, f"{browser.key}-{scenario}")
    is_mbga = browser.key == "mbga"
    # DevTools is only used after measuring, to check the pages did what the
    # scenario needs.
    if is_mbga:
        MBGA.prepare(data, [{"space": "Bench", "today": background + [front]}])
        proc = MBGA.launch(data, devtools=True)
    else:
        browser.prepare(data)
        # Chromium shows the first URL given on the command line.
        proc = browser.launch(data, [front] + background, devtools=True)
    result = {"first_window_s": wait_for_window(proc.pid)}
    time.sleep(2)
    if is_mbga and background:
        # Visiting each tab loads it; the last one (the article) stays on screen.
        MBGA.select_every_tab([len(background) + 1])
    activate(proc.pid)
    t0 = time.time()
    result["window"] = window_bounds(proc.pid)
    log(f"{browser.key} {scenario}: settling")

    if scenario == "battery-background":
        sleep_until(t0, SETTLE)
        result["early"] = measure_window(proc.pid, WINDOW)
        sleep_until(t0, 6 * 60 if WINDOW >= 60 else 60)
        result["late"] = measure_window(proc.pid, WINDOW)
        summary = (f"early {result['early']['power_mw']:.0f} mW, "
                   f"late {result['late']['power_mw']:.0f} mW")
    else:
        sleep_until(t0, SETTLE)
        result["idle"] = measure_window(proc.pid, WINDOW)
        summary = (f"{result['idle']['power_mw']:.0f} mW, {result['idle']['cpu_percent']:.1f}% CPU, "
                   f"{result['idle']['gpu_percent']:.1f}% GPU, "
                   f"impact {result['idle']['energy_impact']:.1f}")
    result["check"] = check(proc.pid, scenario, front)
    log(f"{browser.key} {scenario}: {summary}; check {result['check']}")
    browser.quit(proc)
    time.sleep(3)
    return result


CHECKS = {
    "battery-static": "true",
    "battery-busy": "new Promise(r => { let n = 0; const f = () => ++n < 30 ? "
                    "requestAnimationFrame(f) : r(true); requestAnimationFrame(f); "
                    "setTimeout(() => r(n), 2000); })",
    "battery-video": "new Promise(r => { const v = document.querySelector('video'); "
                     "const t = v.currentTime; setTimeout(() => r(!v.paused && v.currentTime != t), 500); })",
    "battery-background": "true",
}


def check(pid, scenario, front):
    """The page on screen is visible and doing its thing, and (for the
    background scenario) every background page is still loaded."""
    devtools = DevTools(DEVTOOLS_PORT, pid, match=front)
    try:
        visible = devtools.evaluate("document.visibilityState") == "visible"
        works = devtools.evaluate(CHECKS[scenario], await_promise=True) is True
    finally:
        devtools.close()
    out = {"front_visible": visible, "works": works}
    if scenario == "battery-background":
        out["background_pages"] = sum(1 for t in page_targets(DEVTOOLS_PORT) if "busy.html" in t["url"])
    out["ok"] = visible and works and out.get("background_pages", BACKGROUND_TABS) == BACKGROUND_TABS
    if not out["ok"]:
        log(f"WARNING: {scenario} page check failed, the measurement is not valid: {out}")
    return out
