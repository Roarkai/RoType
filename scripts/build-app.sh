#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
dist_dir="$repo_dir/dist"
app_dir="$dist_dir/RoType Voice.app"
staging_app_dir="$dist_dir/.RoType Voice.app.build"
contents_dir="$staging_app_dir/Contents"
release_dir="$repo_dir/.build/release"
whisper_checkout="$repo_dir/.build/checkouts/argmax-oss-swift"

function remove_generated_app() {
  local target="$1"
  case "$target" in
    "$app_dir"|"$staging_app_dir") ;;
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
}

trap cleanup_staging_app EXIT

cd "$repo_dir"
swift build -c release --product RoTypeVoice

mkdir -p "$dist_dir"
remove_generated_app "$staging_app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$release_dir/RoTypeVoice" "$contents_dir/MacOS/RoTypeVoice"
cp "$repo_dir/Resources/Info.plist" "$contents_dir/Info.plist"
mkdir -p "$contents_dir/Resources/ThirdParty/WhisperKit"
cp "$repo_dir/THIRD_PARTY_NOTICES.md" "$contents_dir/Resources/ThirdParty/"
cp "$whisper_checkout/LICENSE" "$contents_dir/Resources/ThirdParty/WhisperKit/LICENSE.txt"
cp "$whisper_checkout/NOTICES" "$contents_dir/Resources/ThirdParty/WhisperKit/NOTICES.txt"

for bundle in "$release_dir"/*.bundle(N); do
  cp -R "$bundle" "$contents_dir/Resources/"
done

signing_identity=${ROTYPE_CODESIGN_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
  signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/ { print $2; exit }')
fi
if [[ -z "$signing_identity" ]]; then
  signing_identity="-"
fi

codesign --force --deep --sign "$signing_identity" "$staging_app_dir"
remove_generated_app "$app_dir"
mv "$staging_app_dir" "$app_dir"
trap - EXIT
print "Signed with: $signing_identity"
print "Built: $app_dir"
