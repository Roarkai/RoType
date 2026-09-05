#!/bin/bash
set -euo pipefail

input_methods_dir="${ROTYPE_INPUT_METHODS_DIR:-/Library/Input Methods}"
expected_bundle_id="im.roarkai.inputmethod.Luoke"
standard_app="$input_methods_dir/洛克输入法.app"

bundle_id_for() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

standard_bundle_id=""
if [[ -d "$standard_app" ]]; then
  standard_bundle_id=$(bundle_id_for "$standard_app")
fi

if [[ "$standard_bundle_id" != "$expected_bundle_id" ]]; then
  relocated_app=""
  relocated_root=""

  for candidate_root in "$input_methods_dir"/洛克输入法*.localized; do
    [[ -d "$candidate_root" ]] || continue
    candidate_app="$candidate_root/洛克输入法.app"
    [[ -d "$candidate_app" ]] || continue
    if [[ "$(bundle_id_for "$candidate_app")" == "$expected_bundle_id" ]]; then
      relocated_root="$candidate_root"
      relocated_app="$candidate_app"
      break
    fi
  done

  if [[ -z "$relocated_app" ]]; then
    echo "RoType: installed input method payload was not found." >&2
    exit 1
  fi

  if [[ -e "$standard_app" ]]; then
    if [[ "$standard_bundle_id" == "com.roarkai.rotype.inputmethod" || "$standard_bundle_id" == "$expected_bundle_id" ]]; then
      /bin/rm -R "$standard_app"
    else
      echo "RoType: refusing to replace an unknown bundle at $standard_app" >&2
      exit 1
    fi
  fi

  /bin/mv "$relocated_app" "$standard_app"
  /bin/rmdir "$relocated_root" >/dev/null 2>&1 || true
  echo "RoType: normalized relocated input method to $standard_app"
fi

if [[ "$(bundle_id_for "$standard_app")" != "$expected_bundle_id" || ! -f "$standard_app/Contents/MacOS/Squirrel" ]]; then
  echo "RoType: input method normalization failed." >&2
  exit 1
fi
