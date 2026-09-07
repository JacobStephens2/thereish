defmodule MeaningGameWeb.LayoutTest do
  @moduledoc """
  Tests for the root layout (ticket 11: Umami counts the door).
  """
  use MeaningGameWeb.ConnCase, async: false

  setup do
    original_config = Application.get_env(:meaning_game, :umami)

    on_exit(fn ->
      if original_config do
        Application.put_env(:meaning_game, :umami, original_config)
      else
        Application.delete_env(:meaning_game, :umami)
      end
    end)

    :ok
  end

  describe "Umami tracking tag in root layout" do
    test "renders deferred script tag with website id across pages when configured", %{conn: conn} do
      Application.put_env(:meaning_game, :umami,
        script_url: "https://umami.stephens.page/script.js",
        website_id: "3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d"
      )

      for path <- [~p"/", ~p"/spend", ~p"/check"] do
        page_conn = get(conn, path)
        html = html_response(page_conn, 200)

        assert html =~
                 ~s(<script defer src="https://umami.stephens.page/script.js" data-website-id="3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d">)
      end
    end

    test "renders no script tag when website_id is missing", %{conn: conn} do
      Application.put_env(:meaning_game, :umami,
        script_url: "https://umami.stephens.page/script.js",
        website_id: nil
      )

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      refute html =~ "umami.stephens.page"
      refute html =~ "data-website-id"
    end

    test "renders no script tag when script_url is missing", %{conn: conn} do
      Application.put_env(:meaning_game, :umami,
        script_url: nil,
        website_id: "3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d"
      )

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      refute html =~ "3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d"
      refute html =~ "data-website-id"
    end

    test "renders no script tag when unconfigured", %{conn: conn} do
      Application.delete_env(:meaning_game, :umami)

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      refute html =~ "data-website-id"
    end
  end
end
