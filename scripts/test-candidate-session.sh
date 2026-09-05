#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
temporary=$(mktemp -d)
trap 'rm -R "$temporary"' EXIT
xcrun swiftc -import-objc-header "$repo_dir/Shared/RoTypeXPCProtocol/include/RoTypeTranslationXPCProtocol.h" \
  "$repo_dir/Sources/RoTypeCore/DynamicTranslationProtocol.swift" \
  "$repo_dir/Squirrel/sources/RoTypeTranslationClient.swift" \
  "$repo_dir/Squirrel/sources/RoTypeCandidateTranslationSession.swift" \
  "$repo_dir/Tests/CandidateTranslation/SessionTests.swift" -o "$temporary/test"
"$temporary/test"
