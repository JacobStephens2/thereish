#!/usr/bin/env python3
"""Own a media directory without following symlinks.

The directory itself becomes nobody:nogroup and mode 0755. Each real
descendant directory becomes nobody:nogroup and loses other-write. The
extended ACL is removed from each directory opened, and the mode bits
stay as this walk set them. A symlink is not a directory: opening with
O_NOFOLLOW | O_DIRECTORY fails, and fchown, fchmod, and the ACL removal
apply to the directory that was opened, so replacing that path with a
link cannot retarget the change.
"""

import ctypes
import ctypes.util
import errno
import grp
import os
import pwd
import resource
import stat
import sys

_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
# Access ACL (named users and groups) and the default ACL directories
# hand to children. setfacl -b removes both, then rebuilds the mode.
_ACL_XATTRS = (b"system.posix_acl_access", b"system.posix_acl_default")

# fremovexattr on the open descriptor. os.removexattr takes a path and
# would re-resolve the name, which is the swap these descriptors exist
# to avoid. Not every interpreter exposes os.fremovexattr.
_libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
_libc.fremovexattr.argtypes = (ctypes.c_int, ctypes.c_char_p)
_libc.fremovexattr.restype = ctypes.c_int


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
        _own_opened_dir(root, uid, gid, 0o755)
        own_descendants(root, uid, gid)
    finally:
        os.close(root)
    return 0


def _own_opened_dir(fd, uid, gid, mode):
    os.fchown(fd, uid, gid)
    os.fchmod(fd, mode)
    # fchmod rewrites the mask and leaves named entries. Dropping these
    # xattrs removes the extended ACL and, on Linux, leaves the mode bits
    # just written. setfacl -b would rebuild the mode from the base group
    # entry instead.
    for name in _ACL_XATTRS:
        if _libc.fremovexattr(fd, name) == 0:
            continue
        err = ctypes.get_errno()
        if err in (errno.ENODATA, errno.ENOTSUP, errno.EOPNOTSUPP):
            continue
        raise OSError(err, os.strerror(err), name.decode())


def _ensure_nofile(needed):
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    if soft >= needed:
        return
    resource.setrlimit(resource.RLIMIT_NOFILE, (needed, max(hard, needed)))


def _open_child(name, parent, depth):
    try:
        return os.open(name, _FLAGS, dir_fd=parent)
    except OSError as exc:
        if exc.errno not in (errno.EMFILE, errno.ENFILE):
            return None
        # A deep chain holds one descriptor per level. Raising the limit
        # lets the privileged walk finish instead of stopping early.
        _ensure_nofile(depth + 128)
        try:
            return os.open(name, _FLAGS, dir_fd=parent)
        except OSError as retry:
            if retry.errno in (errno.EMFILE, errno.ENFILE):
                raise
            return None


def _listdir(fd, depth):
    try:
        return os.listdir(fd)
    except OSError as exc:
        if exc.errno not in (errno.EMFILE, errno.ENFILE):
            raise
        _ensure_nofile(depth + 128)
        return os.listdir(fd)


def own_descendants(root, uid, gid):
    # Explicit stack: one Python frame per directory aborts at the
    # interpreter recursion limit and leaves the rest of the tree unowned.
    # sudo's default soft limit is 1024, below a chain an attacker can mkdir.
    _soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    _ensure_nofile(hard)
    frames = [[root, None, 0, False]]
    try:
        while frames:
            fd, names, index, close = frames[-1]
            if names is None:
                frames[-1][1] = _listdir(fd, len(frames))
                continue
            if index >= len(names):
                frames.pop()
                if close:
                    os.close(fd)
                continue
            frames[-1][2] = index + 1
            child = _open_child(names[index], fd, len(frames))
            if child is None:
                continue
            try:
                info = os.fstat(child)
                _own_opened_dir(
                    child, uid, gid, stat.S_IMODE(info.st_mode) & ~0o002
                )
            except Exception:
                os.close(child)
                raise
            frames.append([child, None, 0, True])
    finally:
        while frames:
            fd, _names, _index, close = frames.pop()
            if close:
                os.close(fd)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
