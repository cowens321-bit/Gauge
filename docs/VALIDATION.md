# Validation

Everything below was produced on the development Mac (Apple silicon, 10 cores, 32 GB, macOS 27 beta). Nothing here is
a claim of general accuracy; it records what was compared and how it differed.

## Automated tests (`scripts/test.sh`, 55 tests, all passing)
* **CPU deltas** – single/multi‑core, first sample, non‑advancing clock, counters going backwards, disk and energy rates.
* **PID reuse** – same pid with a later start time never inherits the old process’s counters.
* **Termination / churn** – vanished processes are pruned; a real child is spawned, observed and killed; 15 short‑lived processes are spawned/reaped while sampling.
* **Short‑lived processes** – born‑between‑samples processes count from zero; unknown old processes get no rate.
* **Restricted metrics** – unreadable processes (`counters == nil`) yield nil, are excluded from memory totals and counted; unavailable system metrics stay nil.
* **Grouping** – Chrome main + renderers/GPU/network helpers fold into one entry; Safari WebContent/Networking via the responsible process; Terminal children; Xcode helpers + build tools + Instruments kept separate when it is a Dock app; CoreSimulator apps excluded from path grouping; Docker‑style bundles; Apple services vs third‑party background processes; same executable name in different apps not merged; responsible‑pid loops terminate; relaunch merges by bundle path.
* **Aggregation, sorting, filtering, scopes, search (name / bundle id / pid / process name), severity thresholds, protection rules.**
* **Live** – measures two busy threads (150–260 %), reads this process’s footprint, full sampler end‑to‑end under 250 ms, `nettop` source yields per‑pid rates and cleans up its child.
* **Menu bar** – only ticked metrics render, unavailable metrics show “n/a”/“—”, template image in every style.

## Comparison with `top` (`scripts/validate.py`)
Two `yes` processes were run as a known load while `top -l 2 -s 2` and Gauge’s sampler (`--dump 2`) measured simultaneously.

| | Gauge | top |
|---|---|---|
| `yes` ×2 (single‑threaded busy loops, expected ≈100 %) | 99.2 % each | 82.4 % each |
| other processes (≥4 %), median |Δ| | 0.7 percentage points | |
| memory (physical footprint), median relative Δ | 0.2 % | |

Meaningful differences:
* `top` under‑reports a pegged core here (82 % vs an expected ~100 %) because its own sampling interval is not exactly the nominal `-s` delay; Gauge divides by the measured monotonic interval between its two reads.
* Memory matches `top`’s MEM column (both are `phys_footprint`). Activity Monitor’s “Memory” is the same figure per process; Gauge sums it per app, so shared pages are not double counted by the kernel but apps whose helpers map the same large shared regions can still look larger than any single process.
* Energy is average power from `ri_billed_energy`; it is **not** Activity Monitor’s “Energy Impact”, which is a proprietary weighted score.
* Activity Monitor groups by process tree only in its “Hierarchical” view; Gauge groups by owning application (bundle path → responsible process → ancestry) and labels inferred attributions.
* On this Mac all ~900 processes were readable (root daemons included); on systems/users where some are not, they are counted as “protected by macOS” and omitted from totals.

## Gauge’s own CPU use
Measured with `ps` CPU time over 40 s of steady state (after a 15 s warm‑up), Release build, Mac Studio M1 Max, ~1,950 running processes, display awake:

| Configuration | Before (1.1.0) | After (1.2.0) |
|---|---|---|
| Window open, Liquid Glass, 2 s refresh | ≈ 50 % | **≈ 3 %** |
| Window open, 1 s refresh | — | ≈ 9 % before the sampler cache, lower after |
| Menu bar only, 2 s refresh | — | **≈ 1 %** |
| Window open, refresh paused | ≈ 0 % | ≈ 0 % |

How it was found: cost scaled with the number of updates (≈ 1 CPU‑second per tick at any interval), and bisecting showed the ring gauges plus the global update animation were responsible — every animation frame re‑rendered the Liquid Glass surfaces, so each data tick became ~40 expensive frames. With Reduced effects the same views cost ≈ 0 %, confirming the glass re‑render as the multiplier. Data ticks now apply without animation. Separately, per‑sample cost fell from ≈ 75–110 ms to ≈ 17 ms by caching owning‑bundle and Info.plist lookups across ticks.

Earlier readings in this project that showed a constant cost while paused were invalid: the display had gone to sleep, so nothing was rendering. Measurements are only trusted when the app’s startup render is visible in its CPU time and the display is awake.
