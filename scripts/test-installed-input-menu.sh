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
    repeat with itemRef in every menu item of menu 1 of inputItem
      try
        if enabled of itemRef then
          set markCharacter to value of attribute "AXMenuItemMarkChar" of itemRef
          if markCharacter is "✓" then set selectedName to name of itemRef
        end if
      end try
    end repeat
    key code 53
    return selectedName
  end tell
end tell
APPLESCRIPT
} 2>&1)"

if [[ "$tis_current_source" != "im.roarkai.inputmethod.Luoke.Hans" || "$menu_current_source" != "洛克输入法" ]]; then
  printf 'FAIL: 系统 API 与顶部输入法菜单没有共同确认“洛克输入法”\n'
  printf 'TIS 当前输入源: %s\n' "$tis_current_source"
  printf '菜单实际勾选: %s\n' "${menu_current_source:-<无>}"
  exit 1
fi

printf 'PASS: 系统 API 与顶部输入法菜单共同确认“洛克输入法”\n'
