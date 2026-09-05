#!/usr/bin/env python3
"""Compare storage against a previously built baseline checkout using identical synthetic samples.

Usage: python3 Scripts/benchmark-memory.py dist/memory-baseline
Build both checkouts with swift build first. Artifacts and measurements stay in dist/.
"""
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
baseline = pathlib.Path(sys.argv[1]).resolve()
output = root / "dist"
measurements = {}
for mode, checkout, seconds in [("baseline", baseline, "3600"), ("compact", root, "172800")]:
    binary_path = pathlib.Path(subprocess.check_output(
        ["swift", "build", "--package-path", str(checkout), "--show-bin-path"], text=True).strip())
    objects = []
    for target in ["MenuBarStatsCore", "SystemSources", "CSystemSources"]:
        objects.extend(str(p) for p in sorted((binary_path / f"{target}.build").glob("*.o")))
    binary = output / f"memory-{mode}-benchmark"
    command = ["swiftc", "-parse-as-library", "-O", "-I", str(binary_path / "Modules"),
               "-I", str(binary_path / "CSystemSources.build"), str(root / "Tools/MemoryHistoryBenchmark.swift"),
               *objects, "-o", str(binary)]
    for framework in ["IOKit", "CoreWLAN", "EventKit", "Network", "SystemConfiguration"]:
        command.extend(["-framework", framework])
    if mode == "compact":
        command.extend(["-D", "COMPACT_HISTORY"])
    subprocess.run(command, check=True)
    result = subprocess.run([str(binary), seconds], check=True, text=True, capture_output=True)
    (output / f"memory-{mode}.txt").write_text(result.stdout)
    print(result.stdout, end="")

    measurements[mode] = {}
    for line in result.stdout.splitlines():
        fields = dict(field.split("=", 1) for field in line.split()[1:])
        measurements[mode][int(fields["seconds"])] = int(fields["footprint_bytes"])

before = measurements["baseline"][3600]
after = measurements["compact"][3600]
growth = measurements["compact"][172800] - measurements["compact"][86400]
if after >= before * 0.5:
    raise SystemExit("FAIL: compact history did not reduce the one-hour footprint by at least 50%")
if growth > 5 * 1024 * 1024:
    raise SystemExit("FAIL: compact history grew more than 5 MiB between simulated hours 24 and 48")
print(f"PASS: one-hour footprint reduced by {100 * (1 - after / before):.1f}%; plateau growth {growth} bytes")
