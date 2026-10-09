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
