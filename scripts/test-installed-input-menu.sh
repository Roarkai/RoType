#!/bin/bash
set -euo pipefail

tis_current_source="$(swift -e '
import Carbon
let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
let identifier = unsafeBitCast(value, to: CFString?.self) as String?
print(identifier ?? "")
')"

menu_current_source="$({
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "TextInputMenuAgent"
    set inputItem to menu bar item 1 of menu bar 2
    click inputItem
    delay 0.2
    set selectedName to ""
    set luokeCount to 0
    set checkedCount to 0
    repeat with itemRef in every menu item of menu 1 of inputItem
      try
        if enabled of itemRef then
          if name of itemRef is "洛克输入法" then set luokeCount to luokeCount + 1
          set markCharacter to value of attribute "AXMenuItemMarkChar" of itemRef
          if markCharacter is "✓" then
            set selectedName to name of itemRef
            set checkedCount to checkedCount + 1
          end if
        end if
      end try
    end repeat
    perform action "AXCancel" of menu 1 of inputItem
    return selectedName & "|" & (luokeCount as text) & "|" & (checkedCount as text)
  end tell
end tell
APPLESCRIPT
} 2>&1)"

if [[ "$tis_current_source" != "im.roarkai.inputmethod.Luoke.Hans" || "$menu_current_source" != "洛克输入法|1|1" ]]; then
  printf 'FAIL: 菜单必须只有一个可选洛克、一个勾选项，且与系统 API 一致\n'
  printf 'TIS 当前输入源: %s\n' "$tis_current_source"
  printf '菜单勾选名称|洛克条目数|勾选数: %s\n' "${menu_current_source:-<无>}"
  exit 1
fi

printf 'PASS: 只有一个可选洛克、一个勾选项，且与系统 API 一致\n'
