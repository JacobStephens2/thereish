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
    refute climbed.resp_body == "outside-bytes"
    refute climbed.halted

    linked = request("/media/tracks/leak.mp3")
    refute linked.resp_body == "outside-bytes"
    refute linked.halted

    kept = request("/media/tracks/kept.mp3")
    assert kept.status == 200
    assert kept.resp_body == "inside-bytes"
  end

  defp request(path) do
    :get
    |> Plug.Test.conn(path)
    |> ThereishWeb.Plugs.MediaStatic.call([])
  end
end
