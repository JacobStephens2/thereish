defmodule ThereishWeb.Plugs.MediaStatic do
  @moduledoc """
  Serves media files (tracks, generated audio) from the server's media directory.

  Every request whose first path segment is "media" is halted, whether or not
  a file is sent. Plug.Static uses that same segment, and it drops empty
  segments, so a path with extra slashes is still the prefix. A file is sent
  only when it stays inside the directory. A path that climbs out, a link that
  points out, or a missing file gets no file, and the prefix is still halted
  so Plug.Static does not serve it.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["media" | rest]} = conn, _opts) do
    case path_inside_media_dir(Enum.join(rest, "/")) do
      {:ok, full_path} ->
        conn
        |> Plug.Conn.put_resp_header("content-type", MIME.from_path(full_path))
        |> Plug.Conn.put_resp_header("cache-control", "public, max-age=31536000")
        |> Plug.Conn.send_file(200, full_path)
        |> Plug.Conn.halt()

      :error ->
        conn
        |> Plug.Conn.send_resp(404, "Not Found")
        |> Plug.Conn.halt()
    end
  end

  def call(conn, _opts), do: conn

  defp path_inside_media_dir(rel_path) do
    media_dir = Thereish.Steward.TrackCache.media_dir() |> Path.expand()

    with {:ok, safe_rel} <- Path.safe_relative(rel_path, media_dir),
         full_path = Path.join(media_dir, safe_rel),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(full_path) do
      {:ok, full_path}
    else
      _ -> :error
    end
  end
end
