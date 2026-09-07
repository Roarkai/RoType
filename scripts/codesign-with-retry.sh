# Sourced by packaging scripts. Retry Apple's timestamp transport only;
# never remove --timestamp, change identity, or ignore a signing failure.
codesign() {
  local attempt log result retry
  for attempt in 1 2 3 4; do
    log=$(mktemp)
    result=0
    /usr/bin/codesign "$@" 2>"$log" || result=$?
    /bin/cat "$log" >&2
    retry=0
    /usr/bin/grep -q 'The timestamp service is not available' "$log" && retry=1
    /bin/rm -f "$log"
    [[ "$result" -eq 0 ]] && return 0
    [[ "$retry" -eq 1 && "$attempt" -lt 4 ]] || return "$result"
    /bin/sleep "$((attempt * 3))"
  done
}
