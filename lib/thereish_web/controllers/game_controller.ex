defmodule ThereishWeb.GameController do
  @moduledoc """
  The page that says what Thereish is, for someone who has not played it.

  The door at `/` asks for a Code and nothing else, because the person
  standing at it has been told one. This page is for everyone else: a link
  shared in a message, a search result, a curious friend. It is a plain
  controller render rather than a LiveView, since nothing on it changes.
  """
  use ThereishWeb, :controller

  def show(conn, _params) do
    conn
    |> assign(:page_title, "Thereish · a couch word game")
    |> assign(
      :description,
      "Two far-apart words. Everyone writes the word that bridges them, " <>
        "and a machine grades how close the table landed. " <>
        "For two to six phones and a laptop. No accounts, nothing to install."
    )
    |> assign(:og_image, url(~p"/images/game/og.jpg"))
    |> render(:show)
  end
end
