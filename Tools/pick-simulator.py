#!/usr/bin/env python3
"""Print the UDID of an available iPhone simulator on the newest iOS runtime.

CI runner images swap their bundled simulators without notice, so pinning a
model name ("iPhone 16") makes the workflow fail on image updates. Reads
`xcrun simctl list devices available --json` on stdin.

`--major 18` keeps to runtimes of that iOS version, and fails if there are
none, so a run meant for the oldest supported iOS can't quietly fall through
to a newer one.
"""
import json
import re
import sys


def version(runtime: str) -> tuple:
    # "com.apple.CoreSimulator.SimRuntime.iOS-18-5" -> (18, 5)
    return tuple(int(part) for part in re.findall(r"\d+", runtime.rsplit("iOS", 1)[-1]))


def main() -> int:
    major = None
    if "--major" in sys.argv:
        major = int(sys.argv[sys.argv.index("--major") + 1])

    devices = json.load(sys.stdin)["devices"]

    candidates = []
    for runtime, entries in devices.items():
        if "iOS" not in runtime:
            continue
        if major is not None and version(runtime)[:1] != (major,):
            continue
        for device in entries:
            if device.get("isAvailable") and "iPhone" in device["name"]:
                candidates.append((runtime, device["name"], device["udid"]))

    if not candidates:
        wanted = f" on iOS {major}" if major is not None else ""
        print(f"No available iPhone simulator found{wanted}", file=sys.stderr)
        return 1

    # By version number, not by string: as text, iOS-9 sorts after iOS-18.
    candidates.sort(key=lambda c: version(c[0]))
    runtime, name, udid = candidates[-1]
    print(f"Selected {name} on {runtime}", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
