#!/usr/bin/env python3
"""Measure the installed app with one menu bar widget enabled at a time.

The script changes only Barometer's encoded settings while the app is stopped. It restores the
original settings byte for byte and returns Barometer to its original running state on every exit.
It never launches, stops, or configures a menu bar manager.
"""

import argparse
import copy
import json
import pathlib
import plistlib
import re
import statistics
import subprocess
import time


DOMAIN = "com.barometer.app"
APP_PATH = "/Applications/Barometer.app"
MODULES = ["cpu", "gpu", "memory", "disks", "network", "sensors", "battery", "weather", "time"]


def command_output(arguments: list[str]) -> str:
    return subprocess.check_output(arguments, text=True).strip()


def read_settings() -> bytes:
    exported = subprocess.check_output(["defaults", "export", DOMAIN, "-"])
    settings = plistlib.loads(exported).get("settings")
    if not isinstance(settings, bytes):
        raise RuntimeError("Barometer settings data is unavailable")
    return settings


def write_settings(data: bytes) -> None:
    subprocess.run(["defaults", "write", DOMAIN, "settings", "-data", data.hex()], check=True)
    if read_settings() != data:
        raise RuntimeError("Barometer settings did not round trip through UserDefaults")


def process_ids() -> list[int]:
    result = subprocess.run(["pgrep", "-x", "Barometer"], text=True, capture_output=True)
    return [int(value) for value in result.stdout.split() if value.isdigit()]


def stop_app() -> None:
    subprocess.run(
        ["osascript", "-e", f'tell application id "{DOMAIN}" to quit'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    for _ in range(100):
        if not process_ids():
            return
        time.sleep(0.1)
    raise RuntimeError("Barometer did not quit, so the benchmark refused to create another instance")


def start_app() -> int:
    subprocess.run(["open", APP_PATH], check=True)
    for _ in range(100):
        identifiers = process_ids()
        if len(identifiers) == 1:
            return identifiers[0]
        if len(identifiers) > 1:
            raise RuntimeError("More than one Barometer process is running")
        time.sleep(0.1)
    raise RuntimeError("Barometer did not launch")


def module_records(settings: dict) -> dict[str, dict]:
    encoded = settings.get("modules")
    if isinstance(encoded, dict):
        return encoded
    if isinstance(encoded, list) and len(encoded) % 2 == 0:
        return {encoded[index]: encoded[index + 1] for index in range(0, len(encoded), 2)}
    raise RuntimeError("Unsupported modules encoding in Barometer settings")


def scenario_settings(original: dict, module: str | None, shows_seconds: bool = False) -> bytes:
    settings = copy.deepcopy(original)
    modules = module_records(settings)
    for identifier, record in modules.items():
        record["isEnabled"] = identifier == module
    settings["globalSamplingInterval"] = 3

    sensor_settings = settings.get("sensors", {})
    for index, widget in enumerate(sensor_settings.get("widgets", [])):
        widget["isEnabled"] = module == "sensors" and index == 0

    stack_settings = settings.get("stacks", {})
    stacks = stack_settings.get("stacks", [])
    for index, stack in enumerate(stacks):
        stack["isEnabled"] = module == "combined" and index == 0

    time_settings = settings.setdefault("time", {})
    time_settings["showsSeconds"] = module == "time" and shows_seconds
    return json.dumps(settings, separators=(",", ":")).encode()


def physical_footprints(pid: int) -> tuple[float, float]:
    result = subprocess.run(
        ["leaks", str(pid)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    ).stdout
    current = re.search(r"Physical footprint:\s+([\d.]+)M", result)
    peak = re.search(r"Physical footprint \(peak\):\s+([\d.]+)M", result)
    if current is None or peak is None:
        raise RuntimeError("leaks did not report physical footprints")
    return float(current.group(1)), float(peak.group(1))


def count_value(value: str) -> float:
    multipliers = {"K": 1_000, "M": 1_000_000, "G": 1_000_000_000}
    suffix = value[-1] if value[-1] in multipliers else ""
    number = float(value[:-1] if suffix else value)
    return number * multipliers.get(suffix, 1)


def measure(pid: int, samples: int) -> tuple[float, float, float, float, float, float]:
    output = command_output([
        "top", "-l", str(samples + 1), "-s", "1", "-pid", str(pid),
        "-stats", "pid,cpu,mem,csw,time",
    ])
    rows = re.findall(rf"^{pid}\s+([\d.]+)\s+\S+\s+([\d.]+[KMG]?)\+?\s+", output, re.MULTILINE)
    if len(rows) < samples:
        raise RuntimeError(f"top returned {len(rows)} usable samples, expected at least {samples}")
    rows = rows[-samples:]
    cpu = [float(row[0]) for row in rows]
    context_switches = [count_value(row[1]) for row in rows]
    switches_per_second = max(0, context_switches[-1] - context_switches[0]) / max(1, len(rows) - 1)
    current, peak = physical_footprints(pid)
    return statistics.mean(cpu), statistics.median(cpu), max(cpu), switches_per_second, current, peak


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--warmup-seconds", type=float, default=12)
    parser.add_argument("--samples", type=int, default=15)
    arguments = parser.parse_args()
    if arguments.warmup_seconds < 1 or arguments.samples < 3:
        parser.error("warmup-seconds must be at least 1 and samples must be at least 3")

    root = pathlib.Path(__file__).resolve().parents[1]
    output = root / "dist" / "widget-impact"
    output.mkdir(parents=True, exist_ok=True)
    original_data = read_settings()
    original = json.loads(original_data)
    was_running = bool(process_ids())
    (output / "original-settings.json").write_bytes(original_data)
    results = []
    scenarios: list[tuple[str, str | None, bool]] = [("No widgets", None, False)]
    scenarios.extend((module.title(), module, False) for module in MODULES)
    scenarios.append(("Time with seconds", "time", True))
    if original.get("stacks", {}).get("stacks"):
        scenarios.append(("Combined", "combined", False))

    try:
        stop_app()
        for name, module, shows_seconds in scenarios:
            write_settings(scenario_settings(original, module, shows_seconds))
            pid = start_app()
            time.sleep(arguments.warmup_seconds)
            average, median, maximum, switches, current, peak = measure(pid, arguments.samples)
            result = {
                "widget": name,
                "cpuAveragePercent": round(average, 3),
                "cpuMedianPercent": round(median, 3),
                "cpuMaximumPercent": round(maximum, 3),
                "contextSwitchesPerSecond": round(switches, 1),
                "physicalFootprintMB": current,
                "peakPhysicalFootprintMB": peak,
            }
            results.append(result)
            (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            print(
                f"{name}: CPU avg {average:.2f}% median {median:.2f}% max {maximum:.2f}%, "
                f"context switches {switches:.1f}/s, footprint {current:.1f}M peak {peak:.1f}M",
                flush=True,
            )
            stop_app()
    finally:
        stop_app()
        write_settings(original_data)
        if was_running:
            start_app()

    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    if read_settings() != original_data:
        raise RuntimeError("Original Barometer settings were not restored")
    print("Original Barometer settings restored byte for byte.")
    print("Per-process GPU time is not available without the privileged powermetrics tool.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
