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
    File.ln_s!(outside, Path.join(media, "escape"))
    File.ln_s!(secret, Path.join(media, "tracks/leak.mp3"))

    outside_owner = owner(outside)
    hidden_owner = owner(hidden)
    secret_owner = owner(secret)

    {output, status} = System.cmd("bash", [@script, media], stderr_to_stdout: true)
    assert status == 0, output

    assert owner(outside) == outside_owner
    assert perm(outside) == 0o777
    assert owner(hidden) == hidden_owner
    assert perm(hidden) == 0o777
    assert owner(secret) == secret_owner
    assert perm(secret) == 0o666
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
