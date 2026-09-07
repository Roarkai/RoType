#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-/tmp/rotype-settings-preview}"
swift build --product RoTypeApp >/dev/null
build=$(swift build --show-bin-path)
# Use SwiftPM's current object list, never stale object files left behind by deleted sources.
objects=()
while IFS= read -r file; do
  [[ "$file" == */main.swift.o ]] || objects+=("$file")
done < "$build/RoTypeApp.product/Objects.LinkFileList"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc -swift-version 6 -parse-as-library \
  -I "$build/Modules" \
  -Xcc "-fmodule-map-file=$build/RoTypeXPCProtocol.build/module.modulemap" \
  -Xcc "-I$PWD/Shared/RoTypeXPCProtocol/include" \
  Tests/SettingsUI/Preview.swift "${objects[@]}" -o "$work/RoTypeSettingsPreview"
"$work/RoTypeSettingsPreview" "$output"
printf 'Native light/dark settings previews: %s\n' "$output"
