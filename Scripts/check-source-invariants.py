#!/usr/bin/env python3
"""Reject source patterns that violate measured Barometer runtime invariants."""

import pathlib


root = pathlib.Path(__file__).resolve().parents[1]
violations: list[str] = []

# SwiftUI Canvas retains a large Core Animation backing allocation after a graph disappears.
# Shape paths render the same graphs without the observed 160+ MiB retained spike.
for path in sorted((root / "Sources" / "MenuBarStatsUI").rglob("*.swift")):
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if "Canvas {" in line:
            violations.append(f"{path.relative_to(root)}:{line_number}: SwiftUI Canvas is prohibited")

if violations:
    raise SystemExit("\n".join(["Source invariant check failed:", *violations]))

print("Source invariant check passed")
