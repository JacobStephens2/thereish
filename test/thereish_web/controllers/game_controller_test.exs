defmodule ThereishWeb.GameControllerTest do
  use ThereishWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the game page says what Thereish is and opens a Room", %{conn: conn} do
    html = conn |> get(~p"/game") |> html_response(200)

    assert html =~ "How a Page goes"
    assert html =~ ~s(data-role="game-new-room")
    assert html =~ ~s(href="/new")
  end

  test "the game page reads its Ladder from configuration", %{conn: conn} do
    html = conn |> get(~p"/game") |> html_response(200)

    for {band, floor} <- Thereish.Ladder.bands() do
      name = band |> Atom.to_string() |> String.replace("_", " ")
      assert html =~ ~r/#{name}\s*<span[^>]*>#{floor}</
    end
  end

  test "the game page carries a description and a share image", %{conn: conn} do
    html = conn |> get(~p"/game") |> html_response(200)

    assert html =~ ~s(<meta name="description")
    assert html =~ ~s(property="og:image")
    assert html =~ "/images/game/og.jpg"
  end

  test "the door links to the game page", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ ~s(data-role="what-is-this")
    assert html =~ ~s(href="/game")
  end
end
