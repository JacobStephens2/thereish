defmodule ThereishWeb.Plugs.MediaStatic do
  @moduledoc """
  Serves media files (tracks, generated audio) from the server's media directory.

  A file is sent only when it stays inside that directory. A path that climbs
  out, or a link that points out, is left for the rest of the pipeline.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: "/media/" <> rel_path} = conn, _opts) do
    case path_inside_media_dir(rel_path) do
      {:ok, full_path} ->
        conn
        |> Plug.Conn.put_resp_header("content-type", MIME.from_path(full_path))
        |> Plug.Conn.put_resp_header("cache-control", "public, max-age=31536000")
        |> Plug.Conn.send_file(200, full_path)
        |> Plug.Conn.halt()

      :error ->
        conn
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
