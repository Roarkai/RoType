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
codesign --force --sign - --identifier im.roarkai.inputmethod.Luoke "$probe"
"$probe" translation connection-rejected "$service_name"
"$probe" candidate connection-rejected "$service_name"
codesign --force --identifier im.roarkai.inputmethod.Luoke.helper --options runtime \
  --timestamp --sign "$signing_identity" "$probe"
"$probe" verification accepted "$service_name"
"$probe" translation operation-rejected "$service_name"
"$probe" candidate operation-rejected "$service_name"
/bin/sleep 2
if /bin/launchctl print "gui/$uid/$service_name" | /usr/bin/grep -q 'pid = '; then
  print -u2 'Translation fixture did not exit after becoming idle.'
  exit 1
fi
"$probe" verification accepted "$service_name"
print 'Isolated translation XPC caller-role, idle-exit, and relaunch checks passed.'
