#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
temporary=$(mktemp -d)
fixture_pid=""
cleanup() {
  if [[ -n "$fixture_pid" ]]; then
    /bin/kill -TERM "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  /bin/rm -R "$temporary"
}
trap cleanup EXIT
identity=${ROTYPE_CODESIGN_IDENTITY:-'Developer ID Application: XIAO BIN (DF7J2VBQD8)'}
xcrun swiftc "$repo_dir/Tests/InputMethodUpgrade/Fixture.swift" -o "$temporary/Fixture"
xcrun swiftc "$repo_dir/Squirrel/sources/RoTypeProcessTrust.swift" \
  "$repo_dir/Tests/InputMethodUpgrade/Probe.swift" -o "$temporary/probe"
for version in 1 2; do
  app="$temporary/v$version.app"
  mkdir -p "$app/Contents/MacOS"
  cp "$temporary/Fixture" "$app/Contents/MacOS/Fixture"
  /usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string im.roarkai.inputmethod.Luoke "$app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleExecutable -string Fixture "$app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleVersion -string "$version" "$app/Contents/Info.plist"
  codesign --force --timestamp=none --sign "$identity" "$app"
done
app="$temporary/v1.app"
"$app/Contents/MacOS/Fixture" &
fixture_pid=$!
sleep 1
"$temporary/probe" "$fixture_pid" "$app" allow
# Even a legitimate signed bundle at a different path cannot authorize a quit.
"$temporary/probe" "$fixture_pid" "$temporary/v2.app" deny
# Atomically replace the signed executable while its previous image is running.
/bin/mv -f "$temporary/v2.app/Contents/MacOS/Fixture" "$app/Contents/MacOS/Fixture"
/bin/cp "$temporary/v2.app/Contents/Info.plist" "$app/Contents/Info.plist"
/bin/cp "$temporary/v2.app/Contents/_CodeSignature/CodeResources" "$app/Contents/_CodeSignature/CodeResources"
codesign --verify --strict "$app"
"$temporary/probe" "$fixture_pid" "$app" allow
# A tampered replacement must never qualify for the upgrade-only fallback.
/usr/bin/plutil -replace CFBundleVersion -string tampered "$app/Contents/Info.plist"
"$temporary/probe" "$fixture_pid" "$app" deny
/usr/bin/plutil -replace CFBundleVersion -string 2 "$app/Contents/Info.plist"
codesign --verify --strict "$app"
"$temporary/probe" "$fixture_pid" "$app" terminate
wait "$fixture_pid" 2>/dev/null || true
fixture_pid=""
print 'Signed running-process replacement and termination checks passed.'
