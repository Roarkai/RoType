#!/bin/bash
# Independent static-site deployment. Credentials are supplied only by the operator.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEPLOY_HOST:?Set DEPLOY_HOST to the SSH destination}"
: "${DEPLOY_KEY:?Set DEPLOY_KEY to an existing local private key}"
[[ -f "$DEPLOY_KEY" ]]
reuse_downloads=${REUSE_DOWNLOADS:-0}
[[ "$reuse_downloads" == 0 || "$reuse_downloads" == 1 ]]
for file in index.html style.css assets/social-v2.png downloads/RoType-0.0.1-build48-arm64.pkg downloads/RoType-build48-source.tar.gz; do
  [[ -s "website/$file" ]] || { echo "Missing website/$file" >&2; exit 1; }
done
(cd website/downloads && shasum -a 256 -c RoType-0.0.1-build48-arm64.pkg.sha256)
if command -v spctl >/dev/null; then
  spctl --assess --type install website/downloads/RoType-0.0.1-build48-arm64.pkg
fi
release=$(date -u +%Y%m%d-%H%M%S)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
payload=(index.html style.css site.js 404.html robots.txt sitemap.xml assets privacy releases)
[[ "$reuse_downloads" == 1 ]] || payload+=(downloads)
pkg_hash=$(shasum -a 256 website/downloads/RoType-0.0.1-build48-arm64.pkg | cut -d ' ' -f1)
source_hash=$(shasum -a 256 website/downloads/RoType-build48-source.tar.gz | cut -d ' ' -f1)
COPYFILE_DISABLE=1 tar --no-xattrs -czf "$work/site.tgz" -C website "${payload[@]}"
ssh_args=(-i "$DEPLOY_KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=15)
scp "${ssh_args[@]}" "$work/site.tgz" "$DEPLOY_HOST:/tmp/rotype-site-$release.tgz"
scp "${ssh_args[@]}" website/deploy/nginx.conf "$DEPLOY_HOST:/tmp/rotype-nginx-$release.conf"
scp "${ssh_args[@]}" website/deploy/renew-nginx.sh "$DEPLOY_HOST:/tmp/rotype-renew-$release.sh"
ssh "${ssh_args[@]}" "$DEPLOY_HOST" "bash -s -- '$release' '$reuse_downloads' '$pkg_hash' '$source_hash'" <<'REMOTE'
set -euo pipefail
release="$1"
[[ "$release" =~ ^[0-9]{8}-[0-9]{6}$ ]]
root=/var/www/rotype
config=/etc/nginx/conf.d/type.roarkist.com.conf
[[ -s /etc/letsencrypt/live/type.roarkist.com/fullchain.pem ]]
[[ ! -e "$root/current" || -L "$root/current" ]]
[[ ! -e "$root/releases/$release" ]]
[[ "$2" == 0 || "$2" == 1 ]]
if [[ "$2" == 1 ]]; then
  [[ "$(sha256sum "$root/current/downloads/RoType-0.0.1-build48-arm64.pkg" | cut -d ' ' -f1)" == "$3" ]]
  [[ "$(sha256sum "$root/current/downloads/RoType-build48-source.tar.gz" | cut -d ' ' -f1)" == "$4" ]]
fi
mkdir -p "$root/releases/$release" "$root/rollback"
tar -xzf "/tmp/rotype-site-$release.tgz" -C "$root/releases/$release"
if [[ "$2" == 1 ]]; then
  cp -a "$root/current/downloads" "$root/releases/$release/downloads"
fi
find "$root/releases/$release" -type d -exec chmod 755 {} +
find "$root/releases/$release" -type f -exec chmod 644 {} +
if command -v restorecon >/dev/null; then restorecon -RF "$root/releases/$release"; fi
previous=$(readlink "$root/current" || true)
[[ ! -f "$config" ]] || cp -p "$config" "$root/rollback/nginx-$release.conf"
install -m 644 "/tmp/rotype-nginx-$release.conf" "$config"
rollback_config() {
  if [[ -f "$root/rollback/nginx-$release.conf" ]]; then
    cp -p "$root/rollback/nginx-$release.conf" "$config"
  else
    rm -f "$config"
  fi
}
if ! nginx -t; then rollback_config; exit 1; fi
ln -s "$root/releases/$release" "$root/.next-$release"
mv -Tf "$root/.next-$release" "$root/current"
if ! systemctl reload nginx; then
  rollback_config
  if [[ -n "$previous" ]]; then
    ln -s "$previous" "$root/.restore-$release"
    mv -Tf "$root/.restore-$release" "$root/current"
  else
    rm "$root/current"
  fi
  nginx -t && systemctl reload nginx
  exit 1
fi
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
install -m 755 "/tmp/rotype-renew-$release.sh" /etc/letsencrypt/renewal-hooks/deploy/rotype-nginx
printf '%s\n' "$previous" > "$root/rollback/previous-$release.txt"
# nginx -s reload returns before new workers necessarily accept connections.
healthy=false
for attempt in {1..10}; do
  if curl --fail --silent --show-error --max-time 10 --resolve type.roarkist.com:443:127.0.0.1 https://type.roarkist.com/ -o /dev/null; then
    healthy=true
    break
  fi
  sleep 1
done
if [[ "$healthy" != true ]]; then
  rollback_config
  if [[ -n "$previous" ]]; then
    ln -s "$previous" "$root/.restore-$release"
    mv -Tf "$root/.restore-$release" "$root/current"
  else
    rm "$root/current"
  fi
  nginx -t && systemctl reload nginx
  exit 1
fi
rm -f "/tmp/rotype-site-$release.tgz" "/tmp/rotype-nginx-$release.conf" "/tmp/rotype-renew-$release.sh"
printf 'Published %s; previous release: %s\n' "$release" "${previous:-none}"
REMOTE
printf 'Verify the public edge separately: https://type.roarkist.com/\n'
