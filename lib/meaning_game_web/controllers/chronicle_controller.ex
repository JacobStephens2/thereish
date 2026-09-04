defmodule MeaningGameWeb.ChronicleController do
  @moduledoc """
  Serves the Chronicle as Markdown on demand over HTTP (ticket 08, design brief).
  """
  use MeaningGameWeb, :controller

  alias MeaningGame.Chronicle
  alias MeaningGame.Rooms

  def export(conn, params) do
    slug = Rooms.open!(params["slug"] || Rooms.default_slug())
    markdown = Chronicle.to_markdown(slug)

    conn
    |> put_resp_content_type("text/markdown; charset=utf-8")
    |> put_resp_header("content-disposition", ~s[inline; filename="chronicle-#{slug}.md"])
    |> send_resp(200, markdown)
  end
end
