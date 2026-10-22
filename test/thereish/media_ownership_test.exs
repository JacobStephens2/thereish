defmodule Thereish.MediaOwnershipTest do
  use ExUnit.Case, async: true

  @script Path.expand("../../deploy/media-ownership.sh", __DIR__)

  setup do
    parent =
      Path.join(
        System.tmp_dir!(),
        "thereish-media-own-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(parent)

    on_exit(fn ->
      System.cmd("sudo", ["rm", "-rf", "--", parent])
    end)

    media = Path.join(parent, "media")
    tracks = Path.join(media, "tracks")
    nested = Path.join(tracks, "nested dir")
    masks = Path.join(media, "masks")
    awkward = Path.join(media, "weird\nname")
    song = Path.join(tracks, "song.mp3")

    File.mkdir_p!(nested)
    File.mkdir_p!(masks)
    File.mkdir_p!(awkward)
    File.write!(song, "audio")
    File.chmod!(tracks, 0o777)
    File.chmod!(nested, 0o777)
    File.chmod!(masks, 0o755)
    File.chmod!(awkward, 0o707)
    File.chmod!(song, 0o666)
    File.chmod!(media, 0o777)

    %{
      media: media,
      tracks: tracks,
      nested: nested,
      masks: masks,
      awkward: awkward,
      song: song,
      nobody: nobody_ids()
    }
  end

  test "owns each descendant directory as nobody and clears other-write", %{
    media: media,
    tracks: tracks,
    nested: nested,
    masks: masks,
    awkward: awkward,
    song: song,
    nobody: {uid, gid}
  } do
    {output, status} = System.cmd("bash", [@script, media], stderr_to_stdout: true)
    assert status == 0, output

    assert {uid, gid} == owner(tracks)
    assert {uid, gid} == owner(nested)
    assert {uid, gid} == owner(masks)
    assert {uid, gid} == owner(awkward)

    assert perm(tracks) == 0o775
    assert perm(nested) == 0o775
    assert perm(masks) == 0o755
    assert perm(awkward) == 0o705

    assert owner(song) != {uid, gid}
    assert perm(song) == 0o666
    assert owner(media) == {uid, gid}
    assert perm(media) == 0o755
  end

  test "removes the extended ACL from each directory it opens and from a regular file, and leaves the mode bits",
       %{media: media, tracks: tracks, song: song, nobody: {uid, gid}} do
    user = current_user()
    assert user not in ["root", "nobody"]

    # group:: is r-x while the mode's group class stays rwx, so rebuilding
    # the mode from the base ACL entries would not leave 0775. On the file,
    # group:: is r-- and the mode stays 0666; rebuilding would leave 0646.
    {output, status} =
      System.cmd("setfacl", ["-m", "u:#{user}:rwx,g::r-x", "--", tracks], stderr_to_stdout: true)

    assert status == 0, output
    File.chmod!(tracks, 0o777)
    grant_default_user(tracks, user, "rwx")
    grant_named_user(media, user, "rwx")
    File.chmod!(media, 0o777)
    grant_default_user(media, user, "rwx")

    {output, status} =
      System.cmd("setfacl", ["-m", "u:#{user}:rw,g::r--", "--", song], stderr_to_stdout: true)

    assert status == 0, output
    File.chmod!(song, 0o666)

    assert perm(tracks) == 0o777
    assert perm(media) == 0o777
    assert extended_acl?(tracks)
    assert extended_acl?(media)
    assert extended_acl?(song)
    song_owner = owner(song)
    assert song_owner != {uid, gid}

    {output, status} = System.cmd("bash", [@script, media], stderr_to_stdout: true)
    assert status == 0, output

    assert {uid, gid} == owner(tracks)
    assert {uid, gid} == owner(media)
    assert perm(tracks) == 0o775
    assert perm(media) == 0o755
    refute extended_acl?(tracks)
    refute extended_acl?(media)

    assert {:error, :eacces} = File.write(Path.join(tracks, "planted.txt"), "x")
    assert {:error, :eacces} = File.write(Path.join(media, "planted.txt"), "x")

    later = Path.join(tracks, "later")
    {output, status} = System.cmd("sudo", ["mkdir", "--", later], stderr_to_stdout: true)
    assert status == 0, output
    refute extended_acl?(later)

    refute extended_acl?(song)
    assert perm(song) == 0o666
    assert owner(song) == song_owner
  end

  test "does not follow a symlink out of the media volume", %{media: media} do
    parent = Path.dirname(media)
    outside = Path.join(parent, "outside")
    hidden = Path.join(outside, "hidden")
    secret = Path.join(outside, "secret.txt")
    File.mkdir_p!(hidden)
    File.write!(secret, "secret")
    File.chmod!(outside, 0o777)
    File.chmod!(hidden, 0o777)
    File.chmod!(secret, 0o666)
    user = current_user()
    grant_named_user(outside, user, "rwx")
    grant_named_user(hidden, user, "rwx")
    grant_default_user(outside, user, "rwx")
    grant_default_user(hidden, user, "rwx")
    grant_named_user(secret, user, "rw")
    File.chmod!(secret, 0o666)
    File.chmod!(outside, 0o777)
    File.chmod!(hidden, 0o777)
    File.ln_s!(outside, Path.join(media, "escape"))
    File.ln_s!(secret, Path.join(media, "tracks/leak.mp3"))
    assert extended_acl?(secret)

    outside_owner = owner(outside)
    hidden_owner = owner(hidden)
    secret_owner = owner(secret)

    {output, status} = System.cmd("bash", [@script, media], stderr_to_stdout: true)
    assert status == 0, output

    assert owner(outside) == outside_owner
    assert perm(outside) == 0o777
    assert extended_acl?(outside)
    assert default_acl?(outside)
    assert owner(hidden) == hidden_owner
    assert perm(hidden) == 0o777
    assert extended_acl?(hidden)
    assert default_acl?(hidden)
    assert owner(secret) == secret_owner
    assert perm(secret) == 0o666
    assert extended_acl?(secret)
    assert File.lstat!(Path.join(media, "escape")).type == :symlink
    assert File.lstat!(Path.join(media, "tracks/leak.mp3")).type == :symlink
  end

  test "does not walk a media path that is a symlink", %{media: media} do
    parent = Path.dirname(media)
    outside = Path.join(parent, "linked-media")
    hidden = Path.join(outside, "hidden")
    File.mkdir_p!(hidden)
    File.chmod!(outside, 0o777)
    File.chmod!(hidden, 0o777)
    link = Path.join(parent, "media-link")
    File.ln_s!(outside, link)

    outside_owner = owner(outside)
    hidden_owner = owner(hidden)

    {output, status} = System.cmd("bash", [@script, link], stderr_to_stdout: true)

    assert status == 0, output
    assert owner(outside) == outside_owner
    assert perm(outside) == 0o777
    assert owner(hidden) == hidden_owner
    assert perm(hidden) == 0o777
  end

  test "a directory replaced by a symlink during the walk is not chowned" do
    code = """
    import os, stat, subprocess, tempfile, threading, ctypes, ctypes.util, sys
    libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.restype = ctypes.c_int
    base = tempfile.mkdtemp(prefix="ownrace-")
    media = os.path.join(base, "media")
    outside = os.path.join(base, "outside")
    nested = os.path.join(media, "tracks", "nested")
    os.makedirs(os.path.join(nested, "deep"))
    os.makedirs(os.path.join(outside, "deep"))
    os.chmod(media, 0o755)
    for p in (os.path.join(media, "tracks"), nested, os.path.join(nested, "deep"), outside, os.path.join(outside, "deep")):
        os.chmod(p, 0o777)
    def snap(p):
        st = os.lstat(p)
        return (stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid)
    before = {p: snap(p) for p in (outside, os.path.join(outside, "deep"))}
    fd = libc.inotify_init1(0x80000)
    if libc.inotify_add_watch(fd, nested.encode(), 0x20) < 0:
        sys.exit("inotify_add_watch failed")
    def swap():
        os.read(fd, 4096)
        # The parent may already be nobody and not other-writable. The swap
        # still has to win, or this test never exercises the replacement.
        subprocess.run(["sudo", "mv", nested, nested + ".real"], check=True)
        subprocess.run(["sudo", "ln", "-s", outside, nested], check=True)
    thread = threading.Thread(target=swap, daemon=True)
    thread.start()
    subprocess.run(["bash", sys.argv[1], media], check=False)
    thread.join(timeout=5)
    bad = any(snap(p) != before[p] for p in before)
    swapped = os.path.islink(nested) and os.path.isdir(nested + ".real")
    subprocess.run(["sudo", "rm", "-rf", "--", base], check=False)
    if bad or not swapped or thread.is_alive():
        sys.exit(1)
    """

    {output, status} = System.cmd("python3", ["-c", code, @script], stderr_to_stdout: true)
    assert status == 0, output
  end

  test "owns a descendant chain deeper than the interpreter recursion limit", %{
    media: media,
    nobody: {uid, gid}
  } do
    {leaf_out, 0} =
      System.cmd("python3", [
        "-c",
        """
        import os, sys
        path = sys.argv[1]
        for _ in range(1200):
            path = os.path.join(path, "d")
            os.mkdir(path)
        print(path)
        """,
        media
      ])

    leaf = String.trim(leaf_out)

    {output, status} = System.cmd("bash", [@script, media], stderr_to_stdout: true)
    assert status == 0, output
    assert owner(leaf) == {uid, gid}
    assert Bitwise.band(perm(leaf), 0o002) == 0
  end

  defp current_user do
    {out, 0} = System.cmd("id", ["-un"])
    String.trim(out)
  end

  defp grant_named_user(path, user, perms) do
    {output, status} =
      System.cmd("setfacl", ["-m", "u:#{user}:#{perms}", "--", path], stderr_to_stdout: true)

    assert status == 0, output
  end

  defp grant_default_user(path, user, perms) do
    {output, status} =
      System.cmd(
        "setfacl",
        ["-d", "-m", "u:#{user}:#{perms}", "--", path],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  defp extended_acl?(path) do
    {out, 0} = System.cmd("getfacl", ["-c", "-p", "--", path])

    out
    |> String.split("\n", trim: true)
    |> Enum.any?(fn line ->
      named_user_entry?(line) or named_group_entry?(line) or String.starts_with?(line, "mask:") or
        String.starts_with?(line, "default:")
    end)
  end

  defp default_acl?(path) do
    {out, 0} = System.cmd("getfacl", ["-c", "-p", "--", path])
    out |> String.split("\n", trim: true) |> Enum.any?(&String.starts_with?(&1, "default:"))
  end

  defp named_user_entry?(line) do
    String.starts_with?(line, "user:") and not String.starts_with?(line, "user::")
  end

  defp named_group_entry?(line) do
    String.starts_with?(line, "group:") and not String.starts_with?(line, "group::")
  end

  defp nobody_ids do
    {uid_out, 0} = System.cmd("id", ["-u", "nobody"])
    {group_out, 0} = System.cmd("getent", ["group", "nogroup"])
    gid = group_out |> String.split(":") |> Enum.at(2)
    {String.to_integer(String.trim(uid_out)), String.to_integer(gid)}
  end

  defp owner(path) do
    stat = File.lstat!(path)
    {stat.uid, stat.gid}
  end

  defp perm(path) do
    Bitwise.band(File.lstat!(path).mode, 0o777)
  end
end
