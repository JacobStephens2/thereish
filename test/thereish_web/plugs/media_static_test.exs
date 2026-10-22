defmodule ThereishWeb.Plugs.MediaStaticTest do
  use ExUnit.Case, async: false

  setup do
    parent =
      Path.join(System.tmp_dir!(), "thereish-media-static-#{System.unique_integer([:positive])}")

    media_dir = Path.join(parent, "media")
    secret = Path.join(parent, "secret.txt")

    File.mkdir_p!(Path.join(media_dir, "tracks"))
    File.write!(Path.join(media_dir, "tracks/kept.mp3"), "inside-bytes")
    File.write!(secret, "outside-bytes")
    File.ln_s!(secret, Path.join(media_dir, "tracks/leak.mp3"))

    previous = Application.get_env(:thereish, :media_dir)
    Application.put_env(:thereish, :media_dir, media_dir)

    on_exit(fn ->
      if previous do
        Application.put_env(:thereish, :media_dir, previous)
      else
        Application.delete_env(:thereish, :media_dir)
      end

      File.rm_rf(parent)
    end)

    :ok
  end

  test "sends a file only when it stays inside the media directory" do
    climbed = request("/media/../secret.txt")
    assert climbed.halted
    assert climbed.status == 404
    refute climbed.resp_body == "outside-bytes"

    linked = request("/media/tracks/leak.mp3")
    assert linked.halted
    assert linked.status == 404
    refute linked.resp_body == "outside-bytes"

    missing = request("/media/tracks/missing.mp3")
    assert missing.halted
    assert missing.status == 404

    bare = request("/media")
    assert bare.halted
    assert bare.status == 404

    kept = request("/media/tracks/kept.mp3")
    assert kept.halted
    assert kept.status == 200
    assert kept.resp_body == "inside-bytes"
  end

  test "keeps media in the static paths" do
    assert "media" in ThereishWeb.static_paths()
  end

  test "leaves a path outside the /media prefix for the rest of the pipeline" do
    admin = request("/admin/media")
    refute admin.halted

    other = request("/median")
    refute other.halted
  end

  test "halts a /media path whose extra slashes Plug.Static would ignore" do
    parent =
      Path.join(System.tmp_dir!(), "thereish-media-prefix-#{System.unique_integer([:positive])}")

    static_root = Path.join(parent, "static")
    media = Path.join(static_root, "media")
    secret = Path.join(parent, "secret.txt")
    File.mkdir_p!(media)
    File.write!(secret, "outside-bytes")
    File.ln_s!(secret, Path.join(media, "leak-out.txt"))

    static_opts =
      Plug.Static.init(
        at: "/",
        from: static_root,
        gzip: false,
        only: ThereishWeb.static_paths(),
        raise_on_missing_only: false
      )

    build = fn path ->
      base = Plug.Test.conn(:get, "/placeholder")

      segments =
        for segment <- :binary.split(path, "/", [:global]), segment != "", do: segment

      %{base | request_path: path, path_info: segments}
    end

    pipeline = fn path ->
      conn = ThereishWeb.Plugs.MediaStatic.call(build.(path), [])

      if conn.halted do
        conn
      else
        Plug.Static.call(conn, static_opts)
      end
    end

    on_exit(fn -> File.rm_rf!(parent) end)

    served = pipeline.("//media/leak-out.txt")
    assert served.halted
    assert served.status == 404
    refute served.resp_body == "outside-bytes"

    deeper = pipeline.("///media/leak-out.txt")
    assert deeper.halted
    assert deeper.status == 404
    refute deeper.resp_body == "outside-bytes"

    missing = pipeline.("//media/missing.txt")
    assert missing.halted
    assert missing.status == 404

    bare = pipeline.("//media")
    assert bare.halted
    assert bare.status == 404
  end

  defp request(path) do
    :get
    |> Plug.Test.conn(path)
    |> ThereishWeb.Plugs.MediaStatic.call([])
  end
end
