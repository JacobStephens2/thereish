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

  import Phoenix.LiveViewTest

  describe "MeaningGame.Umami.config/0" do
    test "returns map when both script_url and website_id are non-empty strings" do
      Application.put_env(:meaning_game, :umami,
        script_url: "https://umami.example.com/script.js",
        website_id: "abc-123"
      )

      assert MeaningGame.Umami.config() == %{
               script_url: "https://umami.example.com/script.js",
               website_id: "abc-123"
             }

      assert MeaningGame.umami_config() == %{
               script_url: "https://umami.example.com/script.js",
               website_id: "abc-123"
             }
    end

    test "returns nil when script_url is empty or nil" do
      Application.put_env(:meaning_game, :umami, script_url: "", website_id: "abc-123")
      assert MeaningGame.Umami.config() == nil

      Application.put_env(:meaning_game, :umami, script_url: nil, website_id: "abc-123")
      assert MeaningGame.Umami.config() == nil
    end

    test "returns nil when website_id is empty or nil" do
      Application.put_env(:meaning_game, :umami,
        script_url: "https://umami.example.com/script.js",
        website_id: ""
      )

      assert MeaningGame.Umami.config() == nil

      Application.put_env(:meaning_game, :umami,
        script_url: "https://umami.example.com/script.js",
        website_id: nil
      )

      assert MeaningGame.Umami.config() == nil
    end

    test "returns nil when unconfigured" do
      Application.delete_env(:meaning_game, :umami)
      assert MeaningGame.Umami.config() == nil
    end
  end

  describe "Umami tracking tag in LiveView and controller layouts" do
    test "renders deferred script tag with website id across controller pages when configured", %{conn: conn} do
      Application.put_env(:meaning_game, :umami,
        script_url: "https://umami.stephens.page/script.js",
        website_id: "3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d"
      )

      for path <- [~p"/check"] do
        page_conn = get(conn, path)
        html = html_response(page_conn, 200)

        assert html =~
                 ~s(<script defer src="https://umami.stephens.page/script.js" data-website-id="3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d">)
      end
    end

    test "renders deferred script tag across LiveView pages when configured", %{conn: conn} do
      Application.put_env(:meaning_game, :umami,
        script_url: "https://umami.stephens.page/script.js",
        website_id: "3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d"
      )

      for path <- [~p"/", ~p"/spend"] do
        {:ok, _view, html} = live(conn, path)

        assert html =~ ~s(src="https://umami.stephens.page/script.js")
        assert html =~ ~s(data-website-id="3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d")
        assert html =~ ~r/<script[^>]*defer[^>]*umami\.stephens\.page/
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
