#!/usr/bin/env python3
"""Measure repeated installed-app launches. Restarts only Barometer; never modifies settings.

Run after installing a tested build. Keep its dropdowns closed for the idle benchmark.
"""
import argparse
import pathlib
import re
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runs', type=int, default=3)
parser.add_argument('--seconds', type=float, default=78)
parser.add_argument('--peak-limit-mb', type=float, default=146.3)
args = parser.parse_args()
if args.runs < 1 or args.seconds < 1:
    parser.error('runs and seconds must be positive')
root = pathlib.Path(__file__).resolve().parents[1]
output = root / 'dist' / 'app-memory-runs'
output.mkdir(parents=True, exist_ok=True)
failed = False
for run in range(1, args.runs + 1):
    subprocess.run(['osascript', '-e', 'tell application id "com.barometer.app" to quit'], check=True)
    for _ in range(100):
        if subprocess.run(['pgrep', '-x', 'Barometer'], stdout=subprocess.DEVNULL).returncode != 0:
            break
        time.sleep(0.1)
    else:
        raise SystemExit('Barometer did not quit; refusing to launch another instance')
    subprocess.run(['open', '/Applications/Barometer.app'], check=True)
    time.sleep(args.seconds)
    pid = subprocess.check_output(['pgrep', '-x', 'Barometer'], text=True).strip()
    if not pid.isdigit():
        raise SystemExit('Expected exactly one Barometer process')
    result = subprocess.run(['leaks', pid], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (output / f'run-{run}.txt').write_text(result.stdout)
    current = re.search(r'Physical footprint:\s+([\d.]+)M', result.stdout)
    peak = re.search(r'Physical footprint \(peak\):\s+([\d.]+)M', result.stdout)
    if current is None or peak is None:
        raise SystemExit(f'No usable footprint in run {run}; inspect its report')
    passed = float(peak[1]) < args.peak_limit_mb
    failed |= not passed
    print(f'Run {run}: current={current[1]}M peak={peak[1]}M {"PASS" if passed else "FAIL"}', flush=True)
raise SystemExit(1 if failed else 0)
