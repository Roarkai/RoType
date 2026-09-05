#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
app=${ROTYPE_SQUIRREL_APP:?Set ROTYPE_SQUIRREL_APP to an extracted current App fixture}
shared="$app/Contents/SharedSupport"
frameworks="$app/Contents/Frameworks"
temporary=$(mktemp -d)
trap 'rm -R "$temporary"' EXIT
mkdir -p "$temporary/bootstrap" "$temporary/build"

# A no-learning negative control, otherwise using the same shipped schema,
# dictionaries, simplification and final candidate filter as the product.
awk '
  /schema_id: rotype$/ { sub(/schema_id: rotype$/, "schema_id: rotype_learning_off") }
  { gsub(/enable_user_dict: true/, "enable_user_dict: false"); print }
' "$shared/rotype.schema.yaml" > "$temporary/bootstrap/rotype_learning_off.schema.yaml"
printf '%s\n' 'patch:' '  schema_list:' '    - schema: rotype' '    - schema: rotype_flypy' '    - schema: rotype_learning_off' \
  > "$temporary/bootstrap/default.custom.yaml"
"$app/Contents/MacOS/rime_deployer" --build "$temporary/bootstrap" "$shared" "$temporary/build"
for prebuilt in "$shared/build/"*(N); do
  if [[ ! -e "$temporary/build/${prebuilt:t}" ]]; then cp -R "$prebuilt" "$temporary/build/"; fi
done
xcrun clang++ -std=c++20 "$repo_dir/Tests/RimeIntegration/rime_learning_test.cc" \
  -I "$repo_dir/Squirrel/librime/src" "$frameworks/librime.1.dylib" \
  "$frameworks/rime-plugins/librime-lua.dylib" \
  -Wl,-rpath,"$frameworks" -Wl,-rpath,"$frameworks/rime-plugins" -o "$temporary/test"

run_case() {
  local profile=$1 schema=$2 action=$3
  mkdir -p "$temporary/$profile"
  "$temporary/test" "$shared" "$temporary/$profile" "$temporary/build" "$schema" "$action"
}

run_case control rotype_learning_off baseline
run_case control rotype_learning_off train
if run_case control rotype_learning_off verify > "$temporary/control-check.log" 2>&1; then
  print -u2 'FAIL: no-learning control unexpectedly passed'
  exit 1
else
  result=$?
  if [[ $result != 42 ]]; then
    cat "$temporary/control-check.log" >&2
    exit "$result"
  fi
fi
print 'Negative control rejected as expected.'
run_case learning rotype baseline
run_case learning rotype train
run_case learning rotype verify
print 'Learned selection survived a fresh process.'
run_case learning rotype_flypy verify
run_case flypy rotype_flypy baseline
run_case flypy rotype_flypy train
run_case flypy rotype_flypy verify
print 'Full pinyin and Flypy both learn, and share learned preferences.'
run_case number rotype number
run_case number rotype verify
run_case space rotype highlight-space
run_case space rotype verify
print 'Number-key and highlighted-space paths also preserve learning.'
run_case learning rotype reverse
run_case learning rotype verify-original
print 'A later preference can replace the earlier preference.'

# Paired controls: one selection really does learn, so the undo check cannot
# pass merely because a single selection had no effect in the first place.
run_case once rotype baseline
run_case once rotype once
run_case once rotype verify
run_case undo rotype baseline
run_case undo rotype undo
run_case undo rotype verify-original
print 'Immediate unhandled Backspace reverted the single learning transaction.'
run_case late rotype late-undo
run_case late rotype verify
print 'Boundary confirmed: Backspace after four seconds does not undo learning.'
run_case translation rotype baseline
run_case translation rotype translate
run_case translation rotype verify-no-translation
run_case forget rotype train
run_case forget rotype verify
run_case forget rotype forget
run_case forget rotype verify-forgotten
run_case forget rotype once
run_case forget rotype verify
print 'Local learning baseline passed (isolated data; no production profile access).'
