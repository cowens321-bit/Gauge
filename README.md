# Gauge

A native, lightweight macOS Activity Monitor alternative (SwiftUI + Swift Charts + libproc/Mach/IOKit).
Groups every process under the application responsible for it and shows honest, per‑app CPU, memory,
energy, disk and (opt‑in) network. No accounts, analytics, network access or disk writes of its own.
Inspired by the publicly described feature set of Vitals; no Vitals code or assets are used.

## Install & updates
Download `Gauge-<version>.dmg` from the [latest release](https://github.com/cowens321-bit/Gauge/releases/latest), drag **Gauge** to **Applications**, and launch it. After that, Gauge keeps itself current: it checks this repository's `appcast.xml` daily (Settings ▸ Updates, or **Gauge ▸ Check for Updates…**), verifies each new DMG with an EdDSA signature (Sparkle), and installs it for you — no more manual DMG downloads.

If macOS says the app is from an unidentified developer (it is ad‑hoc signed, not notarized), right‑click ▸ Open once.

### Publishing an update (maintainer)
```
scripts/release.sh 1.1.0 "What changed"
```
Builds, runs the tests, creates `dist/Gauge-1.1.0.dmg`, signs it with the private key in the login Keychain, tags and pushes, publishes the GitHub release, and updates `appcast.xml` on `main`. **Back up the Sparkle private key** (`.tools/bin/generate_keys -x gauge-sparkle-key.pem`, store it somewhere safe): without it future updates cannot be signed for installed copies.

```
scripts/build.sh      # xcodegen + Release build -> dist/Gauge.app
scripts/test.sh       # 55 unit + live tests
scripts/validate.py   # compare against `top` under a known CPU load
dist/Gauge.app --dump 2   # headless JSON sample (smoke test / validation)
```
Requires **macOS 26+** (Liquid Glass APIs), Xcode, and `xcodegen` (the `.xcodeproj` is generated from `project.yml`; it is also checked in).
The app is ad‑hoc signed and **not sandboxed** (libproc needs to see other processes).

## Design
* Native SwiftUI + Swift Charts. Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.glass` / `.glassProminent` buttons) on cards, tiles, panels, the status pill, tooltips and controls; system glass for the sidebar, toolbar, search and inspector.
* Overview cards: ring gauge + animated numbers (`numericText`) + glowing live sparkline per metric. A mesh‑gradient background warms from blue/teal toward orange as CPU / memory pressure rises.
* Charts: gradient areas, round line caps, live‑point halo, scrub‑to‑inspect glass tooltip, gaps shown as gaps, x‑range grows with available history.
* **Menu bar item** (Settings ▸ Menu Bar, or the “Menu bar items” chips in its popover): tick any of CPU, Memory, GPU, Network, Disk I/O, Free storage; style = values / graphs / both. Drawn as one template image so it matches the menu bar in light, dark and tinted modes. Popover: rings, top apps by CPU/memory, quick toggles.
* **Visual effects** (Settings ▸ Display): *Liquid Glass* (default) or *Reduced* (standard materials, static background). Reduced is also used automatically when macOS “Reduce transparency” is on.

## What is measured, and how

| Metric | Source | Scope | Notes |
|---|---|---|---|
| Per‑process CPU | `proc_pid_rusage` (v6) user+system time, mach‑ticks → ns | per process, summed per app | **Default: 100% = one core** (Activity Monitor convention; 3 busy cores = 300%). Settings → "Whole machine" divides by core count. System CPU is always 0–100% of the whole machine. |
| Memory | `ri_phys_footprint` | per process, summed | Same figure Activity Monitor calls *Memory*. Matches `top` to rounding (see docs/VALIDATION.md). |
| Energy | `ri_billed_energy` (nJ) / Δt | per process | Shown as **average power (mW/W)**. This is *not* Activity Monitor's "Energy Impact" score, which is a private heuristic. |
| Disk | `ri_diskio_bytesread/written` | per process; system via IOKit `IOBlockStorageDriver` | |
| Network (system) | `NET_RT_IFLIST2` 64‑bit counters on `en*`/`pdp_ip*` | system | Tunnels/bridges excluded to avoid double counting. |
| Network (per app) | `nettop` (opt‑in) | per process | macOS has **no public per‑process network API**. Off by default: it spawns `nettop`, which has a measurable CPU cost. |
| GPU | IOKit `IOAccelerator` "Device Utilization %" | **system only** | No supported per‑app GPU metric exists, so none is shown. |
| Memory pressure / breakdown | `host_statistics64`, `kern.memorystatus_vm_pressure_level`, `vm.swapusage` | system | App/Wired/Compressed/Cached as in Activity Monitor. |
| Temperature / fans | — | — | **Unavailable** (no public API). Gauge shows `ProcessInfo.thermalState` instead and says so in the UI. |

Unavailable values are `nil` internally and rendered "—"/"Unavailable"; they are never zero‑filled or estimated.
Processes the kernel refuses to read are counted ("N protected by macOS") and excluded.

## Process attribution (`ProcessAttribution/`)

Each process is assigned, in priority order, and the reason is kept and shown:
1. **bundlePath** – executable inside an `.app` (helpers fold into the outermost app; a nested app that is itself a running Dock app, e.g. Instruments in Xcode, stays separate; CoreSimulator runtime apps are excluded).
2. **responsibleProcess** – macOS' "responsible pid" resolves to an app (Safari WebContent/Networking, tools launched from Terminal/Xcode…). This uses `responsibility_get_pid_responsible_for_pid`, the **one private symbol** in the app, resolved with `dlsym` and skipped gracefully if missing.
3. **ancestry** – an ancestor in the parent chain belongs to an app. Flagged "inferred" (❓ in the list and inspector).
4. **unattributed** – never guessed from the executable name. Shown as *macOS Services*, *System Services (root)* or *Background Services* pseudo groups, which cannot be quit as a unit.

PID reuse is handled by identifying processes as (pid, start time). Relaunched apps merge by bundle path.

## Architecture

```
Gauge/App            entry point, delegate, `--dump` headless mode
Gauge/Models         value types (ProcessRecord, GroupSnapshot, SystemSnapshot, TimeSeries…)
Gauge/ProcessDiscovery  ProcessSource protocol + libproc implementation
Gauge/ProcessAttribution  AttributionEngine, GroupAggregator
Gauge/Metrics        RateTracker (CPU/disk/energy deltas), MachSystemMetrics, nettop source
Gauge/Monitoring     Sampler (actor, off‑main), ProcessController (quit / force quit / protection)
Gauge/ViewModels     MonitorModel (@Observable, sampling loop + in‑memory history)
Gauge/Views, Charts, MenuBar, Settings, Utilities
Tests                unit tests with fakes + live tests against the real OS
```
All sampling runs in the `Sampler` actor; the main actor only applies finished snapshots.

## Efficiency design
* No process enumeration at all while the window is hidden/minimised and no popover is open; with only the menu bar enabled just ~4 cheap system reads run per tick. Sampling stops entirely when paused.
* Static per‑process info (path, name) is cached by process identity; one full sample of ~600 processes costs ≈20 ms.
* History is in‑memory, time‑bounded, never written to disk. Charts are downsampled and break across gaps.

## Safety
Quit is graceful (`NSRunningApplication.terminate`) and confirmed; Force Quit requires a confirmation warning about lost work.
Protected targets are refused: pid ≤ 1, Gauge itself, other users' processes, `/System/Library`, `/usr/libexec`, `/usr/sbin`, `/sbin`, Finder/Dock/loginwindow/WindowServer/SystemUIServer/Control Center/Notification Center, and all pseudo groups (manage individual processes in the inspector).

## Known limitations / honest notes
* **Gauge’s own CPU use is too high while its window is visible (open issue).** Sampling is cheap (≈20–35 ms per tick for ~900 processes) and costs nothing when the window is hidden and the menu bar item is off. With the window visible, however, I measured roughly 30–55 % of one core on the test Mac (macOS 27 beta, Release build, 2 s refresh). What I established, with the display awake:
  * Switching *Visual effects* to **Reduced** (no Liquid Glass on live panels, no animated background) made **no meaningful difference** (≈10.0 vs ≈10.5 CPU‑seconds per 20 s), so glass is not the cause.
  * Removing the overview cards and the app list individually, or both, did **not** remove the load; a stripped window (sidebar, toolbar, search, inspector only) still used ≈27 % at 1 s, 2 s, 10 s and *paused* refresh. That points at something in the window chrome rendering continuously rather than at per‑tick data updates.
  * A bisect of the remaining chrome (sidebar status pill, search field, inspector) was started but the Mac’s display went to sleep mid‑run, so those four readings are invalid and are not reported.
  Next step: profile on your hardware (Instruments ▸ Time Profiler / Animation Hitches), then bisect `status`, `.searchable`, `.inspector`, and the toolbar `Menu` in `Views/RootView.swift` / `Views/ApplicationsView.swift`.
* The menu bar popover, Settings window and Quit/Force‑Quit alerts were built and unit‑tested where possible but not clicked through (GUI automation was not permitted on the test Mac).
* Per‑app GPU, temperature and fan speed are intentionally absent (no supported API). Per‑app network is opt‑in via `nettop`.
* Single private symbol: `responsibility_get_pid_responsible_for_pid` (dlsym, optional).
* Developer launch options: `-launchPage system`, `-launchInspectTop YES`, `--dump [seconds]` (headless JSON sample).
