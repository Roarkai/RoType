#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
cd "$repo_dir"

luajit Tests/RimeIntegration/candidate_filter_test.lua
luajit Tests/RimeIntegration/candidate_filter_stream_test.lua
luajit Tests/RimeIntegration/simplified_only_filter_test.lua

zsh "$repo_dir/scripts/test-candidate-session.sh"
zsh "$repo_dir/scripts/test-rime-install.sh"
"$repo_dir/scripts/test-squirrel-integration.sh"
"$repo_dir/scripts/test-installer.sh"

"$repo_dir/scripts/test-user-experience.sh"

if command -v swiftlint >/dev/null 2>&1; then
  (cd "$repo_dir/Squirrel" && swiftlint lint --strict)
  swiftlint lint Sources/RoTypeApp Sources/RoTypeCore Sources/RoTypeTranslationService --strict
fi

for schema in Rime/rotype.schema.yaml Rime/rotype_flypy.schema.yaml; do
  ! grep -Eq 'traditionalization|s2t\.json|繁體|繁体' "$schema"
  grep -q 'simplifier@simplification' "$schema"
  grep -q 'lua_filter@\*rotype_simplified_only_filter' "$schema"
  grep -A1 -- '- name: simplification' "$schema" | grep -q 'reset: 1'
  grep -q 'option_name: simplification' "$schema"
  grep -q 'opencc_config: tw2s.json' "$schema"
done

swift test
