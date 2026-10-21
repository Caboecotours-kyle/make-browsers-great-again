# Benchmarks

Tools for measuring MBGA's memory, CPU and power against Google Chrome on a
heavy, identical workload: 3 profiles and 50 real sites, laid out in MBGA as
favorites, pinned tabs, pinned folders and Today tabs, and in Chrome as one
window per profile.

Every browser runs alone from a throwaway data directory under `/tmp`, so your
own browsing data is never touched. Memory is the physical footprint (what
Activity Monitor reports as "Memory") summed over the browser's whole process
tree; CPU and energy come from the same per-process counters.

| File | Purpose |
|---|---|
| `run.py` | Full benchmark: `chrome`, `mbga-awake` (tab sleeping off), `mbga-default`, plus `*-control` runs with blank visible tabs. About 40 minutes. |
| `trials.py` | Quick A/B of engine switches, one at a time, on the same workload (about 2.5 minutes per trial). |
| `report.py` | Markdown table from a results file. |
| `chart.py` | HTML report from a results file (`--inline` for embedding). |
| `sample.swift` | Samples footprint, CPU time, energy and wakeups of a process tree. |
| `windows.swift`, `key.swift` | Window detection and key presses for driving MBGA. |

`MBGA_ENGINE_SWITCHES="--foo --bar=baz"` passes extra Chromium switches to
MBGA, which is how `trials.py` tests options without rebuilding. Feature lists
(`--enable-features`, `--disable-features`) and repeated `--js-flags` are
merged with the built-in ones.

Real sites change between runs, so single measurements vary by about ±4%.
Compare options with repeated, interleaved runs (`trials.py a b a b`).

## Results

`results/20261021-final.json` (Chrome 155 against MBGA, Apple M1 Max):

| | Chrome | MBGA, sleeping off | MBGA, defaults |
|---|---:|---:|---:|
| Memory, all 50 tabs loaded | 4,320 MB | 2,122 MB | 900 MB |
| Memory after 12 idle minutes | 4,302 MB | 2,116 MB | 681 MB |
| Processes | 65 | 11 | 6 |
| Idle CPU after 12 minutes | 18.4% | 0.4% | 0.2% |
| Idle power after 12 minutes | 202 mW | 3 mW | <1 mW |
| Memory 90 s after restoring the session | 1,659 MB | 254 MB | – |
| First window when restoring | 0.79 s | 1.04 s | – |

## What was tried

Effects are relative to the configuration at the time, averaged over repeated
runs. Early rounds ran before a bug was fixed that made every profile fall
back to shared in-memory storage, so treat those effects as indicative; the
final configuration was re-measured with real profiles.

Kept as defaults:

| Option | Effect |
|---|---|
| Shared renderer processes (`--disable-features=SitePerProcess`, `--renderer-process-limit=4`, sign-in origins isolated) | Largest single saving. Strict isolation measured +29% with real profiles. |
| Network service in the browser process (`NetworkServiceInProcess2`) | About −120 MB: one process less and its caches shared. |
| HTTP/3 off (`--disable-quic`) | About −3.5%. |
| Cached resources not pinned (`--disable-features=MemoryCacheStrongReference`) | About −4%; holds as tabs age. |
| Purge renderers when backgrounded or when a page freezes (`MemoryPurgeInBackground`, `MemoryPurgeOnFreeze`) | About −3% to −6%, larger over time. |
| Freezing hidden Today tabs (DevTools `Page.setWebLifecycleState`) | About −2.5% memory, stops background growth, cuts idle CPU. |
| Release off-screen tiles when idle (`ReclaimPrepaintTilesWhenIdle`, `ReclaimOldPrepaintTiles`) | About −2%. |
| Low-end device mode, V8 `--optimize-for-size`, no prerendering, no spare renderer | Individually within noise, together a few percent. |

Measured and rejected:

| Option | Why |
|---|---|
| Skia Ganesh instead of Graphite | +15–19% memory. |
| PartitionAlloc hardening off (BackupRefPtr and friends) | No measurable gain; kept for use-after-free protection. |
| PartitionAlloc anti-fragmentation options | No effect. |
| V8 `--memory-saver-mode` | No effect. |
| V8 `--max-semi-space-size=1` | Within noise, costs CPU on allocation-heavy pages. |
| Disabling Media Router, Translate, phishing detection, sync | No effect. |

A simulated critical memory-pressure signal freed only ~35 MB, all of it in
the network service: what remains is live page data (JavaScript heaps and
DOM), not caches. A Chromium memory-infra dump (taken with shared processes
and QUIC off, before the cache, tile and freeze changes) showed renderers
holding 627 MB in malloc partitions of which only 426 MB was live objects, a
347 MB Blink object heap, a 334 MB V8 heap and a 189 MB resource cache (128 MB
of it script source). That slack and cache is what the purge, freeze and
cache options above go after.
