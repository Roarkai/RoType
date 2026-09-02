#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}

bash -n "$repo_dir/Installer/scripts/postinstall"
bash -n "$repo_dir/Installer/scripts/preinstall"
zsh -n "$repo_dir/scripts/build-installer.sh"
plutil -lint "$repo_dir/Installer/dev.rotype.voice.plist" >/dev/null
grep -q '/Library/Input Methods/Squirrel.app' "$repo_dir/Installer/scripts/postinstall"
grep -q '/Applications/RoType Voice.app' "$repo_dir/Installer/scripts/postinstall"
grep -q 'rotype-backups' "$repo_dir/Installer/scripts/postinstall"
grep -q '/Library/Input Methods/Squirrel.app' "$repo_dir/Installer/scripts/preinstall"
grep -q 'legacy_voice_app' "$repo_dir/Installer/scripts/postinstall"
grep -q 'dev.rotype.voice' "$repo_dir/Installer/dev.rotype.voice.plist"

print "Unified installer checks passed."
