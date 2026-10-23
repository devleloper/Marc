#!/usr/bin/env bash
# Builds Marc's disk image: the app, an Applications shortcut, the window background and icon
# layout. The background is rendered from design/render-dmg-background.swift; dmgbuild comes from
# PyPI, pinned by hash in packaging/dmg/requirements.txt.
#
# Usage: scripts/make-dmg.sh path/to/Marc.app output.dmg [--preview]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$(cd "$(dirname "${1:?usage: make-dmg.sh <Marc.app> <output.dmg> [--preview]}")" && pwd)/$(basename "$1")"
output="${2:?usage: make-dmg.sh <Marc.app> <output.dmg> [--preview]}"
variant="standard"
[[ "${3:-}" == "--preview" ]] && variant="preview"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Rendering the $variant background"
swiftc -O "$root/design/render-dmg-background.swift" -o "$work/render-background"
"$work/render-background" "$work" > /dev/null
tiffutil -cathidpicheck "$work/background-$variant.png" "$work/background-$variant@2x.png" \
  -out "$work/background.tiff" > /dev/null 2>&1

echo "Installing dmgbuild"
python3 -m venv "$work/venv"
"$work/venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes --only-binary :all: \
  -r "$root/packaging/dmg/requirements.txt"

echo "Building $output"
rm -f "$output"
"$work/venv/bin/dmgbuild" -s "$root/packaging/dmg/settings.py" \
  -D app="$app" -D background="$work/background.tiff" "Marc" "$output"
