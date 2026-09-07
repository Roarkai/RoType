#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}

bash -n "$repo_dir/Installer/scripts/postinstall"
bash -n "$repo_dir/Installer/scripts/preinstall"
bash -n "$repo_dir/Installer/scripts/normalize-input-method.sh"
zsh -n "$repo_dir/scripts/build-installer.sh"
zsh -n "$repo_dir/scripts/fetch-octagram-model.sh"
zsh -n "$repo_dir/scripts/test-translation-xpc.sh"
zsh -n "$repo_dir/scripts/test-xpc-isolation.sh"
zsh -n "$repo_dir/scripts/notarize-installer.sh"
grep -q 'Developer ID Application' "$repo_dir/scripts/build-app.sh"
grep -q 'Developer ID Installer' "$repo_dir/scripts/build-installer.sh"
grep -q -- '--options runtime' "$repo_dir/scripts/build-app.sh"
grep -q -- '--timestamp' "$repo_dir/scripts/build-app.sh"
grep -q 'RoTypeApp.entitlements' "$repo_dir/scripts/build-app.sh"
grep -q -- '--identifier im.roarkai.inputmethod.Luoke.translation' "$repo_dir/scripts/build-app.sh"
grep -q -- '--sign "$installer_identity"' "$repo_dir/scripts/build-installer.sh"
grep -q -- '--entitlements "$repo_dir/Squirrel/resources/Squirrel.entitlements"' "$repo_dir/scripts/build-installer.sh"
grep -q 'restore each nested product' "$repo_dir/scripts/build-installer.sh"
grep -q 'staged_input_method/Contents/Helpers/RoTypeTranslationService' "$repo_dir/scripts/build-installer.sh"
if grep -q -- '--preserve-metadata=identifier,entitlements' "$repo_dir/scripts/build-installer.sh"; then
  print -u2 "Release signing must not preserve Xcode's get-task-allow entitlement."
  exit 1
fi
grep -q 'notarytool submit' "$repo_dir/scripts/notarize-installer.sh"
grep -q 'stapler staple' "$repo_dir/scripts/notarize-installer.sh"
grep -q 'BundleIsRelocatable false' "$repo_dir/scripts/build-installer.sh"
grep -q 'make -C.*Squirrel.*release' "$repo_dir/scripts/build-installer.sh"
grep -q 'lsregister.*-u.*squirrel_app' "$repo_dir/scripts/build-installer.sh"
plutil -lint "$repo_dir/Installer/im.roarkai.inputmethod.Luoke.translation.plist" >/dev/null
grep -q '/Library/Input Methods/洛克输入法.app' "$repo_dir/Installer/scripts/postinstall"
grep -q 'Contents/Helpers/RoTypeTranslationService' "$repo_dir/Installer/im.roarkai.inputmethod.Luoke.translation.plist"
grep -q '<key>MachServices</key>' "$repo_dir/Installer/im.roarkai.inputmethod.Luoke.translation.plist"
if grep -q '洛克输入法设置.app' "$repo_dir/Installer/im.roarkai.inputmethod.Luoke.translation.plist"; then
  print -u2 "Settings must not run as a login LaunchAgent."
  exit 1
fi
grep -q 'legacy_standalone_app="$applications_dir/洛克输入法.app"' "$repo_dir/Installer/scripts/preinstall"
grep -q 'rm -R "$legacy_standalone_app"' "$repo_dir/Installer/scripts/preinstall"
grep -q 'legacy_system_voice_app="/Applications/RoType Voice.app"' "$repo_dir/Installer/scripts/postinstall"
grep -q 'Resources/AppIcon.icns.*staged_input_method/Contents/Resources/Rime.icns' "$repo_dir/scripts/build-installer.sh"
grep -q 'staged_input_method/Contents/Helpers/洛克输入法设置.app' "$repo_dir/scripts/build-installer.sh"
grep -q 'staged_input_method/Contents/Helpers/RoTypeTranslationService' "$repo_dir/scripts/build-installer.sh"
grep -q 'RoTypeTranslationService' "$repo_dir/scripts/build-app.sh"
! grep -Eq 'build-voice-app|staged_voice_app|RoTypeVoice.entitlements' "$repo_dir/scripts/build-installer.sh"
[[ ! -d "$repo_dir/ThirdParty/QwenVoiceRuntime" ]]
! grep -q 'launch-server.sh" stop' "$repo_dir/Installer/scripts/preinstall"
grep -q 'retirement_tool" --app' "$repo_dir/Installer/scripts/preinstall"
grep -q 'RetireVoice.swift' "$repo_dir/scripts/build-installer.sh"
grep -q '洛克语音输入.app' "$repo_dir/Installer/scripts/preinstall"
grep -q 'io.github.vladuzh.qwenscribe' "$repo_dir/Installer/scripts/preinstall"
grep -q 'test-xpc-isolation.sh' "$repo_dir/scripts/build-installer.sh"
grep -q -- '--scripts "$staged_scripts"' "$repo_dir/scripts/build-installer.sh"
if grep -q 'staging_dir/Applications/洛克输入法.app' "$repo_dir/scripts/build-installer.sh"; then
  print -u2 "Settings helper must not be installed as a standalone application."
  exit 1
fi
grep -q 'generate-menu-icon.swift' "$repo_dir/scripts/build-installer.sh"
grep -q 'rotypeABC22SmallRTemplate.pdf' "$repo_dir/scripts/build-installer.sh"
grep -q 'staged_input_method/Contents/SharedSupport' "$repo_dir/scripts/build-installer.sh"
grep -q 'rm -rf "$staged_input_method/Contents/SharedSupport"' "$repo_dir/scripts/build-installer.sh"
grep -q 'luna_pinyin.dict.yaml' "$repo_dir/scripts/build-installer.sh"
grep -q 'TWVariantsRev.ocd2' "$repo_dir/scripts/build-installer.sh"
grep -q 'fetch-octagram-model.sh' "$repo_dir/scripts/build-installer.sh"
grep -q 'zh-hant-t-essay-bgw.gram' "$repo_dir/scripts/build-installer.sh"
grep -q 'LICENSES/LGPL-3.0.txt' "$repo_dir/scripts/build-installer.sh"
grep -q '0488ebd6688f900a39200f2b794f2f99bcbf1e8fc27280ae4a2324b08b1559c1' "$repo_dir/scripts/fetch-octagram-model.sh"
grep -q 'rime_deployer.*--build' "$repo_dir/scripts/build-installer.sh"
if grep -q 'Library/Application Support/RoType/Rime' "$repo_dir/scripts/build-installer.sh"; then
  print -u2 "Factory Rime data must be supplied by the signed input method bundle."
  exit 1
fi
grep -q 'legacy_factory_data=' "$repo_dir/Installer/scripts/postinstall"
if grep -Eq 'killall (ControlCenter|TextInputMenuAgent|Squirrel)' "$repo_dir/Installer/scripts/postinstall" "$repo_dir/Installer/scripts/preinstall"; then
  print -u2 "Installer must not terminate system agents or unrelated Squirrel processes."
  exit 1
fi
if rg -n 'legacy_squirrel_app|rm .*Squirrel\.app' "$repo_dir/Installer/scripts"; then
  print -u2 "Installer must preserve genuine upstream Squirrel installations."
  exit 1
fi
if grep -q 'AppleEnabledInputSources' "$repo_dir/Sources/RoTypeApp/InputSourceManager.swift"; then
  print -u2 "Onboarding must not edit private HIToolbox preferences."
  exit 1
fi
grep -q 'rotype-backups' "$repo_dir/Squirrel/sources/Main.swift"
grep -q 'input_methods_dir="${ROTYPE_INPUT_METHODS_DIR:-/Library/Input Methods}"' "$repo_dir/Installer/scripts/preinstall"
grep -q 'legacy_rotype_bundle_id="com.roarkai.rotype.inputmethod"' "$repo_dir/Installer/scripts/preinstall"
grep -q '洛克输入法\*\.localized' "$repo_dir/Installer/scripts/preinstall"
grep -q 'relocated_rotype_app="$relocated_rotype_root/洛克输入法.app"' "$repo_dir/Installer/scripts/preinstall"
grep -q 'rm -R "$installed_rotype_app"' "$repo_dir/Installer/scripts/preinstall"
grep -q 'rm -R "$relocated_rotype_root"' "$repo_dir/Installer/scripts/preinstall"
grep -q 'Never modify /Library/Input Methods/Squirrel.app' "$repo_dir/Installer/scripts/preinstall"
grep -q 'backup_index > 3' "$repo_dir/Installer/scripts/preinstall"
grep -q 'active_gui_uids' "$repo_dir/Installer/scripts/postinstall"
grep -q 'home_for_user' "$repo_dir/Installer/scripts/postinstall"
parsed_home=$(printf '%s\n' 'NFSHomeDirectory: /Users/Test User' | /usr/bin/awk 'sub(/^[^:]*:[[:space:]]*/, "") { print; exit }')
[[ "$parsed_home" == '/Users/Test User' ]]
if grep -q 'NFSHomeDirectory.*awk.*print \$2' "$repo_dir/Installer/scripts/postinstall"; then
  print -u2 "Installer must preserve spaces in user home paths."
  exit 1
fi
enable_line=$(grep -n 'launchctl enable "gui/\$uid/\$translation_service"' "$repo_dir/Installer/scripts/postinstall" | cut -d: -f1)
bootstrap_line=$(grep -n 'launchctl bootstrap "gui/\$uid"' "$repo_dir/Installer/scripts/postinstall" | cut -d: -f1)
[[ "$enable_line" -lt "$bootstrap_line" ]]
grep -q 'launchctl print "gui/\$uid/\$translation_service"' "$repo_dir/Installer/scripts/postinstall"
if grep -q 'launchctl bootstrap.*|| true' "$repo_dir/Installer/scripts/postinstall"; then
  print -u2 "Translation LaunchAgent bootstrap failures must not be silent."
  exit 1
fi
grep -q 'input-source-setup-required' "$repo_dir/Installer/scripts/configure-user.sh"
bash "$repo_dir/scripts/test-install-setup.sh"
grep -q 'source "$script_dir/configure-user.sh"' "$repo_dir/Installer/scripts/postinstall"
grep -q 'finish_rotype_user_setup "$console_uid"' "$repo_dir/Installer/scripts/postinstall"
grep -q 'RoTypeFactoryDataMigration.run' "$repo_dir/Squirrel/sources/Main.swift"
grep -q 'normalize-input-method.sh' "$repo_dir/Installer/scripts/postinstall"

preinstall_fixture=$(mktemp -d)
fixture_input_methods="$preinstall_fixture/Input Methods"
fixture_applications="$preinstall_fixture/Applications"
fixture_backups="$preinstall_fixture/Backups"
mkdir -p \
  "$fixture_input_methods/Squirrel.app/Contents" \
  "$fixture_input_methods/洛克输入法.app/Contents/MacOS" \
  "$fixture_applications" \
  "$fixture_backups/20260101-000001" \
  "$fixture_backups/20260102-000001" \
  "$fixture_backups/20260103-000001" \
  "$fixture_backups/20260104-000001"
cat > "$fixture_input_methods/Squirrel.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>im.rime.inputmethod.Squirrel</string>
</dict></plist>
PLIST
print 'preserve upstream' > "$fixture_input_methods/Squirrel.app/upstream-marker"
cat > "$fixture_input_methods/洛克输入法.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>im.roarkai.inputmethod.Luoke</string>
</dict></plist>
PLIST
cat > "$fixture_input_methods/洛克输入法.app/Contents/MacOS/Squirrel" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$1" >> "$ROTYPE_COMMAND_LOG"
SCRIPT
chmod +x "$fixture_input_methods/洛克输入法.app/Contents/MacOS/Squirrel"
mkdir -p "$fixture_applications/洛克输入法.app/Contents/MacOS"
cat > "$fixture_applications/洛克输入法.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.rotype.voice</string>
</dict></plist>
PLIST
cat > "$fixture_applications/洛克输入法.app/Contents/MacOS/LuokeInput" <<'SCRIPT'
#!/bin/bash
sleep 30
SCRIPT
chmod +x "$fixture_applications/洛克输入法.app/Contents/MacOS/LuokeInput"
started_at=$SECONDS
ROTYPE_INPUT_METHODS_DIR="$fixture_input_methods" \
ROTYPE_APPLICATIONS_DIR="$fixture_applications" \
ROTYPE_BACKUP_ROOT="$fixture_backups" \
ROTYPE_ACTIVE_GUI_UIDS="$(id -u)" \
ROTYPE_SKIP_SESSION_OPERATIONS=1 \
ROTYPE_DIRECT_USER_COMMANDS=1 \
ROTYPE_QUIT_TIMEOUT_ATTEMPTS=20 \
ROTYPE_COMMAND_LOG="$preinstall_fixture/commands.log" \
  bash "$repo_dir/Installer/scripts/preinstall" >/dev/null
(( SECONDS - started_at < 5 ))
[[ "$(sed -n '1p' "$preinstall_fixture/commands.log")" == '--quit' ]]
! grep -q -- '--disable-input-source' "$preinstall_fixture/commands.log"
! pgrep -f "^$fixture_applications/洛克输入法.app/Contents/MacOS/LuokeInput --quit$" >/dev/null
test ! -e "$fixture_applications/洛克输入法.app"
test -f "$fixture_input_methods/Squirrel.app/upstream-marker"
test -d "$fixture_input_methods/洛克输入法.app"
[[ "$(find "$fixture_backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" == 3 ]]
find "$fixture_backups" -path '*/洛克输入法-输入源.app' -type d | grep -q .

legacy_fixture="$preinstall_fixture/legacy"
mkdir -p "$legacy_fixture/Input Methods/洛克输入法.app/Contents" "$legacy_fixture/Applications" "$legacy_fixture/Backups"
cat > "$legacy_fixture/Input Methods/洛克输入法.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.roarkai.rotype.inputmethod</string>
</dict></plist>
PLIST
ROTYPE_INPUT_METHODS_DIR="$legacy_fixture/Input Methods" \
ROTYPE_APPLICATIONS_DIR="$legacy_fixture/Applications" \
ROTYPE_BACKUP_ROOT="$legacy_fixture/Backups" \
ROTYPE_SKIP_SESSION_OPERATIONS=1 \
  bash "$repo_dir/Installer/scripts/preinstall" >/dev/null
test ! -e "$legacy_fixture/Input Methods/洛克输入法.app"
rm -R "$preinstall_fixture"

normalize_fixture=$(mktemp -d)
relocated_fixture="$normalize_fixture/洛克输入法-1.localized/洛克输入法.app"
mkdir -p "$relocated_fixture/Contents/MacOS"
cat > "$relocated_fixture/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>im.roarkai.inputmethod.Luoke</string>
</dict></plist>
PLIST
touch "$relocated_fixture/Contents/MacOS/Squirrel"
ROTYPE_INPUT_METHODS_DIR="$normalize_fixture" \
  bash "$repo_dir/Installer/scripts/normalize-input-method.sh"
test -f "$normalize_fixture/洛克输入法.app/Contents/MacOS/Squirrel"
test ! -e "$normalize_fixture/洛克输入法-1.localized"
rm -R "$normalize_fixture"

grep -q 'im.roarkai.inputmethod.Luoke.translation' "$repo_dir/Installer/im.roarkai.inputmethod.Luoke.translation.plist"
grep -q 'retired_helper_service="im.roarkai.inputmethod.Luoke.helper"' "$repo_dir/Installer/scripts/postinstall"

print "Unified installer checks passed."
