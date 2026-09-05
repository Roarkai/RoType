#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
rime_dir=${ROTYPE_RIME_DIR:-"$HOME/Library/Rime"}
backup_root="$rime_dir/rotype-backups"
files=(
  rotype.schema.yaml
  rotype_flypy.schema.yaml
  rotype_en.schema.yaml
  rotype_zh.dict.yaml
  rotype_en.dict.yaml
)

mkdir -p "$rime_dir/lua" "$backup_root"
backup_dir=$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S).XXXXXX")
for file in $files; do
  if [[ -f "$rime_dir/$file" ]]; then
    cp "$rime_dir/$file" "$backup_dir/$file"
  fi
  cp "$repo_dir/Rime/$file" "$rime_dir/$file"
done

lua_files=(
  rotype_candidate_session.lua
  rotype_candidate_filter.lua
  rotype_bilingual_translator.lua
  rotype_dynamic_bilingual_filter.lua
  rotype_dynamic_refresh.lua
  rotype_english_echo.lua
  rotype_full_translation_commit.lua
  rotype_simplified_only_filter.lua
)
for file in $lua_files; do
  if [[ -f "$rime_dir/lua/$file" ]]; then
    cp "$rime_dir/lua/$file" "$backup_dir/$file"
  fi
  cp "$repo_dir/Rime/lua/$file" "$rime_dir/lua/$file"
done

if [[ ! -f "$rime_dir/default.custom.yaml" ]]; then
  cp "$repo_dir/Rime/default.custom.yaml" "$rime_dir/default.custom.yaml"
  default_config_message="Created default.custom.yaml with the RoType schema enabled."
else
  default_config_message="Kept existing default.custom.yaml unchanged. Add 'rotype' and 'rotype_flypy' under patch/schema_list if the RoType schemas are not listed."
fi

print "Installed RoType Rime files into: $rime_dir"
print "Existing RoType files, if any, were copied to: $backup_dir"
print "$default_config_message"
print "测试前请从洛克输入法菜单选择“重新部署”。"
