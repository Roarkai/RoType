#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
app_dir="$repo_dir/dist/洛克输入法设置.app"
translation_service="$repo_dir/dist/RoTypeTranslationService"

"$repo_dir/scripts/build-app.sh" >/dev/null
"$repo_dir/scripts/build-app.sh" >/dev/null

codesign --verify --deep --strict "$app_dir"
codesign --verify --strict "$translation_service"
codesign -dv --verbose=4 "$translation_service" 2>&1 | grep -q 'Identifier=im.roarkai.inputmethod.Luoke.translation'
test -x "$translation_service"
! codesign -d --entitlements :- "$app_dir" 2>/dev/null | grep -q 'com.apple.security.device.audio-input'
! codesign -d --entitlements :- "$app_dir" 2>/dev/null | grep -q 'com.apple.security.network.client'
! test -d "$app_dir/Contents/Resources/ThirdParty/WhisperKit"
test -f "$app_dir/Contents/Resources/Rime.icns"
test -f "$app_dir/Contents/Resources/Assets.car"
plutil -extract CFBundleDisplayName raw "$app_dir/Contents/Info.plist" | grep -qx '洛克输入法设置'
plutil -extract CFBundleIdentifier raw "$app_dir/Contents/Info.plist" | grep -qx 'im.roarkai.inputmethod.Luoke.helper'
plutil -extract CFBundleExecutable raw "$app_dir/Contents/Info.plist" | grep -qx LuokeInput
plutil -extract CFBundleIconFile raw "$app_dir/Contents/Info.plist" | grep -qx Rime
plutil -extract CFBundleIconName raw "$app_dir/Contents/Info.plist" | grep -qx Rime
plutil -extract LSUIElement raw "$app_dir/Contents/Info.plist" | grep -qx true
! plutil -extract NSMicrophoneUsageDescription raw "$app_dir/Contents/Info.plist" >/dev/null 2>&1

print "Repeated app build without voice capabilities passed: $app_dir"
