defmodule Thereish.Foley.RepertoireTest do
  use Thereish.DataCase, async: true

  alias Thereish.Chronicle.Page
  alias Thereish.Foley.Loops
  alias Thereish.Foley.Repertoire
  alias Thereish.Foley.Track
  alias Thereish.Foley.Vamp
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
      music_meta: %Track{path: path, title: title, meta: %{"provider" => "fake"}},
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

    test "a Page's Vamp is not a Repertoire member, even when kept beside its Track" do
      room = create_test_room("vamp-not-repertoire")
      now = DateTime.utc_now()

      %Page{}
      |> Page.changeset(%{
        room_id: room.id,
        document: %{bookends: ["sun", "moon"]},
        author_meta: %{arm: "flash"},
        music_meta: %Track{
          path: "/media/tracks/cabin.mp3",
          title: "Cabin Warmth",
          meta: %{"provider" => "fake"}
        },
        vamp_meta: %Vamp{path: "/media/vamps/cabin-vamp.mp3", duration: 30, loop: true},
        closed_because: "meld",
        melded: true,
        closeness: 95,
        opened_at: now,
        closed_at: now
      })
      |> Repo.insert!()

      paths = Enum.map(Repertoire.members(room.id), & &1.path)
      assert "/media/tracks/cabin.mp3" in paths
      refute "/media/vamps/cabin-vamp.mp3" in paths
    end

    test "failed or unfinished scores in Chronicle do not count toward settled status" do
      room = create_test_room("failed-score-room")

      # Insert page with a failed Track
      now = DateTime.utc_now()

      %Page{}
      |> Page.changeset(%{
        room_id: room.id,
        document: %{bookends: ["sun", "moon"]},
        author_meta: %{arm: "flash"},
        music_meta: Track.failed(:timeout),
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

    test "deal/2 returns eligible members excluding previous/current member" do
      room = create_test_room("deal-room")
      members = Repertoire.members(room.id)
      first = hd(members)

      deal = Repertoire.deal(room.id, first.path)
      assert length(deal) == length(members) - 1
      refute Enum.any?(deal, fn m -> m.path == first.path end)
    end

    test "next_deal/3 advances through the deal without repeats, then reshuffles never repeating current" do
      room = create_test_room("session-shuffle-room")
      members = Repertoire.members(room.id)
      first = hd(members)
      deal = Repertoire.deal(room.id, first.path)

      # Step through the deal
      {played, remaining_deal, last_played} =
        Enum.reduce(1..(length(members) - 1), {[], deal, first}, fn _,
                                                                    {seen, current_deal,
                                                                     current_playing} ->
          assert {:ok, next_track, new_deal} =
                   Repertoire.next_deal(room.id, current_deal, current_playing.path)

          refute next_track.path in seen
          refute next_track.path == current_playing.path
          {[next_track.path | seen], new_deal, next_track}
        end)

      # Entire rest of the Repertoire was played exactly once
      assert length(played) == length(members) - 1
      assert remaining_deal == []

      # Deal is now exhausted. Next call must reshuffle, never returning the thing now playing
      assert {:ok, reshuffled_next, new_deal} =
               Repertoire.next_deal(room.id, remaining_deal, last_played.path)

      refute reshuffled_next.path == last_played.path
      assert length(new_deal) == length(members) - 2
    end

    test "deal/2 and next_deal/3 accept an explicit list of members" do
      custom_members = [
        %{name: "Song A", title: "Song A", path: "/a.mp3"},
        %{name: "Song B", title: "Song B", path: "/b.mp3"},
        %{name: "Song C", title: "Song C", path: "/c.mp3"}
      ]

      deal = Repertoire.deal(custom_members, "/a.mp3")
      assert length(deal) == 2
      refute Enum.any?(deal, &(&1.path == "/a.mp3"))

      assert {:ok, next_song, remaining} = Repertoire.next_deal(custom_members, deal, "/a.mp3")
      refute next_song.path == "/a.mp3"
      assert length(remaining) == 1
    end

    test "members/1 excludes members marked Never for that Room, preserving them in other Rooms" do
      room_a = create_test_room("never-room-a")
      room_b = create_test_room("never-room-b")

      loops = Repertoire.shipped_loops()
      assert length(loops) == 5
      never_loop = hd(loops)

      # Record Never for room_a
      {:ok, _} = Thereish.Rooms.Store.record_never(room_a.id, never_loop.path)

      assert Repertoire.nevers(room_a.id) == [never_loop.path]
      assert Repertoire.nevers(room_b.id) == []

      # Room A excludes the never'd loop
      members_a = Repertoire.members(room_a.id)
      assert length(members_a) == 4
      refute Enum.any?(members_a, fn m -> m.path == never_loop.path end)

      # Room B still includes that loop (cross-Room isolation)
      members_b = Repertoire.members(room_b.id)
      assert length(members_b) == 5
      assert Enum.any?(members_b, fn m -> m.path == never_loop.path end)
    end

    test "advance_after_never/3 returns the sole remaining member when 1 member remains" do
      single = %{name: "Only", title: "Only", path: "/only.mp3"}
      assert {:ok, member, deal} = Repertoire.advance_after_never([single], [], "/nevered.mp3")
      assert member.path == "/only.mp3"
      assert deal == []
    end

    test "advance_after_never/3 advances deal or reshuffles when more than 1 member remains" do
      members = [
        %{name: "A", title: "A", path: "/a.mp3"},
        %{name: "B", title: "B", path: "/b.mp3"}
      ]

      assert {:ok, member, deal} = Repertoire.advance_after_never(members, [], "/nevered.mp3")
      assert member.path in ["/a.mp3", "/b.mp3"]
      assert length(deal) == 1
    end
  end
end
