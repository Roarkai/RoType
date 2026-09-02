#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
squirrel_app=${ROTYPE_SQUIRREL_APP:?Set ROTYPE_SQUIRREL_APP to an extracted Squirrel.app path}
deployer="$squirrel_app/Contents/MacOS/rime_deployer"
shared_data="$squirrel_app/Contents/SharedSupport"

[[ -x "$deployer" ]]
[[ -d "$shared_data" ]]

user_dir=$(mktemp -d)
staging_dir=$(mktemp -d)
trap 'rm -R "$user_dir" "$staging_dir"' EXIT

ROTYPE_RIME_DIR="$user_dir" "$repo_dir/scripts/install-rime.sh" >/dev/null
"$deployer" --build "$user_dir" "$shared_data" "$staging_dir"

[[ -f "$staging_dir/rotype_zh.table.bin" ]]
[[ -f "$staging_dir/rotype_en.table.bin" ]]
[[ -f "$staging_dir/rotype.schema.yaml" ]]
[[ -f "$staging_dir/rotype_flypy.schema.yaml" ]]
[[ -f "$staging_dir/rotype_flypy.prism.bin" ]]

print "Rime deployment test passed: full-pinyin, Xiaohe and English data compiled."
