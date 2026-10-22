"""Speed:

startup      Cold launch showing the plain article, 3 times: time until the
             window is on screen, and memory 10 s after launch.
speedometer  Speedometer 3.1 (browserbench.org), read through DevTools.
"""

import os
import statistics
import time

from browsers import MBGA
from common import WORK, DevTools, activate, log, page_url, sample, sleep_until, summarize, wait_for_window

STARTUPS = 3
SPEEDOMETER = "https://browserbench.org/Speedometer3.1/?startAutomatically=true"
SPEEDOMETER_TIMEOUT = 15 * 60


def launch(browser, scenario, url, devtools=False):
    data = os.path.join(WORK, f"{browser.key}-{scenario}")
    if browser.key == "mbga":
        MBGA.prepare(data, [{"space": "Bench", "today": [url]}])
        return MBGA.launch(data, devtools=devtools)
    browser.prepare(data)
    return browser.launch(data, [url], devtools=devtools)


def run_startup(browser):
    url = page_url("static.html")
    runs = []
    for i in range(STARTUPS):
        t = time.time()
        proc = launch(browser, f"startup-{i}", url)
        first = wait_for_window(proc.pid)
        sleep_until(t, 10)
        runs.append({"first_window_s": first, "memory": summarize(sample(proc.pid))})
        browser.quit(proc)
        time.sleep(3)
    result = {
        "first_window_s": statistics.median(r["first_window_s"] for r in runs),
        "memory_mb": statistics.median(r["memory"]["total_mb"] for r in runs),
        "runs": runs,
    }
    log(f"{browser.key} startup: window {result['first_window_s']:.2f}s, {result['memory_mb']:.0f} MB")
    return result


def run_speedometer(browser):
    proc = launch(browser, "speedometer", SPEEDOMETER, devtools=True)
    wait_for_window(proc.pid)
    time.sleep(2)
    activate(proc.pid)
    devtools = DevTools(port=9555, root_pid=proc.pid, match="browserbench.org")
    t0 = time.time()
    score = None
    try:
        while time.time() - t0 < SPEEDOMETER_TIMEOUT:
            time.sleep(10)
            done = devtools.evaluate(
                "location.hash === '#summary' && document.querySelector('#result-number')?.textContent"
            )
            if done:
                score = float(done)
                break
        detail = devtools.evaluate("document.querySelector('#confidence-number')?.textContent || ''")
    finally:
        devtools.close()
        browser.quit(proc)
        time.sleep(3)
    if score is None:
        raise RuntimeError("Speedometer did not finish")
    log(f"{browser.key} speedometer: {score} {detail}")
    return {"score": score, "confidence": detail, "seconds": round(time.time() - t0)}


def run(browser, scenario):
    return run_startup(browser) if scenario == "startup" else run_speedometer(browser)
