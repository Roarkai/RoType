#!/bin/zsh
set -euo pipefail

[[ $# -eq 0 || ( $# -eq 1 && "$1" == "--fail-after-handshake" ) ]] || { print -u2 'Unknown test option'; exit 2; }
[[ -z "${ROTYPE_TRANSLATION_SERVICE:-}" ]] || { print -u2 'ROTYPE_TRANSLATION_SERVICE is no longer supported: this test builds an isolated fixture.'; exit 2; }
repo_dir=${0:A:h:h}
protocol_header="$repo_dir/Shared/RoTypeXPCProtocol/include/RoTypeTranslationXPCProtocol.h"
service_name="im.roarkai.inputmethod.Luoke.translation.test.$(/usr/bin/uuidgen)"
uid=$(id -u)
temporary=$(mktemp -d)
probe="$temporary/RoTypeXPCProbe"
agent="$temporary/agent.plist"
bootstrap_attempted=false
publisher_pid=""

wait_for_removal() {
  local attempt
  for attempt in {1..50}; do
    if ! /bin/launchctl print "gui/$uid/$service_name" >/dev/null 2>&1; then return 0; fi
    /bin/sleep 0.1
  done
  print -u2 "Timed out removing test fixture: $service_name"
  return 1
}

cleanup() {
  local result=$?
  trap - EXIT
  if [[ -n "$publisher_pid" ]]; then
    kill "$publisher_pid" 2>/dev/null || true
    wait "$publisher_pid" 2>/dev/null || true
  fi
  if $bootstrap_attempted; then
    /bin/launchctl bootout "gui/$uid/$service_name" >/dev/null 2>&1 || true
    if ! wait_for_removal; then
      print -u2 "Preserving fixture files for diagnosis: $temporary"
      exit 1
    fi
  fi
  /bin/rm -R "$temporary"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

signing_identity=${ROTYPE_CODESIGN_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
  signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application: XIAO BIN \(DF7J2VBQD8\)/ { print $2; exit }')
fi
[[ -n "$signing_identity" ]] || { print -u2 'Missing Developer ID Application identity.'; exit 1; }

# Compile exactly the same service implementation in a private scratch tree.
# Only this fixture entry point accepts a test endpoint. Production builds have
# no endpoint override; neither the installed worker nor its job is replaced.
swift build --package-path "$repo_dir" --scratch-path "$temporary/build" \
  --configuration release --product RoTypeTranslationService -Xswiftc -DROTYPE_XPC_TEST > "$temporary/build.log" 2>&1 || {
    /usr/bin/tail -60 "$temporary/build.log" >&2; exit 1
  }
bin_dir=$(swift build --package-path "$repo_dir" --scratch-path "$temporary/build" --configuration release --show-bin-path)
worker="$bin_dir/RoTypeTranslationService"
codesign --force --options runtime --timestamp --identifier im.roarkai.inputmethod.Luoke.translation \
  --sign "$signing_identity" "$worker"

# plutil handles XML escaping (including spaces, ampersands and angle brackets).
plutil -create xml1 "$agent"
plutil -insert Label -string "$service_name" "$agent"
plutil -insert ProgramArguments -json '[]' "$agent"
plutil -insert ProgramArguments.0 -string "$worker" "$agent"
plutil -insert ProgramArguments.1 -string "$service_name" "$agent"
plutil -insert MachServices -json "{\"$service_name\":true}" "$agent"
plutil -insert EnvironmentVariables -json '{"ROTYPE_TRANSLATION_IDLE_TIMEOUT":"0.2","ROTYPE_ALLOW_UNSIGNED_XPC":"1"}' "$agent"
plutil -insert ThrottleInterval -integer 1 "$agent"
plutil -insert ProcessType -string Background "$agent"
xcrun swiftc -import-objc-header "$protocol_header" \
  "$repo_dir/Tests/XPCIntegration/XPCProbe.swift" -o "$probe"

print "XPC fixture: $service_name"
bootstrap_attempted=true
/bin/launchctl bootstrap "gui/$uid" "$agent"
# Verify a positive handshake first: an unavailable/crashed worker must never
# count as evidence that the unsigned-client rejection policy is correct.
codesign --force --identifier im.roarkai.inputmethod.Luoke --options runtime \
  --timestamp --sign "$signing_identity" "$probe"
"$probe" translation accepted "$service_name"
"$probe" candidate accepted "$service_name"
"$probe" candidate-version version-rejected "$service_name"
if [[ "${1:-}" == "--fail-after-handshake" ]]; then
  print -u2 'Deliberate failure to verify cleanup after starting the worker.'
  exit 42
fi
# Keep executable vnodes separate; repeatedly re-signing one path can leave
# the previous process's cached code identity visible during the next launch.
unsigned_probe="$temporary/UnsignedProbe"
helper_probe="$temporary/SettingsProbe"
cp "$probe" "$unsigned_probe"
cp "$probe" "$helper_probe"
codesign --force --sign - --identifier im.roarkai.inputmethod.Luoke "$unsigned_probe"
"$unsigned_probe" translation connection-rejected "$service_name"
"$unsigned_probe" candidate connection-rejected "$service_name"
codesign --force --identifier im.roarkai.inputmethod.Luoke.helper --options runtime \
  --timestamp --sign "$signing_identity" "$helper_probe"
"$helper_probe" verification accepted "$service_name"
"$helper_probe" translation operation-rejected "$service_name"
"$helper_probe" candidate operation-rejected "$service_name"

# Exercise endpoint serialization, both peer identities, helper publication denial,
# and input-method discovery denial without inserting into any desktop application.
xcrun swiftc -import-objc-header "$protocol_header" \
  "$repo_dir/Tests/XPCIntegration/DictationProbe.swift" -o "$temporary/VoicePublisher"
cp "$temporary/VoicePublisher" "$temporary/VoiceHelper"
codesign --force --options runtime --timestamp --identifier im.roarkai.inputmethod.Luoke \
  --sign "$signing_identity" "$temporary/VoicePublisher"
codesign --force --options runtime --timestamp --identifier im.roarkai.inputmethod.Luoke.helper \
  --sign "$signing_identity" "$temporary/VoiceHelper"
"$temporary/VoicePublisher" publish "$service_name" "$temporary/voice-ready" &
publisher_pid=$!
for attempt in {1..100}; do
  [[ -f "$temporary/voice-ready" ]] && break
  kill -0 "$publisher_pid"
  sleep 0.05
done
[[ -f "$temporary/voice-ready" ]]
sleep 0.2
"$temporary/VoicePublisher" denied "$service_name"
"$temporary/VoiceHelper" helper "$service_name"
kill "$publisher_pid"
wait "$publisher_pid" 2>/dev/null || true
publisher_pid=""
/bin/sleep 2
if /bin/launchctl print "gui/$uid/$service_name" | /usr/bin/grep -q 'pid = '; then
  print -u2 'Translation fixture did not exit after becoming idle.'
  exit 1
fi
"$helper_probe" verification accepted "$service_name"
print 'Isolated translation XPC caller-role, idle-exit, and relaunch checks passed.'
