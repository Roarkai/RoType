#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
app_dir="$repo_dir/dist/RoType Voice.app"

"$repo_dir/scripts/build-app.sh" >/dev/null
"$repo_dir/scripts/build-app.sh" >/dev/null

codesign --verify --deep --strict "$app_dir"
test -f "$app_dir/Contents/Resources/ThirdParty/WhisperKit/LICENSE.txt"
test -f "$app_dir/Contents/Resources/ThirdParty/WhisperKit/NOTICES.txt"

print "Repeated app build passed: $app_dir"
