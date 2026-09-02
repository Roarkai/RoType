#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
squirrel_dir="$repo_dir/Squirrel"

test -f "$squirrel_dir/LICENSE.txt"
grep -q 'GNU GENERAL PUBLIC LICENSE' "$squirrel_dir/LICENSE.txt"
grep -q 'rotype://settings' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'RoType 项目主页' "$squirrel_dir/sources/SquirrelInputController.swift"
plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$repo_dir/Resources/Info.plist" | grep -qx rotype
xcrun swiftc -parse "$squirrel_dir/sources/SquirrelInputController.swift"

print "Squirrel menu integration checks passed."
