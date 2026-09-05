#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -R "$temporary"' EXIT
xcrun swiftc "$repo_dir/Squirrel/sources/RoTypeInputModePanel.swift" \
  "$repo_dir/Squirrel/sources/RoTypeCandidateLearningMenu.swift" \
  "$repo_dir/Tests/InputMode/PanelTests.swift" -o "$temporary/panel-test"
if [[ $# == 1 ]]; then mkdir -p "$1"; fi
"$temporary/panel-test" "$@"
