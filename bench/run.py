#!/usr/bin/env python3
"""MBGA vs Google Chrome under a heavy, identical workload.

Workload: 3 profiles, 50 tabs (favorites, pinned tabs, pinned folders and
Today tabs in MBGA; one window per profile in Chrome). Every browser runs
alone, from a throwaway data directory under /tmp, and is measured over its
whole process tree with bench/sample (physical footprint, CPU, energy).

Runs:
  chrome        Chrome defaults: load, idle 12 min, quit, restore session.
  mbga-awake    MBGA with tab sleeping off (every tab stays loaded): load,
                idle 12 min, quit, restore session.
  mbga-default  MBGA defaults: load, idle 12 min (tab sleeping on).

  chrome-control, mbga-awake-control
                Load + idle CPU only, with a blank tab on screen in every window,
                so CPU and power compare background tabs only.

Usage: bench/run.py [run ...]     (default: the first three, ~40 minutes)
Results: bench/results/<timestamp>.json
"""

import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "build", "bench-tools")
WORK = "/tmp/mbga-bench"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
MBGA_APP = os.path.join(ROOT, "build", "cmake", "out", "MBGA.app")
MBGA = os.path.join(MBGA_APP, "Contents", "MacOS", "MBGA")

SETTLE = 90          # seconds between the last tab opening and "loaded"
IDLE_WINDOW = 120    # seconds of idle CPU/energy sampling
IDLE_MARK = 12 * 60  # "after idle" sample, counted from the last tab opening
if os.environ.get("BENCH_QUICK"):  # smoke test of the mechanics only
    SETTLE, IDLE_WINDOW, IDLE_MARK = 15, 10, 60

# Keycodes (layout independent).
KEY_TAB, KEY_Q = 48, 12
KEY_DIGITS = [18, 19, 20, 21, 23, 22, 26, 28, 25]

W = "https://en.wikipedia.org/wiki/"
WORKLOAD = [
    {
        "profile": "Personal", "space": "Home", "icon": "🏠", "color": 0x8B5CF6,
        "favorites": ["https://www.youtube.com/", "https://x.com/",
                      "https://www.spotify.com/", "https://www.netflix.com/"],
        "folders": {"News": ["https://www.bbc.com/news", "https://www.bbc.com/sport",
                             "https://arstechnica.com/", "https://techcrunch.com/"]},
        "pinned": ["https://www.google.com/maps/search/coffee+near+san+francisco"],
        "today": ["https://www.youtube.com/watch?v=aqz-KE-bpKQ", "https://www.amazon.com/",
                  "https://www.amazon.com/s?k=mechanical+keyboard", "https://www.imdb.com/",
                  "https://www.imdb.com/chart/top/", "https://www.twitch.tv/",
                  "https://www.twitch.tv/directory", "https://maps.google.com/"],
    },
    {
        "profile": "Work", "space": "Work", "icon": "💼", "color": 0x3B82F6,
        "favorites": ["https://github.com/", "https://linear.app/",
                      "https://stripe.com/", "https://www.google.com/"],
        "folders": {"Repos": ["https://github.com/rust-lang/rust",
                              "https://github.com/chromiumembedded/cef",
                              "https://github.com/torvalds/linux", "https://github.com/apple/swift",
                              "https://github.com/microsoft/vscode",
                              "https://github.com/facebook/react"]},
        "pinned": ["https://news.ycombinator.com/", "https://lobste.rs/"],
        "today": ["https://news.ycombinator.com/newest", "https://www.cloudflare.com/",
                  "https://tailwindcss.com/", "https://nodejs.org/en",
                  "https://www.google.com/search?q=chromium+embedded+framework"],
    },
    {
        "profile": "Research", "space": "Research", "icon": "📚", "color": 0x10B981,
        "favorites": ["https://www.wikipedia.org/", "https://www.apple.com/",
                      "https://www.microsoft.com/"],
        "folders": {"Wiki": [W + "Web_browser", W + "Chromium_(web_browser)",
                             W + "Rust_(programming_language)",
                             W + "Swift_(programming_language)", W + "MacOS"]},
        "pinned": ["https://archive.org/"],
        "today": [W + "Linux", W + "Internet", W + "Arc_(web_browser)", W + "Apple_silicon",
                  W + "WebKit", "https://www.producthunt.com/", "https://archive.org/details/texts"],
    },
]


def urls(space):
    folder_tabs = [u for tabs in space["folders"].values() for u in tabs]
    return space["favorites"] + folder_tabs + space["pinned"] + space["today"]


ALL_URLS = [u for s in WORKLOAD for u in urls(s)]
assert len(ALL_URLS) == 50, len(ALL_URLS)


# ---------------------------------------------------------------- utilities

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def build_tools():
    os.makedirs(TOOLS, exist_ok=True)
    for name in ["sample", "windows", "key"]:
        out = os.path.join(TOOLS, name)
        src = os.path.join(ROOT, "bench", f"{name}.swift")
        if not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(src):
            subprocess.run(["swiftc", "-O", src, "-o", out], check=True)


def sample(pid):
    out = subprocess.run([os.path.join(TOOLS, "sample"), str(pid)],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def summarize(s):
    """Memory by process kind, in MB."""
    kinds = {}
    for p in s["procs"]:
        kind = p["type"].split(":")[0]  # browser, renderer, gpu-process, utility, ...
        k = kinds.setdefault(kind, {"count": 0, "mb": 0.0})
        k["count"] += 1
        k["mb"] += p["footprint"] / 2**20
    return {"total_mb": s["footprint"] / 2**20, "processes": s["count"], "by_kind": kinds}


def idle_window(pid, seconds=IDLE_WINDOW):
    """Average CPU (% of one core), power and wakeups while nobody touches it."""
    a = sample(pid)
    time.sleep(seconds)
    b = sample(pid)
    before = {p["pid"]: p for p in a["procs"]}
    cpu = energy = 0
    for p in b["procs"]:
        q = before.get(p["pid"], {"cpu_ns": 0, "energy_nj": 0})
        cpu += p["cpu_ns"] - q["cpu_ns"]
        energy += p["energy_nj"] - q["energy_nj"]
    elapsed = b["t"] - a["t"]
    return {
        "seconds": round(elapsed, 1),
        "cpu_percent": cpu / (elapsed * 1e9) * 100,
        "power_mw": energy / elapsed / 1e6,
        "wakeups_per_s": (b["wakeups"] - a["wakeups"]) / elapsed,
        "memory": summarize(b),
    }


def wait_for_window(pid, timeout=30):
    start = time.time()
    while time.time() - start < timeout:
        out = subprocess.run([os.path.join(TOOLS, "windows"), str(pid)],
                             capture_output=True, text=True).stdout.strip()
        if out and int(out) > 0:
            return time.time() - start
        time.sleep(0.05)
    return None


def sleep_until(t0, offset):
    remaining = t0 + offset - time.time()
    if remaining > 0:
        time.sleep(remaining)


def wait_exit(proc, timeout=30):
    try:
        proc.wait(timeout)
    except subprocess.TimeoutExpired:
        log("did not exit in time, killing")
        proc.kill()
        proc.wait()


# ------------------------------------------------------------------- Chrome

CHROME_FLAGS = ["--no-first-run", "--no-default-browser-check",
                "--window-size=1280,820", "--window-position=224,99"]


def chrome_prepare(data):
    shutil.rmtree(data, ignore_errors=True)
    for i, space in enumerate(WORKLOAD, 1):
        prefs_dir = os.path.join(data, f"Profile {i}")
        os.makedirs(prefs_dir)
        # "Continue where you left off", so the restore test reopens all tabs.
        with open(os.path.join(prefs_dir, "Preferences"), "w") as f:
            json.dump({"session": {"restore_on_startup": 1},
                       "profile": {"name": space["profile"]}}, f)


def run_chrome(control=False):
    """control=True: each window's front tab is blank and only load + idle
    CPU are measured, so visible pages don't skew CPU and power."""
    data = os.path.join(WORK, "chrome")
    front = ["about:blank"] if control else []
    chrome_prepare(data)
    base = [CHROME, f"--user-data-dir={data}", *CHROME_FLAGS]
    result = {}

    log("chrome: launching 3 profiles with 50 tabs")
    t_launch = time.time()
    proc = subprocess.Popen(base + ["--profile-directory=Profile 1", *front, *urls(WORKLOAD[0])],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result["first_window_s"] = wait_for_window(proc.pid)
    time.sleep(2)
    for i in (2, 3):
        # Hands the URLs to the running instance and exits.
        subprocess.run(base + [f"--profile-directory=Profile {i}", *front, *urls(WORKLOAD[i - 1])],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    t0 = time.time()
    log(f"chrome: all tabs opened after {t0 - t_launch:.1f}s")

    sleep_until(t0, SETTLE)
    result["loaded"] = summarize(sample(proc.pid))
    log(f"chrome: loaded {result['loaded']['total_mb']:.0f} MB")
    result["idle_loaded"] = idle_window(proc.pid)
    if control:
        quit_chrome(proc)
        return result
    sleep_until(t0, IDLE_MARK)
    result["after_idle"] = summarize(sample(proc.pid))
    log(f"chrome: after idle {result['after_idle']['total_mb']:.0f} MB")
    result["idle_after"] = idle_window(proc.pid)

    with open(os.path.join(data, "Local State")) as f:
        local_state = json.load(f)
    result["memory_saver_state"] = (local_state.get("performance_tuning", {})
                                    .get("high_efficiency_mode", {}).get("state"))

    log("chrome: quitting (SIGTERM saves the session)")
    proc.terminate()
    wait_exit(proc)
    time.sleep(3)
    # Reopens each profile's last session, as a user reopening 3 windows (a
    # plain launch shows the profile picker when several profiles exist).
    flags = base + ["--restore-last-session"]

    def launch():
        return subprocess.Popen(flags + ["--profile-directory=Profile 1"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def open_other_profiles(proc):
        time.sleep(4)
        for i in (2, 3):
            subprocess.run(flags + [f"--profile-directory=Profile {i}"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            time.sleep(2)

    result["restore"] = restore(launch, quit_chrome, open_other_profiles)
    return result


def quit_chrome(proc):
    proc.terminate()
    wait_exit(proc)


# --------------------------------------------------------------------- MBGA

def mbga_state(sleep_after_secs, max_live_tabs, blank_last=False):
    """Writes the workload as an MBGA state file."""
    next_id = 1

    def alloc():
        nonlocal next_id
        next_id += 1
        return next_id - 1

    state = {"version": 1, "profiles": [], "favorites": {}, "spaces": [], "tabs": {},
             "policy": {"sleep_after_secs": sleep_after_secs, "max_live_tabs": max_live_tabs},
             "search_template": "https://www.google.com/search?q=%s", "doomed_profiles": []}

    def tab(url, pinned):
        tid = alloc()
        state["tabs"][str(tid)] = {"id": tid, "url": url, "title": "", "favicon": None,
                                   "pinned_url": url if pinned else None, "last_active_ms": 0}
        return tid

    for space in WORKLOAD:
        pid = alloc()
        state["profiles"].append({"id": pid, "name": space["profile"]})
        favs = [tab(u, True) for u in space["favorites"]]
        state["favorites"][str(pid)] = favs
        pinned = []
        for name, tabs in space["folders"].items():
            pinned.append({"kind": "folder", "id": alloc(), "name": name, "expanded": True,
                           "children": [{"kind": "tab", "id": tab(u, True)} for u in tabs]})
        pinned += [{"kind": "tab", "id": tab(u, True)} for u in space["pinned"]]
        today = [tab(u, False) for u in space["today"]]
        if blank_last and space is WORKLOAD[-1]:
            today.append(tab("about:blank", False))  # last in order: on screen at the end
        sid = alloc()
        state["spaces"].append({"id": sid, "name": space["space"], "icon": space["icon"],
                                "color": space["color"], "profile_id": pid, "pinned": pinned,
                                "today": today, "active_tab": favs[0]})
    state["active_space"] = state["spaces"][0]["id"]
    state["next_id"] = next_id
    return state


def mbga_prepare(data, **policy):
    shutil.rmtree(data, ignore_errors=True)
    os.makedirs(data)
    with open(os.path.join(data, "state.json"), "w") as f:
        json.dump(mbga_state(**policy), f)


def mbga_launch(data):
    return subprocess.Popen([MBGA], env={**os.environ, "MBGA_DATA_DIR": data},
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def mbga_key(code, *mods):
    for _ in range(3):
        subprocess.run(["open", "-a", MBGA_APP])
        time.sleep(0.3)
        if subprocess.run([os.path.join(TOOLS, "key"), str(code), *mods]).returncode == 0:
            return
    raise RuntimeError("could not bring MBGA to the front")


def mbga_open_all_tabs(extra_last=0):
    """Selects every tab once (each selection loads it), space by space."""
    for i, space in enumerate(WORKLOAD):
        mbga_key(KEY_DIGITS[i], "ctrl")
        time.sleep(1.0)
        extra = extra_last if i == len(WORKLOAD) - 1 else 0
        for _ in range(len(urls(space)) - 1 + extra):
            mbga_key(KEY_TAB, "ctrl")
            time.sleep(0.4)


def quit_mbga(proc):
    mbga_key(KEY_Q, "cmd")
    wait_exit(proc)


def loaded_titles(data):
    with open(os.path.join(data, "state.json")) as f:
        tabs = json.load(f)["tabs"].values()
    return sum(1 for t in tabs if t["title"])


def run_mbga(name, sleep_after_secs, max_live_tabs, idle, restore_test, control=False,
             idle_cpu=True, late_sample=0):
    data = os.path.join(WORK, name)
    mbga_prepare(data, sleep_after_secs=sleep_after_secs, max_live_tabs=max_live_tabs,
                 blank_last=control)
    result = {}
    log(f"{name}: launching")
    proc = mbga_launch(data)
    result["first_window_s"] = wait_for_window(proc.pid)
    time.sleep(3)
    log(f"{name}: opening all 50 tabs")
    mbga_open_all_tabs(extra_last=1 if control else 0)
    t0 = time.time()

    sleep_until(t0, SETTLE)
    result["loaded"] = summarize(sample(proc.pid))
    result["tabs_with_title"] = loaded_titles(data)
    # Profiles that fail to open fall back to shared in-memory storage, which
    # would make the measurement meaningless.
    log_path = os.path.join(data, "engine", "engine.log")
    errors = open(log_path).read().count("Cannot create profile") if os.path.exists(log_path) else 0
    if errors:
        raise RuntimeError(f"{errors} profiles failed to open; see {log_path}")
    log(f"{name}: loaded {result['loaded']['total_mb']:.0f} MB, "
        f"{result['tabs_with_title']}/50 tabs reported a title")
    if late_sample:
        sleep_until(t0, late_sample)
        result["late"] = summarize(sample(proc.pid))
    if idle_cpu:
        result["idle_loaded"] = idle_window(proc.pid)
    if idle:
        sleep_until(t0, IDLE_MARK)
        result["after_idle"] = summarize(sample(proc.pid))
        log(f"{name}: after idle {result['after_idle']['total_mb']:.0f} MB")
        result["idle_after"] = idle_window(proc.pid)

    quit_mbga(proc)
    time.sleep(3)
    if restore_test:
        result["restore"] = restore(lambda: mbga_launch(data), quit_mbga)
    return result


# ------------------------------------------------------------------ restore

def restore(launch, quit, after_window=None):
    """Cold launch with the saved 50-tab session."""
    t = time.time()
    proc = launch()
    first = wait_for_window(proc.pid)
    if after_window:
        after_window(proc)
    out = {"first_window_s": first}
    for mark in (30, 90):
        sleep_until(t, mark)
        out[f"at_{mark}s"] = summarize(sample(proc.pid))
    log(f"restore: window {first}s, {out['at_90s']['total_mb']:.0f} MB at 90s")
    quit(proc)
    time.sleep(3)
    return out


# --------------------------------------------------------------------- main

def main():
    runs = sys.argv[1:] or ["chrome", "mbga-awake", "mbga-default"]
    build_tools()
    os.makedirs(WORK, exist_ok=True)
    chrome_version = subprocess.run(
        ["defaults", "read", "/Applications/Google Chrome.app/Contents/Info.plist",
         "CFBundleShortVersionString"], capture_output=True, text=True).stdout.strip()
    results = {"date": time.strftime("%Y-%m-%d %H:%M"), "chrome_version": chrome_version,
               "workload": {"profiles": 3, "tabs": 50, "urls": ALL_URLS}, "runs": {}}
    for run in runs:
        if run == "chrome":
            results["runs"][run] = run_chrome()
        elif run == "mbga-awake":
            results["runs"][run] = run_mbga(run, 10**8, 1000, idle=True, restore_test=True)
        elif run == "chrome-control":
            results["runs"][run] = run_chrome(control=True)
        elif run == "mbga-awake-control":
            results["runs"][run] = run_mbga(run, 10**8, 1000, idle=False, restore_test=False,
                                            control=True)
        elif run == "mbga-trial":
            # Quick A/B of engine options passed through MBGA_ENGINE_SWITCHES.
            results["runs"][run] = run_mbga(run, 10**8, 1000, idle=False, restore_test=False,
                                            idle_cpu=False)
            results["runs"][run]["switches"] = os.environ.get("MBGA_ENGINE_SWITCHES", "")
        elif run == "mbga-default":
            results["runs"][run] = run_mbga(run, 600, 8, idle=True, restore_test=False)
        else:
            raise SystemExit(f"unknown run {run}")
    out_dir = os.path.join(ROOT, "bench", "results")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, time.strftime("%Y%m%d-%H%M%S") + ".json")
    with open(path, "w") as f:
        json.dump(results, f, indent=2)
    log(f"results written to {path}")
    shutil.rmtree(WORK, ignore_errors=True)


if __name__ == "__main__":
    main()
