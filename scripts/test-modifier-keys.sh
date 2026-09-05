#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -R "$temporary"' EXIT
xcrun swiftc -import-objc-header "$repo_dir/Squirrel/librime/src/rime/key_table.h" \
  -I "$repo_dir/Squirrel/librime/src" -I "$repo_dir/Squirrel/librime/include" \
  "$repo_dir/Squirrel/sources/MacOSKeyCodes.swift" \
  "$repo_dir/Tests/InputMode/ModifierTests.swift" -o "$temporary/test"
"$temporary/test"
