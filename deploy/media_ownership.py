#!/usr/bin/env python3
"""Own a media directory without following symlinks.

The directory itself becomes nobody:nogroup and mode 0755. Each real
descendant directory becomes nobody:nogroup and loses other-write. A
symlink is not a directory: opening with O_NOFOLLOW | O_DIRECTORY fails,
and fchown/fchmod apply to the directory that was opened, so replacing
that path with a link cannot retarget the change.
"""

import errno
import grp
import os
import pwd
import stat
import sys

_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC


def main(argv):
    if len(argv) != 2:
        sys.exit("usage: media_ownership.py MEDIA_DIR")

    media = argv[1]
    try:
        info = os.lstat(media)
    except OSError as exc:
        sys.exit(f"media ownership: {media}: {exc}")

    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        print(
            f"media ownership: {media} is not a real directory, leaving it untouched",
            file=sys.stderr,
        )
        return 0

    uid = pwd.getpwnam("nobody").pw_uid
    gid = grp.getgrnam("nogroup").gr_gid

    try:
        root = os.open(media, _FLAGS)
    except OSError as exc:
        # A symlink that replaced the directory after lstat must not be followed.
        if exc.errno in (errno.ELOOP, errno.ENOTDIR):
            print(
                f"media ownership: {media} is not a real directory, leaving it untouched",
                file=sys.stderr,
            )
            return 0
        sys.exit(f"media ownership: {media}: {exc}")

    try:
        os.fchown(root, uid, gid)
        os.fchmod(root, 0o755)
        own_descendants(root, uid, gid)
    finally:
        os.close(root)
    return 0


def own_descendants(parent, uid, gid):
    for name in os.listdir(parent):
        try:
            child = os.open(name, _FLAGS, dir_fd=parent)
        except OSError:
            continue
        try:
            info = os.fstat(child)
            os.fchown(child, uid, gid)
            os.fchmod(child, stat.S_IMODE(info.st_mode) & ~0o002)
            own_descendants(child, uid, gid)
        finally:
            os.close(child)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
