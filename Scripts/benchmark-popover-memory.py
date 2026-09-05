#!/usr/bin/env python3
"""Build and run the rich-panel and shared-graph benchmark without creating menu bar items.

Requires a completed debug build. The benchmark displays and scrolls test panels for about twelve seconds.
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
    merged_object = binary_path / f'{target}.o'
    if merged_object.exists():
        objects.append(str(merged_object))
    else:
        objects.extend(str(p) for p in sorted((binary_path / f'{target}.build').glob('*.o')))
binary = root / 'dist' / 'popover-memory-benchmark'
binary.parent.mkdir(parents=True, exist_ok=True)
module_path = binary_path / 'Modules'
command = ['swiftc', '-parse-as-library', '-O', '-I', str(module_path if module_path.exists() else binary_path),
           '-I', str(binary_path / 'CSystemSources.build'), str(root / 'Tools/PopoverMemoryBenchmark.swift'),
           *objects, '-o', str(binary)]
c_module_map = binary_path / 'CSystemSources.build' / 'module.modulemap'
if not c_module_map.exists():
    c_module_map = binary_path.parent.parent / 'Intermediates.noindex/GeneratedModuleMaps/CSystemSources.modulemap'
if c_module_map.exists():
    command.extend(['-Xcc', f'-fmodule-map-file={c_module_map}',
                    '-Xcc', f'-I{root / "Sources/CSystemSources/include"}'])
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
