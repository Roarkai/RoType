#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
squirrel_app=${ROTYPE_SQUIRREL_APP:?Set ROTYPE_SQUIRREL_APP to an extracted Squirrel.app path}
deployer="$squirrel_app/Contents/MacOS/rime_deployer"
shared_data="$squirrel_app/Contents/SharedSupport"

[[ -x "$deployer" ]]
[[ -d "$shared_data" ]]
[[ -f "$shared_data/rotype.schema.yaml" ]]
[[ -f "$shared_data/rotype_flypy.schema.yaml" ]]
[[ -f "$shared_data/lua/rotype_candidate_filter.lua" ]]
[[ -f "$shared_data/zh-hant-t-essay-bgw.gram" ]]

grep -A3 '^schema_list:' "$shared_data/default.yaml" | grep -q 'schema: rotype'

user_dir=$(mktemp -d)
staging_dir=$(mktemp -d)
test_dir=$(mktemp -d)
test_binary="$test_dir/rime_composition_test"
trap 'rm -R "$user_dir" "$staging_dir" "$test_dir"' EXIT

# Exercise an old custom schema's imports without changing any real user files.
/usr/bin/awk '
  /schema_id: rotype$/ { sub(/schema_id: rotype$/, "schema_id: rotype_compat") }
  /rotype_candidate_session/ {
    print "    - lua_processor@*rotype_full_translation_commit"
    print "    - lua_processor@*rotype_dynamic_refresh"
    next
  }
  /rotype_candidate_filter/ { sub(/rotype_candidate_filter/, "rotype_dynamic_bilingual_filter") }
  { print }
  /^  translators:/ { print "    - lua_translator@*rotype_bilingual_translator" }
' "$shared_data/rotype.schema.yaml" > "$user_dir/rotype_compat.schema.yaml"
printf '%s\n' 'patch:' '  schema_list:' '    - schema: rotype' '    - schema: rotype_flypy' '    - schema: rotype_compat' > "$user_dir/default.custom.yaml"

"$deployer" --build "$user_dir" "$shared_data" "$staging_dir"

runtime_data="$staging_dir"
# A packaged App already contains dictionaries. Keep freshly compiled custom
# schemas in staging, and fill only missing files from its prebuilt data.
# Switching the entire runtime to shared/build would silently lose rotype_compat.
for prebuilt in "$shared_data/build/"*(N); do
  if [[ ! -e "$runtime_data/${prebuilt:t}" ]]; then
    /bin/cp -R "$prebuilt" "$runtime_data/"
  fi
done
[[ -f "$runtime_data/rotype_zh.table.bin" ]]
[[ -f "$runtime_data/rotype_en.table.bin" ]]
[[ -f "$runtime_data/rotype.schema.yaml" ]]
[[ -f "$runtime_data/rotype_flypy.schema.yaml" ]]
[[ -f "$runtime_data/rotype_flypy.prism.bin" ]]

frameworks="$squirrel_app/Contents/Frameworks"
xcrun clang++ -std=c++20 \
  "$repo_dir/Tests/RimeIntegration/rime_composition_test.cc" \
  -I "$repo_dir/Squirrel/librime/src" \
  "$frameworks/librime.1.dylib" \
  "$frameworks/rime-plugins/librime-lua.dylib" \
  -Wl,-rpath,"$frameworks" \
  -Wl,-rpath,"$frameworks/rime-plugins" \
  -o "$test_binary"

"$test_binary" "$shared_data" "$user_dir" "$runtime_data"

if [[ "${ROTYPE_RIME_BENCHMARK:-0}" == 1 ]]; then
  xcrun clang++ -std=c++20 "$repo_dir/Tests/RimeIntegration/rime_latency_benchmark.cc" \
    -I "$repo_dir/Squirrel/librime/src" "$frameworks/librime.1.dylib" \
    "$frameworks/rime-plugins/librime-lua.dylib" \
    -Wl,-rpath,"$frameworks" -Wl,-rpath,"$frameworks/rime-plugins" \
    -o "$test_dir/rime_latency_benchmark"
  "$test_dir/rime_latency_benchmark" "$shared_data" "$user_dir" "$runtime_data"
fi

print "Rime deployment test passed: schemas compiled and segmented full translation verified."
