#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
info_plist="$repo_dir/Resources/Info.plist"
setup_view="$repo_dir/Sources/RoTypeApp/TranslationSetupView.swift"
privacy_view="$repo_dir/Sources/RoTypeApp/PrivacyPane.swift"
input_source="$repo_dir/Sources/RoTypeApp/InputSourceManager.swift"
verification_client="$repo_dir/Sources/RoTypeApp/ControllerInputVerificationClient.swift"
translation_backend="$repo_dir/Sources/RoTypeTranslationService/SystemTranslationBackend.swift"
translation_service="$repo_dir/Sources/RoTypeTranslationService/TranslationXPCService.swift"
translation_client="$repo_dir/Squirrel/sources/RoTypeTranslationClient.swift"

plutil -extract LSUIElement raw "$info_plist" | grep -qx true
plutil -extract CFBundleIconName raw "$info_plist" | grep -qx Rime
! plutil -extract NSMicrophoneUsageDescription raw "$info_plist" >/dev/null 2>&1
grep -q 'xcrun actool' "$repo_dir/scripts/build-app.sh"
grep -q 'Squirrel/Rime.icon' "$repo_dir/scripts/build-app.sh"
grep -Fq 'private let titles = ["输入法", "本地翻译"]' "$setup_view"
grep -q 'InputSourceSetupPane' "$setup_view"
# Setup completion, resume, and optional translation are exercised by RoTypeAppTests.
grep -q 'im.roarkai.inputmethod.Luoke.Hans' "$input_source"
grep -q 'TISCopyCurrentKeyboardInputSource' "$input_source"
grep -q 'currentIdentifier: currentIdentifier' "$input_source"
grep -q 'controllerHandledInput: controllerHandledInput' "$input_source"
grep -q 'verificationRequestID = UUID().uuidString' "$input_source"
grep -q 'ControllerInputVerificationClient' "$input_source"
grep -q 'controllerInputGeneration' "$verification_client"
grep -q 'inputSource.refreshCurrentState()' "$setup_view"
grep -q '在这里试打 nihao' "$setup_view"
if grep -q 'AppleEnabledInputSources' "$input_source"; then
  echo "FAIL: settings must use public TIS operations only"
  exit 1
fi
grep -q 'resetSession(for: direction)' "$translation_backend"
grep -q 'RoTypeTranslationXPCProtocol' "$translation_service"
grep -q 'SecCodeCheckValidity' "$translation_service"
if grep -q 'ROTYPE_ALLOW_UNSIGNED_XPC' "$translation_service"; then
  echo "FAIL: production worker must not contain an environment-controlled authentication bypass"
  exit 1
fi
grep -q 'im.roarkai.inputmethod.Luoke.helper' "$translation_service"
grep -q 'return .settingsHelper' "$translation_service"
grep -q 'generation <= latest' "$translation_service"
grep -q 'Apple 可能收集不含原文和译文' "$privacy_view"
[[ ! -f "$repo_dir/Sources/RoTypeApp/VoiceSettingsPane.swift" ]]
[[ ! -f "$repo_dir/Sources/RoTypeApp/VoiceModelManager.swift" ]]
grep -q 'NSXPCConnection(machServiceName:' "$translation_client"
grep -q 'IsSecureEventInputEnabled' "$repo_dir/Squirrel/sources/SquirrelInputController.swift"
grep -q 'recordControllerInput' "$translation_client"
grep -q 'setActivationPolicy(.accessory)' "$repo_dir/Sources/RoTypeApp/main.swift"
if grep -q 'setActivationPolicy(.regular)' "$repo_dir/Sources/RoTypeApp/main.swift"; then
  echo "FAIL: embedded settings helper must not create a Dock icon"
  exit 1
fi
grep -q 'SecCodeCheckValidity' "$repo_dir/Sources/RoTypeApp/main.swift"
grep -q 'executableURL?.resolvingSymlinksInPath' "$repo_dir/Sources/RoTypeApp/main.swift"
grep -q 'RoTypeProcessTrust.canTerminate' "$repo_dir/Squirrel/sources/Main.swift"
grep -q 'SecCodeCheckValidity' "$repo_dir/Squirrel/sources/RoTypeProcessTrust.swift"
if rg -n 'contentsOfDirectory|scheduledTimer\(withTimeInterval: 0\.05|dynamic-candidate-refresh' \
  "$repo_dir/Sources" "$repo_dir/Squirrel/sources" "$repo_dir/Rime/lua"; then
  echo "FAIL: polling or distributed dynamic-candidate refresh remains"
  exit 1
fi
if grep -Eq 'CGEvent\(|\.post\(tap:' "$translation_service" "$translation_client"; then
  echo "FAIL: dynamic candidate refresh must not post synthetic keyboard events"
  exit 1
fi

if rg -n 'WhisperKit|WhisperTranscriber|DoubaoSpeech|SpeechTranscrib|AudioRecorder|HotKeyMonitor|VoiceHotKey|TextInserter|StatusPanel' \
  "$repo_dir/Package.swift" "$repo_dir/Sources" "$repo_dir/Tests" "$repo_dir/Resources"; then
  echo "FAIL: removed Whisper voice implementation remains in the product"
  exit 1
fi
! grep -q 'com.apple.security.device.audio-input' "$repo_dir/Resources/RoTypeApp.entitlements"
! grep -q 'com.apple.security.network.client' "$repo_dir/Resources/RoTypeApp.entitlements"
! grep -q 'AudioRecorder\|HotKeyMonitor\|WhisperTranscriber' "$repo_dir/Squirrel/sources/SquirrelInputController.swift"
grep -q '洛克输入法设置.app' "$repo_dir/Squirrel/sources/SquirrelInputController.swift"
! grep -Eq '打开洛克语音输入|openQwenVoiceInput' "$repo_dir/Squirrel/sources/SquirrelInputController.swift"
grep -q 'NSWorkspace.shared.openApplication' "$repo_dir/Squirrel/sources/SquirrelInputController.swift"
grep -q 'im.roarkai.inputmethod.Luoke.show-settings' "$repo_dir/Squirrel/sources/SquirrelInputController.swift"
grep -q 'CommandLine.arguments.contains("--show-settings")' "$repo_dir/Sources/RoTypeApp/AppDelegate.swift"
! grep -q 'openSettingsIfNeeded' "$repo_dir/Sources/RoTypeApp/AppDelegate.swift"

grep -q 'LSMultipleInstancesProhibited' "$info_plist"
grep -q 'tsInputModePaletteIconFileKey' "$repo_dir/Squirrel/resources/Info.plist"
grep -A1 'tsInputModePaletteIconFileKey' "$repo_dir/Squirrel/resources/Info.plist" | grep -q 'rotypeMenu16Template.pdf'
grep -q 'id="luoke-r"' "$repo_dir/Squirrel/Rime.icon/Assets/logo.svg"
icon_fixture=$(mktemp -d)/rotypeTemplate.pdf
xcrun swift "$repo_dir/scripts/generate-menu-icon.swift" "$icon_fixture"
xcrun swift "$repo_dir/Tests/MenuIcon/test-menu-icon.swift" "$icon_fixture"
rm -R "${icon_fixture:h}"
grep -q 'if event.type == .keyDown' "$repo_dir/Squirrel/sources/SquirrelInputController.swift"

print "Keyboard, translation, icon, and voice removal checks passed."
