#!/usr/bin/env bash
# Own the media volume as nobody:nogroup. The directory itself is mode 0755.
# Descendant directories get that owner too and lose other-write. Each
# directory opened loses its extended ACL, and the mode bits stay as the
# walk set them. A regular file loses its extended ACL and keeps its owner
# and mode. Symlinks are not opened. Sourced by deploy/deploy.sh
# and deploy/provision.sh.

ensure_media_ownership() {
  local media="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [ -z "${media}" ]; then
    echo "ensure_media_ownership: media directory required" >&2
    return 1
  fi

  # A symlink is not the volume. Leave it untouched and let the deploy
  # continue. chown and chmod on the path would follow the link.
  if [ -L "${media}" ]; then
    echo "ensure_media_ownership: ${media} is a symlink, leaving it untouched" >&2
    return 0
  fi

  if [ ! -e "${media}" ]; then
    sudo install -d -m 0755 "${media}"
  elif [ ! -d "${media}" ]; then
    echo "ensure_media_ownership: ${media} is not a real directory" >&2
    return 1
  fi

  sudo python3 "${script_dir}/media_ownership.py" "${media}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  if [ "$#" -ne 1 ]; then
    echo "usage: deploy/media-ownership.sh MEDIA_DIR" >&2
    exit 1
  fi
  ensure_media_ownership "$1"
fi
