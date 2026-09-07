#!/bin/zsh
set -euo pipefail
app=${1:?Pass an extracted installed input method app}
helper="$app/Contents/Helpers/洛克输入法设置.app"
temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT
for bundle in "$app" "$helper"; do
  if ! plutil -extract NSMicrophoneUsageDescription raw "$bundle/Contents/Info.plist" >/dev/null; then
    print -u2 "FAIL: missing microphone usage description: $bundle"
    exit 1
  fi
  codesign -d --entitlements :- "$bundle" > "$temporary" 2>/dev/null
  if [[ $(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' "$temporary" 2>/dev/null) != true ]]; then
    print -u2 "FAIL: missing microphone entitlement on TCC host/helper: $bundle"
    exit 1
  fi
done
print 'Voice microphone metadata passed for both TCC host and helper (user consent still required).'
