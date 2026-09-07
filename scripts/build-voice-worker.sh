#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
cd "$repo_dir/VoiceRuntime"
xcodebuild -scheme RoTypeVoiceRuntime -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$repo_dir/.build/voice-worker" \
  -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO build
"$repo_dir/.build/voice-worker/Build/Products/Release/RoTypeVoiceWorker" --self-test
