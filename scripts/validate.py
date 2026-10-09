#!/usr/bin/env python3
"""Compare Gauge's per-process CPU/memory against `top` (the engine behind Activity Monitor-style numbers)
while a known CPU load runs. Usage: scripts/validate.py [path/to/Gauge.app]"""
import json, subprocess, sys, re, time, os
app = sys.argv[1] if len(sys.argv) > 1 else "build/Build/Products/Release/Gauge.app"
exe = os.path.join(app, "Contents/MacOS/Gauge")
burners = [subprocess.Popen(["/usr/bin/yes"], stdout=subprocess.DEVNULL) for _ in range(2)]
time.sleep(0.5)
top = subprocess.Popen(["top", "-l", "2", "-s", "2", "-n", "60", "-o", "cpu", "-stats", "pid,command,cpu,mem"], stdout=subprocess.PIPE, text=True)
gauge = subprocess.Popen([exe, "--dump", "2"], stdout=subprocess.PIPE, text=True)
gout = gauge.communicate()[0]; tout = top.communicate()[0]
for b in burners: b.kill()
data = json.loads(gout.strip().splitlines()[-1])
samples = tout.split("PID")          # second sample is the last block
rows = {}
for line in samples[-1].splitlines():
    m = re.match(r"\s*(\d+)\s+(.+?)\s+([\d.]+)\s+(\d+(?:\.\d+)?)([KMGB])[+-]?\s*$", line)
    if m:
        mult = {"K": 1/1024, "M": 1, "G": 1024, "B": 1/1048576}[m.group(5)]
        rows[int(m.group(1))] = (float(m.group(3)), float(m.group(4)) * mult)
mine = {p["pid"]: p for p in data["processes"]}
print(f"Gauge sample cost: {data['system']['sampleMs']:.1f} ms for {data['system']['processes']} processes\n")
print(f"{'pid':>6} {'process':<28} {'top CPU%':>9} {'Gauge CPU%':>11} {'top MEM(MB)':>12} {'Gauge MEM(MB)':>14}")
cd, md = [], []
for pid, (tc, tm) in sorted(rows.items(), key=lambda kv: -kv[1][0])[:15]:
    p = mine.get(pid)
    if not p or p["cpu"] is None: continue
    gm = (p["mem"] or 0) / 1048576
    cd.append(abs(tc - p["cpu"])); md.append(abs(tm - gm) / max(tm, 1))
    print(f"{pid:>6} {p['name'][:28]:<28} {tc:>9.1f} {p['cpu']:>11.1f} {tm:>12.1f} {gm:>14.1f}")
if cd:
    print(f"\nmedian |ΔCPU| = {sorted(cd)[len(cd)//2]:.1f} pts, median relative Δmem = {sorted(md)[len(md)//2]*100:.1f}%")
