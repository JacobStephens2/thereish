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

  describe "GET /r/:slug/calibration.json" do
    test "exports the labelled set as JSON on demand", %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairo")
      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: slug)

      MeaningGame.Chronicle.record_fairness_tap(room.id, %{
        seat_id: ctx.melissa.id,
        attempt_number: 1,
        anchors: ["lantern", "harbour"],
        bridges: ["cairn", "cairo"],
        grade: 80,
        band: "meld",
        model: "gemini-3.8-flash",
        prompt_version: "v1",
        label: "fair"
      })

      conn = get(conn, ~p"/r/#{slug}/calibration.json")

      assert response(conn, 200)
      assert response_content_type(conn, :json) =~ "application/json"
      body = response(conn, 200)
      assert {:ok, [entry]} = Jason.decode(body)
      assert entry["label"] == "fair"
      assert entry["grade"] == 80
      assert entry["anchors"] == ["lantern", "harbour"]
      assert entry["bridges"] == ["cairn", "cairo"]
    end

    test "exports all rooms over /calibration.json and /calibration.jsonl",
         %{conn: conn, slug: slug} = ctx do
      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: slug)

      MeaningGame.Chronicle.record_fairness_tap(room.id, %{
        seat_id: ctx.melissa.id,
        attempt_number: 1,
        anchors: ["lantern", "harbour"],
        bridges: ["cairn", "cairo"],
        grade: 80,
        band: "meld",
        model: "gemini-3.8-flash",
        prompt_version: "v1",
        label: "fair"
      })

      # JSON
      conn_json = get(conn, ~p"/calibration.json")
      assert response(conn_json, 200)
      assert response_content_type(conn_json, :json) =~ "application/json"
      assert {:ok, entries} = Jason.decode(response(conn_json, 200))
      assert length(entries) >= 1

      # JSONL
      conn_jsonl = get(conn, ~p"/calibration.jsonl")
      assert response(conn_jsonl, 200)
      assert [ct] = get_resp_header(conn_jsonl, "content-type")
      assert ct =~ "application/x-ndjson"
      lines = response(conn_jsonl, 200) |> String.trim() |> String.split("\n")
      assert length(lines) >= 1
      assert {:ok, _} = Jason.decode(hd(lines))
    end

    test "exports room-scoped calibration as JSONL over /r/:slug/calibration.jsonl",
         %{conn: conn, slug: slug} = ctx do
      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: slug)

      MeaningGame.Chronicle.record_fairness_tap(room.id, %{
        seat_id: ctx.melissa.id,
        attempt_number: 1,
        anchors: ["lantern", "harbour"],
        bridges: ["cairn", "cairo"],
        grade: 80,
        band: "meld",
        model: "gemini-3.8-flash",
        prompt_version: "v1",
        label: "fair"
      })

      conn = get(conn, ~p"/r/#{slug}/calibration.jsonl")
      assert response(conn, 200)
      assert [ct] = get_resp_header(conn, "content-type")
      assert ct =~ "application/x-ndjson"
      lines = response(conn, 200) |> String.trim() |> String.split("\n")
      assert length(lines) == 1
      assert {:ok, entry} = Jason.decode(hd(lines))
      assert entry["label"] == "fair"
    end
  end
end
