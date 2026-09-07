defmodule ThereishWeb.ChronicleController do
  @moduledoc """
  Serves the Chronicle as Markdown on demand over HTTP (ticket 08, design brief).
  """
  use ThereishWeb, :controller

  alias Thereish.Chronicle
  alias Thereish.Rooms

  def export(conn, params) do
    slug = Rooms.open!(params["slug"])
    markdown = Chronicle.to_markdown(slug)

    conn
    |> put_resp_content_type("text/markdown; charset=utf-8")
    |> put_resp_header("content-disposition", ~s[inline; filename="chronicle-#{slug}.md"])
    |> send_resp(200, markdown)
  end

  def export_calibration(conn, params) do
    slug = params["slug"]

    format =
      cond do
        conn.assigns[:format] in [:json, :jsonl] -> conn.assigns[:format]
        params["format"] in ["jsonl", :jsonl] -> :jsonl
        true -> :json
      end

    {content_type, ext} =
      case format do
        :jsonl -> {"application/x-ndjson", "jsonl"}
        _ -> {"application/json", "json"}
      end

    filename = if slug, do: "calibration-#{slug}.#{ext}", else: "calibration.#{ext}"
    data = Chronicle.export_calibration(slug, format)

    conn
    |> put_resp_content_type(content_type)
    |> put_resp_header("content-disposition", ~s[inline; filename="#{filename}"])
    |> send_resp(200, data)
  end
end
