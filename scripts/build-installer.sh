#!/bin/zsh
set -euo pipefail
export COPYFILE_DISABLE=1

repo_dir=${0:A:h:h}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_dir/Resources/Info.plist")
architecture=$(uname -m)
dist_dir="$repo_dir/dist"
staging_dir="$dist_dir/.installer-root"
output_pkg="$dist_dir/洛克输入法-${version}-macOS-${architecture}.pkg"
squirrel_app="$repo_dir/Squirrel/build/Build/Products/Release/Squirrel.app"
settings_helper="$dist_dir/洛克输入法设置.app"
translation_service="$dist_dir/RoTypeTranslationService"
staged_input_method="$staging_dir/Library/Input Methods/洛克输入法.app"
component_dir=$(mktemp -d)
component_plist="$component_dir/components.plist"
staged_scripts="$component_dir/scripts"
trap '/bin/rm -R "$component_dir"' EXIT

safe_remove() {
  local target="$1"
  case "$target" in
    "$staging_dir"|"$output_pkg") ;;
    *) print -u2 "Refusing to remove unexpected path: $target"; return 1 ;;
  esac
  if [[ -e "$target" ]]; then
    chmod -R u+w "$target"
    rm -R "$target"
  fi
}

"$repo_dir/scripts/build-app.sh"
# Fixture-only endpoint selection must never enter the distributable worker.
if /usr/bin/strings "$translation_service" | /usr/bin/grep -F 'im.roarkai.inputmethod.Luoke.translation.test.' >/dev/null; then
  print -u2 'Refusing to package an XPC integration fixture as the production worker.'
  exit 1
fi
zsh "$repo_dir/scripts/test-input-method-upgrade.sh"
zsh "$repo_dir/scripts/test-voice-retirement.sh"
zsh "$repo_dir/scripts/test-xpc-isolation.sh"
octagram_model=$("$repo_dir/scripts/fetch-octagram-model.sh")

# Keep the input method bundle version in lockstep with the installer. A stale
# prebuilt Squirrel.app can leave macOS with an invalid cached input source.
make -C "$repo_dir/Squirrel" release

if [[ ! -d "$squirrel_app" ]]; then
  print -u2 "Missing Squirrel Release build: $squirrel_app"
  print -u2 "Run 'SQUIRREL_BUNDLED_RECIPES=:preset bash Squirrel/action-install.sh' and 'make -C Squirrel release' first."
  exit 1
fi

safe_remove "$staging_dir"
safe_remove "$output_pkg"
mkdir -p \
  "$staging_dir/Applications" \
  "$staging_dir/Library/LaunchAgents" \
  "$staging_dir/Library/Input Methods"

/usr/bin/ditto --norsrc --noextattr "$squirrel_app" "$staged_input_method"
/bin/mkdir -p "$staged_input_method/Contents/Helpers"
/usr/bin/ditto --norsrc --noextattr "$settings_helper" "$staged_input_method/Contents/Helpers/洛克输入法设置.app"
/bin/cp -X "$translation_service" "$staged_input_method/Contents/Helpers/RoTypeTranslationService"
/bin/rm -rf "$staged_input_method/Contents/SharedSupport"
/bin/mkdir -p "$staged_input_method/Contents/SharedSupport/opencc"
for factory_file in \
  default.yaml \
  essay.txt \
  key_bindings.yaml \
  luna_pinyin.dict.yaml \
  pinyin.yaml \
  punctuation.yaml \
  symbols.yaml
do
  /bin/cp -X "$repo_dir/Squirrel/data/plum/$factory_file" "$staged_input_method/Contents/SharedSupport/"
done
/bin/cp -X "$repo_dir/Squirrel/data/squirrel.yaml" "$staged_input_method/Contents/SharedSupport/squirrel.yaml"
for opencc_file in \
  tw2s.json \
  TSPhrases.ocd2 \
  TSCharacters.ocd2 \
  TWVariantsRevPhrases.ocd2 \
  TWVariantsRev.ocd2
do
  /bin/cp -X "$repo_dir/Squirrel/data/opencc/$opencc_file" "$staged_input_method/Contents/SharedSupport/opencc/"
done
/usr/bin/ditto --norsrc --noextattr "$repo_dir/Rime" "$staged_input_method/Contents/SharedSupport"
/usr/bin/install -m 0644 "$octagram_model" "$staged_input_method/Contents/SharedSupport/zh-hant-t-essay-bgw.gram"
/bin/mkdir -p "$staged_input_method/Contents/Resources/Licenses"
/bin/cp -X "$repo_dir/LICENSES/LGPL-3.0.txt" "$staged_input_method/Contents/Resources/Licenses/"
/bin/cp -X "$repo_dir/THIRD_PARTY_NOTICES.md" "$staged_input_method/Contents/Resources/"
/bin/rm -f "$staged_input_method/Contents/SharedSupport/default.custom.yaml"
/bin/rm -rf "$staged_input_method/Contents/SharedSupport/build"
/bin/mkdir -p "$component_dir/rime-user"
/bin/cp -X "$repo_dir/Rime/default.custom.yaml" "$component_dir/rime-user/default.custom.yaml"
"$staged_input_method/Contents/MacOS/rime_deployer" --build \
  "$component_dir/rime-user" \
  "$staged_input_method/Contents/SharedSupport" \
  "$staged_input_method/Contents/SharedSupport/build"
# Xcode's inherited Squirrel asset catalog can retain the upstream app icon.
# Override only the Dock/Finder icon in the staged bundle; the monochrome
# The Template filename makes AppKit tint the monochrome menu icon correctly
# for light, dark, and wallpaper-backed menu bars.
/bin/cp -X "$repo_dir/Resources/AppIcon.icns" "$staged_input_method/Contents/Resources/Rime.icns"
xcrun swift "$repo_dir/scripts/generate-menu-icon.swift" \
  "$staged_input_method/Contents/Resources/rotypeMenu16Template.pdf"
cp -X "$repo_dir/Installer/im.roarkai.inputmethod.Luoke.translation.plist" "$staging_dir/Library/LaunchAgents/"
/bin/chmod -R u+w "$staging_dir"
/usr/bin/xattr -cr "$staging_dir"

signing_identity=${ROTYPE_CODESIGN_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
  signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application: XIAO BIN \(DF7J2VBQD8\)/ { print $2; exit }')
fi
if [[ -z "$signing_identity" ]]; then
  print -u2 "Missing Developer ID Application identity."
  exit 1
fi

installer_identity=${ROTYPE_INSTALLER_IDENTITY:-}
if [[ -z "$installer_identity" ]]; then
  installer_identity=$(security find-identity -v 2>/dev/null | awk '/Developer ID Installer: XIAO BIN \(DF7J2VBQD8\)/ { print $2; exit }')
fi
if [[ -z "$installer_identity" ]]; then
  print -u2 "Missing Developer ID Installer identity."
  exit 1
fi

# Squirrel ships executable deployment tools that Xcode's local signature does
# not seal for Developer ID distribution. Bootstrap-sign the complete tree,
# then restore each nested product's own identity and seal the root last.
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --entitlements "$repo_dir/Squirrel/resources/Squirrel.entitlements" \
  --sign "$signing_identity" \
  "$staged_input_method"
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --entitlements "$repo_dir/Resources/RoTypeApp.entitlements" \
  --sign "$signing_identity" \
  "$staged_input_method/Contents/Helpers/洛克输入法设置.app"
codesign \
  --force \
  --identifier im.roarkai.inputmethod.Luoke.translation \
  --options runtime \
  --timestamp \
  --entitlements "$repo_dir/Resources/RoTypeApp.entitlements" \
  --sign "$signing_identity" \
  "$staged_input_method/Contents/Helpers/RoTypeTranslationService"
codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$repo_dir/Squirrel/resources/Squirrel.entitlements" \
  --sign "$signing_identity" \
  "$staged_input_method"

# Component packages relocate matching bundle identifiers by default. RoType
# deliberately migrates legacy per-user installs after the payload is placed,
# so every bundled component must remain at its declared system path.
pkgbuild --analyze --root "$staging_dir" "$component_plist"
component_index=0
while /usr/libexec/PlistBuddy -c "Print :$component_index:RootRelativeBundlePath" "$component_plist" >/dev/null 2>&1; do
  /usr/libexec/PlistBuddy -c "Set :$component_index:BundleIsRelocatable false" "$component_plist"
  component_index=$((component_index + 1))
done
/usr/bin/ditto --norsrc --noextattr "$repo_dir/Installer/scripts" "$staged_scripts"
/usr/bin/xattr -cr "$staged_scripts"
xcrun swiftc -O "$repo_dir/Installer/tools/RetireVoice.swift" -o "$staged_scripts/retire-voice"
codesign --force --options runtime --timestamp --identifier im.roarkai.inputmethod.Luoke.retirement \
  --sign "$signing_identity" "$staged_scripts/retire-voice"

pkgbuild \
  --sign "$installer_identity" \
  --root "$staging_dir" \
  --component-plist "$component_plist" \
  --scripts "$staged_scripts" \
  --identifier dev.rotype.installer \
  --version "$version" \
  --install-location / \
  "$output_pkg"

safe_remove "$staging_dir"
/bin/rm -R "$component_dir"
trap - EXIT

# xcodebuild registers its Release product with LaunchServices. Leaving that
# ad-hoc development copy registered beside the signed installed copy creates
# two input sources with the same ID, so the menu can resolve the wrong one.
lsregister_path="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$lsregister_path" ]]; then
  "$lsregister_path" -u "$squirrel_app" >/dev/null 2>&1 || true
fi
print "Built: $output_pkg"
