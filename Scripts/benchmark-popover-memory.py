#!/usr/bin/env python3
"""Build and run the weather-panel benchmark without creating any menu bar items.

Requires a completed debug build. The benchmark displays and scrolls test panels for about ten seconds.
"""
import argparse
import pathlib
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--peak-limit-mb', type=float, default=128)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
binary_path = pathlib.Path(subprocess.check_output(
    ['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip())
objects = []
for target in ['MenuBarStatsUI', 'MenuBarStatsCore', 'SystemSources', 'CSystemSources']:
    objects.extend(str(p) for p in sorted((binary_path / f'{target}.build').glob('*.o')))
binary = root / 'dist' / 'popover-memory-benchmark'
command = ['swiftc', '-parse-as-library', '-O', '-I', str(binary_path / 'Modules'),
           '-I', str(binary_path / 'CSystemSources.build'), str(root / 'Tools/PopoverMemoryBenchmark.swift'),
           *objects, '-o', str(binary)]
for framework in ['AppKit', 'SwiftUI', 'IOKit', 'CoreWLAN', 'EventKit', 'Network', 'SystemConfiguration']:
    command.extend(['-framework', framework])
subprocess.run(command, cwd=root, check=True)
result = subprocess.run([str(binary)], cwd=root, check=True, stdout=subprocess.PIPE, text=True)
print(result.stdout, end='')
peaks = [int(value) for value in re.findall(r'peak=(\d+)', result.stdout)]
if not peaks:
    raise SystemExit('FAIL: benchmark produced no peak footprint')
peak_mb = max(peaks) / (1024 * 1024)
if peak_mb >= args.peak_limit_mb:
    raise SystemExit(f'FAIL: peak {peak_mb:.1f} MiB is not below {args.peak_limit_mb:.1f} MiB')
print(f'PASS: peak {peak_mb:.1f} MiB is below {args.peak_limit_mb:.1f} MiB')
