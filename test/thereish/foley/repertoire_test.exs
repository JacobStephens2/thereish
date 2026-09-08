defmodule Thereish.Foley.RepertoireTest do
  use Thereish.DataCase, async: true

  alias Thereish.Chronicle.Page
  alias Thereish.Foley.Loops
  alias Thereish.Foley.Repertoire
  alias Thereish.Repo
  alias Thereish.Rooms.Room
  alias Thereish.Steward.TrackCache

  defp create_test_room(slug) do
    %Room{}
    |> Room.changeset(%{slug: slug, seat_limit: 2})
    |> Repo.insert!()
  end

  defp insert_chronicle_page_with_track(room_id, path, title) do
    now = DateTime.utc_now()

    %Page{}
    |> Page.changeset(%{
      room_id: room_id,
      document: %{bookends: ["sun", "moon"]},
      author_meta: %{arm: "flash"},
      music_meta: %{
        path: path,
        title: title,
        provider: "fake"
      },
      closed_because: "meld",
      melded: true,
      closeness: 95,
      opened_at: now,
      closed_at: now
    })
    |> Repo.insert!()
  end

  describe "Repertoire pool and draw" do
    test "shipped_loops/0 returns the 5 shipped loops with name and path" do
      shipped = Repertoire.shipped_loops()
      assert length(shipped) == 5

      for loop <- Loops.all() do
        assert Enum.any?(shipped, fn m -> m.path == loop.path and m.name == loop.name end)
      end
    end

    test "an unsettled Room's members include the 5 shipped loops and kept Tracks in TrackCache" do
      room = create_test_room("unsettled-1")

      # Put a stranger's track into TrackCache
      {:ok, _} =
        TrackCache.put(["desert", "night"], %{
          title: "Stranger's Song",
          path: "/media/tracks/stranger.mp3"
        })

      members = Repertoire.members(room.id)
      paths = Enum.map(members, & &1.path)

      # 5 shipped loops are present
      for loop <- Loops.all() do
        assert loop.path in paths
      end

      # Kept track from TrackCache is present
      assert "/media/tracks/stranger.mp3" in paths
      stranger = Enum.find(members, &(&1.path == "/media/tracks/stranger.mp3"))
      assert stranger.name == "Stranger's Song"
      assert stranger.title == "Stranger's Song"
    end

    test "a settled Room's members include its own Chronicle Tracks plus the 5 shipped loops, excluding strangers" do
      room_a = create_test_room("settled-a")
      room_b = create_test_room("settled-b")

      # Room B (stranger) has a kept track in its Chronicle and in TrackCache
      {:ok, _} =
        TrackCache.put(["desert", "night"], %{
          title: "Desert Night",
          path: "/media/tracks/desert.mp3"
        })

      _b_page =
        insert_chronicle_page_with_track(room_b.id, "/media/tracks/desert.mp3", "Desert Night")

      # Room A has its own kept track in its Chronicle
      _a_page =
        insert_chronicle_page_with_track(room_a.id, "/media/tracks/cabin.mp3", "Cabin Warmth")

      # Room A is settled
      assert Repertoire.settled?(room_a.id)

      members_a = Repertoire.members(room_a.id)
      paths_a = Enum.map(members_a, & &1.path)

      # Room A's own track is in the members
      assert "/media/tracks/cabin.mp3" in paths_a

      # 5 shipped loops are still eligible
      for loop <- Loops.all() do
        assert loop.path in paths_a
      end

      # Stranger's track from Room B is NOT in Room A's members
      refute "/media/tracks/desert.mp3" in paths_a
    end

    test "failed or unfinished scores in Chronicle do not count toward settled status" do
      room = create_test_room("failed-score-room")

      # Insert page with failure in music_meta
      now = DateTime.utc_now()

      %Page{}
      |> Page.changeset(%{
        room_id: room.id,
        document: %{bookends: ["sun", "moon"]},
        author_meta: %{arm: "flash"},
        music_meta: %{
          failure: :timeout,
          provider: "fake"
        },
        closed_because: "meld",
        melded: true,
        closeness: 95,
        opened_at: now,
        closed_at: now
      })
      |> Repo.insert!()

      refute Repertoire.settled?(room.id)
      refute Enum.any?(Repertoire.chronicle_tracks(room.id), fn t -> t.path == nil end)
    end

    test "draw/2 returns a member from the pool and does not always pick the same loop" do
      room = create_test_room("draw-room")

      # Over many draws, more than 1 distinct member is chosen
      draws =
        for _ <- 1..30 do
          Repertoire.draw(room.id).path
        end
        |> Enum.uniq()

      assert length(draws) > 1
    end

    test "draw/2 avoids previous member when pool has more than 1 member" do
      room = create_test_room("avoid-prev-room")
      first = Repertoire.draw(room.id)

      for _ <- 1..10 do
        next = Repertoire.draw(room.id, first)
        assert next.path != first.path
      end
    end
  end
end
