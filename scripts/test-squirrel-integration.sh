#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
squirrel_dir="$repo_dir/Squirrel"

test -f "$squirrel_dir/LICENSE.txt"
grep -q 'GNU GENERAL PUBLIC LICENSE' "$squirrel_dir/LICENSE.txt"
grep -q 'NSWorkspace.shared.openApplication' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q '洛克输入法设置.app' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'im.roarkai.inputmethod.Luoke.show-settings' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'static let appDir = Bundle.main.bundleURL' "$squirrel_dir/sources/Main.swift"
grep -q 'let error = TISRegisterInputSource(SquirrelApp.appDir as CFURL)' "$squirrel_dir/sources/InputSource.swift"
grep -q 'waitForSource(mode: .primary)' "$squirrel_dir/sources/InputSource.swift"
grep -q 'Foundation.exit(EXIT_FAILURE)' "$squirrel_dir/sources/Main.swift"
if grep -q 'User already registered Squirrel method' "$squirrel_dir/sources/InputSource.swift"; then
  print -u2 "Input-source registration must refresh metadata after every upgrade."
  exit 1
fi
if grep -q 'User already enabled Squirrel method' "$squirrel_dir/sources/InputSource.swift"; then
  print -u2 "Input-source installation must not trust the synthetic IsEnabled flag."
  exit 1
fi
grep -q 'let error = TISEnableInputSource(inputSource)' "$squirrel_dir/sources/InputSource.swift"
if grep -q '/Library/Input Library' "$squirrel_dir/sources/Main.swift"; then
  print -u2 "Squirrel must register its real bundle path."
  exit 1
fi
grep -q '洛克输入法项目主页' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'inputControllerDidActivate(self)' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'inputControllerDidHandleKeyDown(self)' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'im.roarkai.inputmethod.Luoke.verification-request' "$squirrel_dir/sources/SquirrelApplicationDelegate.swift"
grep -q 'translationClient.recordControllerInput()' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'IsSecureEventInputEnabled()' "$squirrel_dir/sources/SquirrelInputController.swift"
if grep -q 'handledInputKey' "$squirrel_dir/sources/SquirrelApplicationDelegate.swift"; then
  print -u2 "Distributed notifications must not carry authoritative input evidence."
  exit 1
fi
grep -q '"value" : "洛克输入法"' "$squirrel_dir/resources/InfoPlist.xcstrings"
grep -q '<string>Squirrel</string>' "$squirrel_dir/resources/Info.plist"
grep -q '<string>im.roarkai.inputmethod.Luoke</string>' "$squirrel_dir/resources/Info.plist"
grep -A1 'CFBundleShortVersionString' "$squirrel_dir/resources/Info.plist" | grep -q '$(MARKETING_VERSION)'
grep -q 'MARKETING_VERSION = 0.0.1;' "$squirrel_dir/Squirrel.xcodeproj/project.pbxproj"
grep -q '<string>im.roarkai.inputmethod.Luoke.Hans</string>' "$squirrel_dir/resources/Info.plist"
grep -A1 'tsInputModeScriptKey' "$squirrel_dir/resources/Info.plist" | grep -q 'smUnicodeScript'
grep -A1 'tsInputModeDefaultStateKey' "$squirrel_dir/resources/Info.plist" | grep -q '<true/>'
if grep -Eq 'SUFeedURL|SUEnableAutomaticChecks|SUPublicEDKey' "$squirrel_dir/resources/Info.plist"; then
  print -u2 "RoType must not consume the upstream Squirrel update feed."
  exit 1
fi
if rg -n 'Sparkle|SPUStandardUpdater' "$squirrel_dir/sources" "$squirrel_dir/Squirrel.xcodeproj/project.pbxproj"; then
  print -u2 "Sparkle must not be linked into the RoType input method."
  exit 1
fi
if grep -q 'tsInputMethodCharacterRepertoireKey' "$squirrel_dir/resources/Info.plist"; then
  echo "FAIL: top-level tsInputMethodCharacterRepertoireKey prevents registration on current macOS"
  exit 1
fi
if grep -q 'im.rime.inputmethod.Squirrel' "$squirrel_dir/resources/Info.plist"; then
  print -u2 "洛克输入法不能复用上游 Squirrel 的输入源标识。"
  exit 1
fi
test -f "$squirrel_dir/Assets.xcassets/Rime.appiconset/icon_512x512@2x.png"
grep -q 'im.roarkai.inputmethod.Luoke.translation' "$repo_dir/Shared/RoTypeXPCProtocol/include/RoTypeTranslationXPCProtocol.h"
if grep -q '@objc private protocol RoTypeTranslationXPCProtocol' "$squirrel_dir/sources/RoTypeTranslationClient.swift"; then
  print -u2 "Squirrel must compile the shared XPC protocol instead of a duplicate declaration."
  exit 1
fi
grep -q 'translationSessionID = UUID().uuidString' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'rotype_panel_raw' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'rotype_panel_source' "$squirrel_dir/sources/SquirrelInputController.swift"
if grep -q 'dynamic-candidate-refresh' "$squirrel_dir/sources/SquirrelInputController.swift"; then
  print -u2 "Dynamic candidate refresh must stay inside the owning controller session."
  exit 1
fi
grep -q 'processKey(UInt32(XK_F19), modifiers: 0)' "$squirrel_dir/sources/SquirrelInputController.swift"
if grep -q 'processKey(UInt32(XK_F18)' "$squirrel_dir/sources/SquirrelInputController.swift"; then
  print -u2 'Translation presentation must not recompose the candidate list.'
  exit 1
fi
grep -q 'commitRoTypeWholeCompositionCandidate(at: candidateIndex)' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'commitRoTypeWholeCompositionCandidate(at: index)' "$squirrel_dir/sources/SquirrelInputController.swift"
grep -q 'visibleComments\[index\] == "〔中→英〕"' "$squirrel_dir/sources/SquirrelInputController.swift"
if grep -q 'im.rime.inputmethod.Squirrel.Hant' "$squirrel_dir/resources/Info.plist"; then
  print -u2 "Traditional Chinese input source must not be bundled."
  exit 1
fi
grep -q 'im.roarkai.inputmethod.Luoke.Hans' "$squirrel_dir/resources/Info.plist"
grep -q 'RoTypeFactoryDataMigration.run' "$squirrel_dir/sources/Main.swift"
grep -q 'factory-data-migration-' "$squirrel_dir/sources/Main.swift"
xcrun swiftc -parse "$squirrel_dir/sources/SquirrelInputController.swift"

print "Squirrel menu integration checks passed."
