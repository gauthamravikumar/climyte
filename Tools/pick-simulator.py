#!/usr/bin/env python3
"""Print the UDID of an available iPhone simulator on the newest iOS runtime.

CI runner images swap their bundled simulators without notice, so pinning a
model name ("iPhone 16") makes the workflow fail on image updates. Reads
`xcrun simctl list devices available --json` on stdin.
"""
import json
import sys


def main() -> int:
    devices = json.load(sys.stdin)["devices"]

    candidates = []
    for runtime, entries in devices.items():
        if "iOS" not in runtime:
            continue
        for device in entries:
            if device.get("isAvailable") and "iPhone" in device["name"]:
                candidates.append((runtime, device["name"], device["udid"]))

    if not candidates:
        print("No available iPhone simulator found", file=sys.stderr)
        return 1

    # Runtime identifiers sort lexicographically by version, so the last entry
    # is the newest iOS available.
    candidates.sort(key=lambda c: c[0])
    runtime, name, udid = candidates[-1]
    print(f"Selected {name} on {runtime}", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
