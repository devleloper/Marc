#!/usr/bin/env bash
# Installs the exact XcodeGen, SwiftLint and SwiftFormat versions CI uses into .tools/bin,
# verifying each download's SHA-256. Locally, `brew bundle` is usually enough; use this script
# when formatting or lint results differ from CI.
#
# Usage: scripts/install-tools.sh && export PATH="$PWD/.tools/bin:$PATH"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/.tools"
BIN="$TOOLS/bin"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# name|version|url|sha256
PINS=(
  "xcodegen|2.46.0|https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip|4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
  "swiftlint|0.65.1|https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip|c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
  "swiftformat|0.64.1|https://github.com/nicklockwood/SwiftFormat/releases/download/0.64.1/swiftformat.zip|0e5762a848d738602c7a983b26812031e634d85e357db070968b9c805f253eff"
)

mkdir -p "$BIN"
for pin in "${PINS[@]}"; do
  IFS='|' read -r name version url sha256 <<<"$pin"
  destination="$TOOLS/$name-$version"
  if [[ ! -d "$destination" ]]; then
    echo "Installing $name $version"
    curl --fail --silent --show-error --location --retry 3 "$url" --output "$WORK/$name.zip"
    echo "$sha256  $WORK/$name.zip" | shasum --algorithm 256 --check --status || {
      echo "error: checksum mismatch for $name $version" >&2
      exit 1
    }
    mkdir -p "$WORK/$name" && unzip -q "$WORK/$name.zip" -d "$WORK/$name"
    mv "$WORK/$name" "$destination"
  fi
  executable="$(find "$destination" -type f -name "$name" -perm -u+x | head -n 1)"
  if [[ -z "$executable" ]]; then
    echo "error: $name executable not found in the $name $version archive" >&2
    exit 1
  fi
  # A wrapper rather than a symlink, so tools that locate resources next to their real path
  # (XcodeGen's setting presets) keep working.
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$executable" >"$BIN/$name"
  chmod +x "$BIN/$name"
done

echo "Tools are in $BIN"
