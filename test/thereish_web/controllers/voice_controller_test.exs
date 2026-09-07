defmodule ThereishWeb.VoiceControllerTest do
  use ThereishWeb.ConnCase, async: false

  import Thereish.RoomFixtures

  alias Thereish.Rooms

  setup do
    slug = open_room()
    token_a = device_token()
    token_b = device_token()
    {:ok, mara} = Rooms.join(slug, "Mara", token_a)
    {:ok, jacob} = Rooms.join(slug, "Jacob", token_b)
    :ok = Rooms.give(slug, mara.id, "setting one")
    :ok = Rooms.give(slug, jacob.id, "setting two")
    await_phase(slug, :bridging)

    %{slug: slug, mara: mara, jacob: jacob, token_a: token_a, token_b: token_b}
  end

  describe "GET /r/:slug/voice/:attempt" do
    test "serves audio bytes for the current attempt and 404 for any other",
         %{conn: conn} = ctx do
      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      assert_receive {:voice_ready, 1}, 2000

      # Current attempt 1 serves 200 with audio bytes
      conn1 = get(conn, ~p"/r/#{ctx.slug}/voice/1")
      assert response(conn1, 200)
      assert response_content_type(conn1, :mp3) =~ "audio/mpeg"
      assert byte_size(response(conn1, 200)) > 0

      # Other attempt numbers answer 404
      conn2 = get(conn, ~p"/r/#{ctx.slug}/voice/2")
      assert response(conn2, 404)

      conn_nonexistent_room = get(conn, "/r/nonexistent/voice/1")
      assert response(conn_nonexistent_room, 404)
    end

    test "past attempt audio answers 404 after advancing", %{conn: conn} = ctx do
      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "beacon")
      await_reveal(ctx.slug)

      assert_receive {:voice_ready, 1}, 2000

      conn1 = get(conn, ~p"/r/#{ctx.slug}/voice/1")
      assert response(conn1, 200)

      # Advance to attempt 2
      :ok = Rooms.next_attempt(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :bridging)

      # Attempt 1 now answers 404
      conn_past = get(conn, ~p"/r/#{ctx.slug}/voice/1")
      assert response(conn_past, 404)
    end
  end
end
