#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
temporary=$(mktemp -d)
trap 'rm -R "$temporary"' EXIT
mkdir -p "$temporary/rime/lua" "$temporary/home"
printf '%s\n' '# user settings' 'patch: {}' > "$temporary/rime/default.custom.yaml"
printf '%s\n' '-- user module' > "$temporary/rime/lua/user_module.lua"
printf '%s\n' 'previous schema' > "$temporary/rime/rotype.schema.yaml"
cp "$temporary/rime/default.custom.yaml" "$temporary/settings-before"
cp "$temporary/rime/lua/user_module.lua" "$temporary/module-before"
HOME="$temporary/home" ROTYPE_RIME_DIR="$temporary/rime" zsh "$repo_dir/scripts/install-rime.sh" > "$temporary/install.log"
cmp "$temporary/settings-before" "$temporary/rime/default.custom.yaml"
cmp "$temporary/module-before" "$temporary/rime/lua/user_module.lua"
for module in rotype_candidate_session rotype_candidate_filter rotype_dynamic_bilingual_filter \
  rotype_dynamic_refresh rotype_full_translation_commit rotype_bilingual_translator; do
  [[ -f "$temporary/rime/lua/$module.lua" ]]
done
[[ ! -d "$temporary/home/Library/Caches/RoType/TranslationBridge" ]]
grep -qx 'previous schema' "$temporary/rime/rotype-backups/"*/rotype.schema.yaml
print 'Rime install passed: new modules copied, prior schema backed up, user settings/modules preserved.'
