#!/bin/sh
# Only act on this site's successful certificate renewal.
case " ${RENEWED_DOMAINS:-} " in
  *" type.roarkist.com "*) /usr/sbin/nginx -t && /usr/bin/systemctl reload nginx ;;
esac
