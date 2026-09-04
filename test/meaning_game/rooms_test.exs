defmodule MeaningGame.RoomsTest do
  @moduledoc """
  The Room through its own interface: join, rejoin, snapshot.

  Not async, because a Room is a process of its own and has to borrow the test's
  database connection.
  """
  use MeaningGame.DataCase, async: false

  import MeaningGame.RoomFixtures

  alias MeaningGame.Rooms
  alias MeaningGame.Rooms.Server

  describe "joining by name" do
    test "two players join a Room and both appear in the roster" do
      slug = open_room()

      assert {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
      assert {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      view = Rooms.snapshot(slug, melissa.id)

      assert Enum.map(view.seats, & &1.name) == ["Melissa", "Jacob"]
      assert view.open_seats == 0
      refute melissa.id == jacob.id
    end

    test "a third player joins a Room built for three" do
      slug = open_room(seat_limit: 3)

      assert {:ok, _} = Rooms.join(slug, "Melissa", device_token())
      assert {:ok, _} = Rooms.join(slug, "Jacob", device_token())
      assert {:ok, _} = Rooms.join(slug, "Ada", device_token())

      assert Rooms.snapshot(slug, nil).open_seats == 0
    end

    test "a third player is turned away from a Room built for two" do
      slug = open_room(seat_limit: 2)

      {:ok, _} = Rooms.join(slug, "Melissa", device_token())
      {:ok, _} = Rooms.join(slug, "Jacob", device_token())

      assert {:error, :room_full} = Rooms.join(slug, "Ada", device_token())
      assert length(Rooms.snapshot(slug, nil).seats) == 2
    end

    test "a name is all that is asked for, and it has to be something" do
      slug = open_room()

      assert {:error, :name_required} = Rooms.join(slug, "   ", device_token())
      assert {:error, :name_required} = Rooms.join(slug, "", device_token())

      assert {:error, :name_too_long} =
               Rooms.join(slug, String.duplicate("a", 25), device_token())
    end

    test "surrounding whitespace is not part of a name" do
      slug = open_room()

      assert {:ok, seat} = Rooms.join(slug, "  Melissa \n", device_token())
      assert seat.name == "Melissa"
    end
  end

  describe "rejoining" do
    setup do
      slug = open_room()
      token = device_token()
      {:ok, seat} = Rooms.join(slug, "Melissa", token)

      %{slug: slug, token: token, seat: seat}
    end

    test "a browser that already holds a Seat is back in it without typing", ctx do
      assert {:ok, seat} = Rooms.rejoin(ctx.slug, ctx.token)
      assert seat.id == ctx.seat.id
    end

    test "a browser with no Seat here is nobody", ctx do
      assert :error = Rooms.rejoin(ctx.slug, device_token())
    end

    test "joining again from the same browser lands in the same Seat", ctx do
      assert {:ok, seat} = Rooms.join(ctx.slug, "Melissa", ctx.token)
      assert seat.id == ctx.seat.id
      assert length(Rooms.snapshot(ctx.slug, nil).seats) == 1
    end

    test "a browser that forgot its token gets its Seat back by name", ctx do
      new_token = device_token()

      assert {:ok, seat} = Rooms.join(ctx.slug, "melissa", new_token)
      assert seat.id == ctx.seat.id
      assert length(Rooms.snapshot(ctx.slug, nil).seats) == 1
      assert {:ok, ^seat} = Rooms.rejoin(ctx.slug, new_token)
    end

    test "claiming a Seat by name does not evict the browser already holding it", ctx do
      second_browser = device_token()
      {:ok, _} = Rooms.join(ctx.slug, "Melissa", second_browser)

      # The Pixel that was here first is still here, still Melissa, still
      # without typing anything.
      assert Rooms.rejoin(ctx.slug, ctx.token) == {:ok, ctx.seat}
      assert Rooms.rejoin(ctx.slug, second_browser) == {:ok, ctx.seat}
      assert length(Rooms.snapshot(ctx.slug, nil).seats) == 1
    end

    test "a full Room still lets its own players back in", ctx do
      {:ok, _} = Rooms.join(ctx.slug, "Jacob", device_token())
      assert Rooms.snapshot(ctx.slug, nil).open_seats == 0

      forgetful = device_token()
      assert {:ok, seat} = Rooms.join(ctx.slug, "Melissa", forgetful)
      assert seat.id == ctx.seat.id
    end

    test "a phone that is already seated cannot take another Seat by typing its name", ctx do
      jacob_token = device_token()
      {:ok, jacob} = Rooms.join(ctx.slug, "Jacob", jacob_token)

      assert {:ok, seat} = Rooms.join(ctx.slug, "Jacob", ctx.token)
      assert seat.id == ctx.seat.id
      assert Rooms.rejoin(ctx.slug, jacob_token) == {:ok, jacob}
    end
  end

  describe "snapshots" do
    test "a Seat whose client process dies snapshots back to the identical view" do
      slug = open_room()
      token = device_token()
      {:ok, melissa} = Rooms.join(slug, "Melissa", token)
      {:ok, _} = Rooms.join(slug, "Jacob", device_token())
      before = Rooms.snapshot(slug, melissa.id)

      # The phone locks. Its view process — the Room's only client — goes away,
      # and the Room is told nothing, because there is nothing it needs to do.
      {client, ref} = spawn_monitor(fn -> Rooms.snapshot(slug, melissa.id) end)
      assert_receive {:DOWN, ^ref, :process, ^client, :normal}

      # It wakes and asks for everything rather than for what it missed.
      assert Process.alive?(GenServer.whereis(Server.via(slug)))
      assert Rooms.rejoin(slug, token) == {:ok, melissa}
      assert Rooms.snapshot(slug, melissa.id) == before
    end

    test "the stage and the phones are told the same roster" do
      slug = open_room()
      {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      stage = Rooms.snapshot(slug, nil)

      assert Enum.map(stage.seats, & &1.name) ==
               Enum.map(Rooms.snapshot(slug, melissa.id).seats, & &1.name)

      assert Enum.map(stage.seats, & &1.name) ==
               Enum.map(Rooms.snapshot(slug, jacob.id).seats, & &1.name)

      assert stage.you == nil
      assert Rooms.snapshot(slug, jacob.id).you.name == "Jacob"
    end
  end

  describe "playing a Page" do
    setup do
      slug = open_room()
      {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.subscribe(slug)

      %{slug: slug, melissa: melissa, jacob: jacob}
    end

    test "the Anchors are up for both phones and the stage", ctx do
      for viewer <- [ctx.melissa.id, ctx.jacob.id, nil] do
        view = Rooms.snapshot(ctx.slug, viewer)

        assert view.phase == :bridging
        assert [_lantern, _harbour] = view.anchors
      end
    end

    test "the last Bridge in fires the Assayer and the reveal lands", ctx do
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, "cairn")
      assert Rooms.snapshot(ctx.slug, nil).phase == :bridging

      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")

      assert_receive :room_changed
      view = await_reveal(ctx.slug)

      assert view.reveal.closeness == 80
      assert view.reveal.band == :meld
      assert view.reveal.melded?
      assert Enum.map(view.reveal.bridges, & &1.bridge) == ["cairn", "cairo"]
      assert [pair] = view.reveal.pairs
      assert pair.reasoning =~ "cairn"
    end

    test "the reveal is held for the beat rather than shown the moment it is graded", ctx do
      beat(200)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "beacon")

      # Long enough for the fake Assayer to have answered several times over,
      # and well short of the beat the players were promised.
      Process.sleep(50)
      assert Rooms.snapshot(ctx.slug, nil).phase == :assaying

      assert await_reveal(ctx.slug).reveal.closeness == 0
    end

    test "a Bridge nobody else can see until they have written their own", ctx do
      :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, "cairn")

      jacob = Rooms.snapshot(ctx.slug, ctx.jacob.id)

      assert jacob.your_bridge == nil
      refute inspect(jacob) =~ "cairn"
      assert Enum.map(jacob.seats, & &1.committed?) == [true, false]
      assert Rooms.snapshot(ctx.slug, ctx.melissa.id).your_bridge == "cairn"
    end

    test "a committed Bridge is final", ctx do
      :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, "cairn")

      assert {:error, :already_committed} =
               Rooms.commit_bridge(ctx.slug, ctx.melissa.id, "beacon")

      assert {:error, :bridge_required} = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "  ")
    end

    test "an Assayer that falls over is a Page that still reveals", ctx do
      keeper(mode: :raise)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")

      view = await_reveal(ctx.slug)

      assert view.reveal.closeness == nil
      refute hd(view.reveal.pairs).graded?
      assert Process.alive?(GenServer.whereis(Server.via(ctx.slug)))
    end

    test "an Assayer with no verdict hands the call to the players", ctx do
      keeper(mode: :unavailable)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")

      view = await_reveal(ctx.slug)

      assert view.reveal.closeness == nil
      assert view.reveal.melded? == false
      refute hd(view.reveal.pairs).graded?
      assert Enum.map(view.reveal.bridges, & &1.bridge) == ["cairn", "cairo"]
    end

    test "a phone that slept through the whole Page snapshots straight into the reveal", ctx do
      :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")
      await_reveal(ctx.slug)

      melissa = Rooms.snapshot(ctx.slug, ctx.melissa.id)

      # They melded, so the Page she woke into is a Page that has ended.
      assert melissa.phase == :closed
      assert melissa.reveal == Rooms.snapshot(ctx.slug, nil).reveal
    end

    test "a slow Assayer does not block the Room", ctx do
      keeper(delay_ms: 100)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")

      # The Room answers while the verdict is still out.
      assert Rooms.snapshot(ctx.slug, nil).phase == :assaying
      assert await_reveal(ctx.slug).reveal.closeness == 80
    end
  end

  describe "the attempt ladder" do
    setup do
      slug = open_room()
      {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      %{slug: slug, melissa: melissa, jacob: jacob}
    end

    # One attempt, missed or melded depending on the two words handed in.
    defp play(ctx, melissa_bridge, jacob_bridge) do
      :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, melissa_bridge)
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, jacob_bridge)

      await_reveal(ctx.slug)
    end

    test "a miss carries both Bridges forward and the next attempt is up", ctx do
      view = play(ctx, "cairn", "beacon")

      assert view.phase == :reveal
      assert view.next_anchors == ["cairn", "beacon"]

      assert :ok = Rooms.next_attempt(ctx.slug, ctx.melissa.id)

      for viewer <- [ctx.melissa.id, ctx.jacob.id, nil] do
        view = Rooms.snapshot(ctx.slug, viewer)

        assert view.phase == :bridging
        assert view.anchors == ["cairn", "beacon"]
        assert view.attempt.number == 2
        assert view.your_bridge == nil
      end
    end

    test "the Room is not the thing that decides to try again", ctx do
      play(ctx, "cairn", "beacon")

      # Nobody has tapped, so the reveal is still up and still the same one.
      Process.sleep(20)

      assert Rooms.snapshot(ctx.slug, nil).phase == :reveal
      assert Rooms.snapshot(ctx.slug, nil).attempt.number == 1
    end

    test "only a Seat in the Room can start the next attempt", ctx do
      play(ctx, "cairn", "beacon")

      assert {:error, :no_such_seat} = Rooms.next_attempt(ctx.slug, Ecto.UUID.generate())
      assert Rooms.snapshot(ctx.slug, nil).attempt.number == 1
    end

    test "a Meld closes the Page there and then", ctx do
      view = play(ctx, "cairn", "cairo")

      assert view.phase == :closed
      assert view.closed == %{because: :meld, attempt: 1}
      assert view.reveal.melded?
      assert {:error, :page_closed} = Rooms.next_attempt(ctx.slug, ctx.melissa.id)
    end

    test "the last attempt closes the Page unmelded", ctx do
      attempt_cap(2)

      play(ctx, "cairn", "beacon")
      :ok = Rooms.next_attempt(ctx.slug, ctx.jacob.id)
      view = play(ctx, "wharf", "gantry")

      assert view.phase == :closed
      assert view.closed == %{because: :attempts_spent, attempt: 2}
      refute view.reveal.melded?
      assert Enum.map(view.played, & &1.anchors) == [["lantern", "harbour"]]
    end

    test "one more? is a fresh Page with the same Seats", ctx do
      play(ctx, "cairn", "cairo")

      assert :ok = Rooms.next_page(ctx.slug, ctx.melissa.id)

      for viewer <- [ctx.melissa.id, ctx.jacob.id, nil] do
        view = Rooms.snapshot(ctx.slug, viewer)

        assert view.phase == :bridging
        assert view.attempt.number == 1
        assert view.anchors != ["lantern", "harbour"]
        assert view.reveal == nil
        assert view.played == []
        assert Enum.map(view.seats, & &1.name) == ["Melissa", "Jacob"]
      end
    end

    test "one more? is refused while the Page is still being played", ctx do
      assert {:error, :page_open} = Rooms.next_page(ctx.slug, ctx.melissa.id)

      play(ctx, "cairn", "beacon")

      assert {:error, :page_open} = Rooms.next_page(ctx.slug, ctx.melissa.id)
    end
  end

  describe "supervision" do
    test "a crashed Room comes back with its Seats" do
      slug = open_room()
      token = device_token()
      {:ok, melissa} = Rooms.join(slug, "Melissa", token)
      before = Rooms.snapshot(slug, melissa.id)

      pid = GenServer.whereis(Server.via(slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      assert once_restarted(fn -> Rooms.snapshot(slug, melissa.id) end) == before
      assert Rooms.rejoin(slug, token) == {:ok, melissa}
    end

    test "a crashed Room comes back at the Anchors, and the Page in progress is gone" do
      slug = open_room()
      {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.commit_bridge(slug, melissa.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairo")
      await_reveal(slug)

      pid = GenServer.whereis(Server.via(slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      # Bridges and verdicts live in the process and nowhere else, so this is
      # what a crash costs until the Chronicle writes Page events down. Both
      # Seats are still here; the Page they were playing is not.
      view = once_restarted(fn -> Rooms.snapshot(slug, melissa.id) end)

      assert view.phase == :bridging
      assert view.reveal == nil
      assert view.your_bridge == nil
      assert Enum.map(view.seats, & &1.name) == ["Melissa", "Jacob"]
    end
  end

  describe "opening a Room" do
    test "a slug no Room could have is no Room, not a new one" do
      assert {:error, :bad_slug} = Rooms.ensure_started("Not A Slug")
      assert {:error, :bad_slug} = Rooms.ensure_started("")

      assert_raise MeaningGame.Rooms.NoSuchRoomError, fn -> Rooms.open!("Not A Slug") end
    end

    test "opening the same Room twice is the same Room" do
      slug = open_room()

      assert Rooms.open!(slug) == slug
      assert {:ok, _} = Rooms.join(slug, "Melissa", device_token())
      assert Rooms.open!(slug) == slug
      assert length(Rooms.snapshot(slug, nil).seats) == 1
    end
  end

  describe "subscriptions" do
    test "a subscriber hears about a new Seat" do
      slug = open_room()
      :ok = Rooms.subscribe(slug)

      {:ok, _} = Rooms.join(slug, "Melissa", device_token())

      assert_receive :room_changed
    end
  end

  # The registry entry outlives the process it points at by a moment, so a call
  # made the instant after a kill can land on a corpse.
  defp once_restarted(fun, tries \\ 50) do
    fun.()
  catch
    :exit, reason ->
      if tries > 0 do
        Process.sleep(10)
        once_restarted(fun, tries - 1)
      else
        exit(reason)
      end
  end
end
