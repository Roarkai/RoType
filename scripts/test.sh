#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
cd "$repo_dir"

luajit Tests/RimeIntegration/bilingual_translator_test.lua
luajit Tests/RimeIntegration/dynamic_bilingual_filter_test.lua
luajit Tests/RimeIntegration/simplified_only_filter_test.lua

"$repo_dir/scripts/test-squirrel-integration.sh"

for schema in Rime/rotype.schema.yaml Rime/rotype_flypy.schema.yaml; do
  ! grep -Eq 'traditionalization|s2t\.json|繁體|繁体' "$schema"
  grep -q 'simplifier@simplification' "$schema"
  grep -q 'lua_filter@\*rotype_simplified_only_filter' "$schema"
  grep -A1 -- '- name: simplification' "$schema" | grep -q 'reset: 1'
  grep -q 'option_name: simplification' "$schema"
  grep -q 'opencc_config: tw2s.json' "$schema"
done

swift test
