#!/usr/bin/env bash
# Copies the "screenshot-<name>" attachments of a test result bundle to <destination>/<name>.png.
#
# Usage: scripts/export-screenshots.sh build/Screenshots.xcresult docs/images
set -euo pipefail

result="${1:?usage: export-screenshots.sh <result bundle> <destination>}"
destination="${2:?usage: export-screenshots.sh <result bundle> <destination>}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

xcrun xcresulttool export attachments --path "$result" --output-path "$work" > /dev/null
mkdir -p "$destination"
/usr/bin/python3 -I - "$work" "$destination" <<'PYTHON'
import json
import pathlib
import shutil
import sys

work, destination = (pathlib.Path(argument) for argument in sys.argv[1:3])
exported = 0
for test in json.loads((work / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        # Names look like "screenshot-marc-window_0_<UUID>.png".
        name = attachment.get("suggestedHumanReadableName", "").rsplit("_", 2)[0]
        if name.startswith("screenshot-"):
            target = destination / f"{name.removeprefix('screenshot-')}.png"
            shutil.copyfile(work / attachment["exportedFileName"], target)
            print(target)
            exported += 1
if exported == 0:
    sys.exit("No screenshot attachments found; was MARC_SCREENSHOTS set?")
PYTHON
