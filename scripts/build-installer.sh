#!/bin/zsh
set -euo pipefail
export COPYFILE_DISABLE=1

repo_dir=${0:A:h:h}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_dir/Resources/Info.plist")
architecture=$(uname -m)
dist_dir="$repo_dir/dist"
staging_dir="$dist_dir/.installer-root"
output_pkg="$dist_dir/RoType-${version}-macOS-${architecture}.pkg"
squirrel_app="$repo_dir/Squirrel/build/Build/Products/Release/Squirrel.app"
voice_app="$dist_dir/RoType Voice.app"

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
  "$staging_dir/Library/Input Methods" \
  "$staging_dir/Library/Application Support/RoType"

/usr/bin/ditto --norsrc --noextattr "$voice_app" "$staging_dir/Applications/RoType Voice.app"
/usr/bin/ditto --norsrc --noextattr "$squirrel_app" "$staging_dir/Library/Input Methods/Squirrel.app"
/usr/bin/ditto --norsrc --noextattr "$repo_dir/Rime" "$staging_dir/Library/Application Support/RoType/Rime"
cp -X "$repo_dir/Installer/dev.rotype.voice.plist" "$staging_dir/Library/LaunchAgents/"
/bin/chmod -R u+w "$staging_dir"
/usr/bin/xattr -cr "$staging_dir"

signing_identity=${ROTYPE_CODESIGN_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
  signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/ { print $2; exit }')
fi
[[ -n "$signing_identity" ]] || signing_identity="-"

codesign \
  --force \
  --deep \
  --sign "$signing_identity" \
  --preserve-metadata=identifier,entitlements,flags,runtime \
  "$staging_dir/Library/Input Methods/Squirrel.app"

pkgbuild \
  --root "$staging_dir" \
  --scripts "$repo_dir/Installer/scripts" \
  --identifier dev.rotype.installer \
  --version "$version" \
  --install-location / \
  "$output_pkg"

safe_remove "$staging_dir"
print "Built: $output_pkg"
