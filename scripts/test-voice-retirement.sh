#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
temporary=$(mktemp -d)
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -KILL "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
  rm -R "$temporary"
}
trap cleanup EXIT
identity=${ROTYPE_CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Developer ID Application: XIAO BIN \(DF7J2VBQD8\)/ { print $2; exit }')}
[[ -n "$identity" ]] || { print -u2 'Developer ID identity required for voice retirement integration tests.'; exit 1; }
app="$temporary/Applications Fixture/洛克语音输入.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Python/bin" "$temporary/scripts"
cp "$repo_dir/Installer/scripts/preinstall" "$temporary/scripts/preinstall"
if [[ -f "$repo_dir/Installer/tools/RetireVoice.swift" ]]; then
  swiftc "$repo_dir/Installer/tools/RetireVoice.swift" -o "$temporary/scripts/retire-voice"
fi
swiftc "$repo_dir/Tests/VoiceRetirement/Fixture.swift" -o "$app/Contents/MacOS/RoTypeVoice"
cp "$app/Contents/MacOS/RoTypeVoice" "$app/Contents/Resources/Python/bin/python3"
cp "$app/Contents/MacOS/RoTypeVoice" "$temporary/unrelated"
printf 'fixture only\n' > "$app/Contents/Resources/server.py"
# The shipped launcher ignores arguments. Any invocation is an error here.
printf '#!/bin/bash\ntouch "%s/launcher-was-executed"\n' "$temporary" > "$app/Contents/Resources/launch-server.sh"
chmod +x "$app/Contents/Resources/launch-server.sh"
printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>im.roarkai.inputmethod.Luoke.voice</string><key>CFBundleExecutable</key><string>RoTypeVoice</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>' > "$app/Contents/Info.plist"
codesign --force --deep --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict -R '=anchor apple generic and identifier "im.roarkai.inputmethod.Luoke.voice" and certificate leaf[subject.OU] = "DF7J2VBQD8"' "$app"
"$app/Contents/MacOS/RoTypeVoice" &
pids+=($!)
"$app/Contents/Resources/Python/bin/python3" "$app/Contents/Resources/server.py" &
pids+=($!)
"$temporary/unrelated" "$app/Contents/Resources/server.py" &
pids+=($!)
sleep 0.2
run_preinstall() {
  ROTYPE_INPUT_METHODS_DIR="$temporary/Input Methods" \
  ROTYPE_APPLICATIONS_DIR="$temporary/Applications Fixture" \
  ROTYPE_BACKUP_ROOT="$temporary/Backups" \
  ROTYPE_ACTIVE_GUI_UIDS="$(id -u)" \
  ROTYPE_SKIP_SESSION_OPERATIONS=1 ROTYPE_DIRECT_USER_COMMANDS=1 \
    bash "$temporary/scripts/preinstall"
}
run_preinstall
[[ ! -e "$temporary/launcher-was-executed" ]] || { print -u2 'FAIL: retirement executed the legacy start-only launcher'; exit 1; }
[[ ! -d "$app" ]] || { print -u2 'FAIL: verified retired app was not removed'; exit 1; }
for pid in "${pids[@]:0:2}"; do
  if kill -0 "$pid" 2>/dev/null; then print -u2 'FAIL: owned legacy process survived retirement'; exit 1; fi
done
kill -0 "${pids[3]}"
print 'Voice retirement passed: owned processes exited, unrelated process preserved, launcher never executed.'

# A valid but uncooperative process must block removal, not be force-killed.
backup=$(< "$temporary/Backups/last-backup.txt")
ditto "$backup/洛克语音输入.app" "$app"
ROTYPE_FIXTURE_IGNORE_TERM=1 ROTYPE_FIXTURE_READY="$temporary/stubborn-ready" "$app/Contents/MacOS/RoTypeVoice" &
stubborn=$!
pids+=($stubborn)
for attempt in {1..100}; do [[ -f "$temporary/stubborn-ready" ]] && break; sleep 0.05; done
[[ -f "$temporary/stubborn-ready" ]]
kill -TERM "$stubborn"
sleep 0.1
kill -0 "$stubborn"
if run_preinstall; then print -u2 'FAIL: retirement reported success for an uncooperative process'; exit 1; fi
[[ -d "$app" ]]
kill -0 "$stubborn"
kill -KILL "$stubborn"
wait "$stubborn" 2>/dev/null || true
pids=(${pids:#$stubborn})

# A tampered resource must prevent both signalling and deleting the app.
"$app/Contents/MacOS/RoTypeVoice" &
untrusted=$!
pids+=($untrusted)
sleep 0.2
printf 'tampered\n' >> "$app/Contents/Resources/server.py"
run_preinstall
[[ -d "$app" ]]
kill -0 "$untrusted"
if "$temporary/scripts/retire-voice" --app "$app"; then print -u2 'FAIL: retirement tool accepted tampered app'; exit 1; fi
kill -0 "$untrusted"
[[ ! -e "$temporary/launcher-was-executed" ]]
print 'Voice retirement refusal passed: stalled processes and tampered apps are preserved.'
