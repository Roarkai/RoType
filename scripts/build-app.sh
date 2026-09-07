#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
source "$repo_dir/scripts/codesign-with-retry.sh"
dist_dir="$repo_dir/dist"
app_dir="$dist_dir/洛克输入法设置.app"
staging_app_dir="$dist_dir/.洛克输入法设置.app.build"
translation_service="$dist_dir/RoTypeTranslationService"
staging_translation_service="$dist_dir/.RoTypeTranslationService.build"
legacy_app_dir="$dist_dir/洛克输入法.app"
contents_dir="$staging_app_dir/Contents"
release_dir="$repo_dir/.build/release"
icon_info=""

function remove_generated_app() {
  local target="$1"
  case "$target" in
    "$app_dir"|"$staging_app_dir"|"$translation_service"|"$staging_translation_service"|"$legacy_app_dir") ;;
    *)
      print -u2 "Refusing to remove unexpected path: $target"
      return 1
      ;;
  esac

  if [[ -e "$target" ]]; then
    chmod -R u+w "$target"
    rm -R "$target"
  fi
}

function cleanup_staging_app() {
  remove_generated_app "$staging_app_dir"
  remove_generated_app "$staging_translation_service"
  if [[ -n "$icon_info" ]]; then
    rm -f "$icon_info"
  fi
}

trap cleanup_staging_app EXIT

cd "$repo_dir"
swift build -c release --product RoTypeApp
swift build -c release --product RoTypeTranslationService
zsh "$repo_dir/scripts/build-voice-worker.sh"
voice_release="$repo_dir/.build/voice-worker/Build/Products/Release"

mkdir -p "$dist_dir"
remove_generated_app "$legacy_app_dir"
remove_generated_app "$staging_app_dir"
remove_generated_app "$translation_service"
remove_generated_app "$staging_translation_service"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$contents_dir/Helpers"
cp "$voice_release/RoTypeVoiceWorker" "$contents_dir/Helpers/RoTypeVoiceWorker"
# The standalone worker's Bundle.main is its executable directory, not the host app.
for bundle in "$voice_release"/*.bundle(N); do
  cp -R "$bundle" "$contents_dir/Helpers/"
done
mkdir -p "$contents_dir/Resources/Licenses/Voice"
for checkout in "$repo_dir/.build/voice-worker/SourcePackages/checkouts"/*(/N); do
  for license in "$checkout"/(LICENSE*|NOTICE*)(N.); do
    cp "$license" "$contents_dir/Resources/Licenses/Voice/${checkout:t}-${license:t}"
  done
done
cp "$release_dir/RoTypeApp" "$contents_dir/MacOS/LuokeInput"
cp "$repo_dir/Resources/Info.plist" "$contents_dir/Info.plist"
icon_info=$(mktemp)
xcrun actool \
  "$repo_dir/Squirrel/Assets.xcassets" \
  "$repo_dir/Squirrel/Rime.icon" \
  --compile "$contents_dir/Resources" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon Rime \
  --output-partial-info-plist "$icon_info" \
  --output-format human-readable-text \
  --warnings \
  --notices
rm -f "$icon_info"
icon_info=""
for bundle in "$release_dir"/*.bundle(N); do
  cp -R "$bundle" "$contents_dir/Resources/"
done

signing_identity=${ROTYPE_CODESIGN_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
  signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application: XIAO BIN \(DF7J2VBQD8\)/ { print $2; exit }')
fi
if [[ -z "$signing_identity" ]]; then
  print -u2 "Missing Developer ID Application identity. Set ROTYPE_CODESIGN_IDENTITY for a local development build."
  exit 1
fi

codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --entitlements "$repo_dir/Resources/RoTypeApp.entitlements" \
  --sign "$signing_identity" \
  "$staging_app_dir"
# Bootstrap nested resource bundles first, then restore the worker's role and
# seal the host WITHOUT --deep (which would replace the explicit worker ID).
codesign --force --options runtime --timestamp \
  --identifier im.roarkai.inputmethod.Luoke.asr \
  --entitlements "$repo_dir/Resources/TranslationWorker.entitlements" \
  --sign "$signing_identity" "$contents_dir/Helpers/RoTypeVoiceWorker"
codesign --force --options runtime --timestamp \
  --entitlements "$repo_dir/Resources/RoTypeApp.entitlements" \
  --sign "$signing_identity" "$staging_app_dir"
codesign --verify --strict \
  -R '=anchor apple generic and identifier "im.roarkai.inputmethod.Luoke.asr" and certificate leaf[subject.OU] = "DF7J2VBQD8"' \
  "$contents_dir/Helpers/RoTypeVoiceWorker"
cp "$release_dir/RoTypeTranslationService" "$staging_translation_service"
codesign \
  --force \
  --identifier im.roarkai.inputmethod.Luoke.translation \
  --options runtime \
  --timestamp \
  --entitlements "$repo_dir/Resources/TranslationWorker.entitlements" \
  --sign "$signing_identity" \
  "$staging_translation_service"
remove_generated_app "$app_dir"
mv "$staging_app_dir" "$app_dir"
mv "$staging_translation_service" "$translation_service"
trap - EXIT
print "Signed with: $signing_identity"
"$app_dir/Contents/Helpers/RoTypeVoiceWorker" --self-test
codesign --verify --deep --strict "$app_dir"
print "Built: $app_dir"
