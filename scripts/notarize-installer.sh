#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_dir/Resources/Info.plist")
architecture=$(uname -m)
pkg="$repo_dir/dist/洛克输入法-${version}-macOS-${architecture}.pkg"
profile=${ROTYPE_NOTARY_PROFILE:-RoType-notary}

if [[ ! -f "$pkg" ]]; then
  print -u2 "Missing installer: $pkg"
  print -u2 "Run ./scripts/build-installer.sh first."
  exit 1
fi

pkgutil --check-signature "$pkg" | grep -q 'Developer ID Installer'
xcrun notarytool submit "$pkg" --keychain-profile "$profile" --no-s3-acceleration --wait
xcrun stapler staple "$pkg"
xcrun stapler validate "$pkg"
spctl --assess --type install --verbose=4 "$pkg"

print "Notarized: $pkg"
