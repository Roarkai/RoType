#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
source "$repo_dir/Installer/scripts/configure-user.sh"
temporary=$(mktemp -d)
trap 'rm -R "$temporary"' EXIT
log="$temporary/commands"
run_as_user() {
  shift
  printf '%s\n' "$*" >> "$log"
  case "$1" in
    helper/Contents/MacOS/LuokeInput) [[ "$fixture_progress" != unknown ]] || return 2; echo "$fixture_progress" ;;
    input-method) [[ "${fail_register:-false}" != true || "$2" != --register-input-source ]] ;;
    /usr/bin/open) return 0 ;;
    /bin/mkdir|/bin/rm|/usr/bin/touch) "$@" ;;
    *) return 99 ;;
  esac
}
for fixture_progress in new resume complete deferred unknown; do
  for agent_ready in true false; do
    for fail_register in true false; do
      : > "$log"
      finish_rotype_user_setup 501 "$temporary/home" input-method helper "$agent_ready" >/dev/null
      grep -q -- '--register-input-source' "$log"
      if [[ "$fixture_progress" == new && "$fail_register" == false ]]; then
        grep -q -- '--enable-input-source' "$log"
        grep -q -- '--select-input-source' "$log"
      else
        ! grep -qE -- '--enable-input-source|--select-input-source' "$log"
      fi
      marker="$temporary/home/Library/Application Support/RoType/input-source-setup-required"
      if [[ ( "$fixture_progress" == complete || "$fixture_progress" == deferred ) && "$agent_ready" == true && "$fail_register" == false ]]; then
        ! grep -q /usr/bin/open "$log"
        if [[ "$fixture_progress" == complete ]]; then [[ ! -e "$marker" ]]; fi
      else
        grep -q /usr/bin/open "$log"
        [[ -f "$marker" ]]
      fi
    done
  done
done
print_result='Install setup passed: fresh/resume/update/unknown, registration and service failures.'
echo "$print_result"
