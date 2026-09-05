#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
model_name="zh-hant-t-essay-bgw.gram"
model_commit="97bf55046aad163c3d1881abae5312040b1bbed9"
expected_sha256="0488ebd6688f900a39200f2b794f2f99bcbf1e8fc27280ae4a2324b08b1559c1"
destination=${ROTYPE_OCTAGRAM_MODEL_PATH:-"$repo_dir/Squirrel/data/plum/$model_name"}
url="https://raw.githubusercontent.com/lotem/rime-octagram-data/$model_commit/$model_name"

matches_checksum() {
  [[ -f "$1" ]] && [[ "$(/usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}')" == "$expected_sha256" ]]
}

if matches_checksum "$destination"; then
  /bin/chmod 0644 "$destination"
  print "$destination"
  exit 0
fi

/bin/mkdir -p "${destination:h}"
temporary=$(mktemp "${destination:h}/.${model_name}.XXXXXX")
trap '/bin/rm -f "$temporary"' EXIT
/usr/bin/curl --fail --location --retry 3 --output "$temporary" "$url"
if ! matches_checksum "$temporary"; then
  print -u2 "Downloaded octagram model failed SHA-256 verification."
  exit 1
fi
# mktemp uses 0600; the installed model is root-owned but read by every user.
/bin/chmod 0644 "$temporary"
/bin/mv "$temporary" "$destination"
trap - EXIT
print "$destination"
