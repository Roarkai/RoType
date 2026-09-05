#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
temporary=$(mktemp -d)
witness_pid=""
cleanup() {
  if [[ -n "$witness_pid" ]]; then
    kill "$witness_pid" 2>/dev/null || true
    wait "$witness_pid" 2>/dev/null || true
  fi
  rm -R "$temporary"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
uid=$(id -u)
production="gui/$uid/im.roarkai.inputmethod.Luoke.translation"
production_pid=""
if /bin/launchctl print "$production" >/dev/null 2>&1; then
  identity=${ROTYPE_CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Developer ID Application: XIAO BIN \(DF7J2VBQD8\)/ { print $2; exit }')}
  [[ -n "$identity" ]]
  swiftc -import-objc-header "$repo_dir/Shared/RoTypeXPCProtocol/include/RoTypeTranslationXPCProtocol.h" \
    "$repo_dir/Tests/XPCIntegration/IsolationWitness.swift" -o "$temporary/witness"
  codesign --force --options runtime --timestamp --identifier im.roarkai.inputmethod.Luoke.helper \
    --sign "$identity" "$temporary/witness"
  "$temporary/witness" "$temporary/ready" &
  witness_pid=$!
  for attempt in {1..200}; do
    [[ -f "$temporary/ready" ]] && break
    kill -0 "$witness_pid"
    sleep 0.05
  done
  [[ -f "$temporary/ready" ]]
  production_pid=$(/bin/launchctl print "$production" | awk '/^[[:space:]]*pid = / { print $3; exit }')
  [[ -n "$production_pid" ]]
else
  print 'No installed service: production-connection witness skipped; fixture cleanup is still verified.'
fi

check_cleanup() {
  local log="$1"
  local label=$(awk '/^XPC fixture: / { print $3 }' "$log")
  [[ "$label" == im.roarkai.inputmethod.Luoke.translation.test.* ]]
  if /bin/launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
    print -u2 "FAIL: fixture job survived cleanup: $label"; return 1
  fi
  if [[ -n "$witness_pid" ]]; then
    kill -0 "$witness_pid" || { print -u2 'FAIL: production XPC connection was interrupted'; return 1; }
    local current=$(/bin/launchctl print "$production" | awk '/^[[:space:]]*pid = / { print $3; exit }')
    [[ "$current" == "$production_pid" ]] || { print -u2 'FAIL: production worker was replaced'; return 1; }
  elif /bin/launchctl print "$production" >/dev/null 2>&1; then
    print -u2 'FAIL: test unexpectedly registered a production job'; return 1
  fi
}

zsh "$repo_dir/scripts/test-translation-xpc.sh" > "$temporary/normal.log" 2>&1 || {
  /usr/bin/tail -60 "$temporary/normal.log" >&2; exit 1
}
check_cleanup "$temporary/normal.log"
/usr/bin/tail -1 "$temporary/normal.log"

result=0
zsh "$repo_dir/scripts/test-translation-xpc.sh" --fail-after-handshake > "$temporary/failure.log" 2>&1 || result=$?
[[ "$result" == 42 ]] || { /usr/bin/tail -60 "$temporary/failure.log" >&2; exit 1; }
check_cleanup "$temporary/failure.log"
print 'XPC isolation passed: normal and failed runs removed their fixtures.'
if [[ -n "$witness_pid" ]]; then
  print "Installed production connection remained open; worker pid $production_pid unchanged."
fi
