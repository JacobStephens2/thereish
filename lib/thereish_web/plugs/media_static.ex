defmodule ThereishWeb.Plugs.MediaStatic do
  @moduledoc """
  Serves media files (tracks, generated audio) from the server's media directory.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: "/media/" <> rel_path} = conn, _opts) do
    full_path = Path.join(Thereish.Steward.TrackCache.media_dir(), rel_path)

    if File.regular?(full_path) do
      conn
      |> Plug.Conn.put_resp_header("content-type", MIME.from_path(full_path))
      |> Plug.Conn.put_resp_header("cache-control", "public, max-age=31536000")
      |> Plug.Conn.send_file(200, full_path)
      |> Plug.Conn.halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn
end
