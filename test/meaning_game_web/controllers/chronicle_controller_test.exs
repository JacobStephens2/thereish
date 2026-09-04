defmodule MeaningGameWeb.ChronicleControllerTest do
  @moduledoc """
  Tests on-demand Markdown export over HTTP (ticket 08, design brief).
  """
  use MeaningGameWeb.ConnCase, async: false

  import MeaningGame.RoomFixtures

  alias MeaningGame.Rooms

  setup do
    slug = open_room()
    {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    %{slug: slug, melissa: melissa, jacob: jacob}
  end

  defp play(ctx, melissa_bridge, jacob_bridge) do
    :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, melissa_bridge)
    :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, jacob_bridge)

    await_reveal(ctx.slug)
  end

  describe "GET /r/:slug/chronicle.md" do
    test "exports the Chronicle as Markdown on demand", %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairo")

      conn = get(conn, ~p"/r/#{slug}/chronicle.md")

      assert response(conn, 200)
      assert response_content_type(conn, :markdown) =~ "text/markdown"
      body = response(conn, 200)

      assert body =~ "# The Chronicle"
      assert body =~ "## Room: #{slug}"
      assert body =~ "Page 1: lantern · harbour"
      assert body =~ "Melissa: cairn"
      assert body =~ "Jacob: cairo"
      assert body =~ "Closeness: 80 / 100 (meld)"
    end

    test "exports the default room over /chronicle.md", %{conn: conn} do
      default_slug = Rooms.default_slug()
      open_room(slug: default_slug)

      conn = get(conn, ~p"/chronicle.md")

      assert response(conn, 200)
      assert response_content_type(conn, :markdown) =~ "text/markdown"
      assert response(conn, 200) =~ "## Room: #{default_slug}"
    end

    test "returns 404 for an unknown room", %{conn: conn} do
      assert_error_sent 404, fn ->
        get(conn, "/r/NOT-A-SLUG/chronicle.md")
      end
    end
  end
end
