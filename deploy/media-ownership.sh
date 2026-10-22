#!/usr/bin/env bash
# Descendant directories of the media volume. Own each one as nobody:nogroup
# and clear other-write. The walk does not follow symlinks, so a link planted
# in the volume cannot retarget chown or chmod onto a path outside it.
# Sourced by deploy/deploy.sh and deploy/provision.sh.

ensure_media_descendant_ownership() {
  local media="$1"

  if [ -z "${media}" ] || [ -L "${media}" ] || [ ! -d "${media}" ]; then
    echo "ensure_media_descendant_ownership: ${media:-media directory} is not a real directory" >&2
    return 1
  fi

  # -P is find's default: do not follow symlinks. -type d skips links.
  # chown --no-dereference will not change the target if a path is a link.
  # chmod would follow a link named on its command line, so it only sees
  # the directories find classified as real directories.
  sudo find -P "${media}" -mindepth 1 -type d \
    -exec chown --no-dereference nobody:nogroup -- {} + \
    -exec chmod o-w -- {} +
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  if [ "$#" -ne 1 ]; then
    echo "usage: deploy/media-ownership.sh MEDIA_DIR" >&2
    exit 1
  fi
  ensure_media_descendant_ownership "$1"
fi
