defmodule MeaningGame.RoomsTest do
  @moduledoc """
  The Room through its own interface: join, rejoin, snapshot.

  Not async, because a Room is a process of its own and has to borrow the test's
  database connection.
  """
  use MeaningGame.DataCase, async: false

  import MeaningGame.RoomFixtures

  alias MeaningGame.Chronicle
  alias MeaningGame.Rooms
  alias MeaningGame.Rooms.Server
  alias MeaningGame.Rooms.Store

  describe "joining by name" do
    test "two players join a Room and both appear in the roster" do
      slug = open_room()

      assert {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      assert {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      view = Rooms.snapshot(slug, mara.id)

      assert Enum.map(view.seats, & &1.name) == ["Mara", "Jacob"]
      assert view.open_seats == 0
      refute mara.id == jacob.id
    end

    test "a third player joins a Room built for three" do
      slug = open_room(seat_limit: 3)

      assert {:ok, _} = Rooms.join(slug, "Mara", device_token())
      assert {:ok, _} = Rooms.join(slug, "Jacob", device_token())
      assert {:ok, _} = Rooms.join(slug, "Ada", device_token())

      assert Rooms.snapshot(slug, nil).open_seats == 0
    end

    test "a Room at the Assayer's cap plays, and every Bridge in it is graded together" do
      slug = open_room(seat_limit: MeaningGame.Steward.seat_cap())

      seats =
        for name <- ~w(Mara Jacob Ada Ida Ola Ora) do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          seat
        end

      Enum.each(seats, &(:ok = Rooms.give(slug, &1.id, "setting #{&1.name}")))
      await_phase(slug, :bridging)
      Enum.each(seats, &(:ok = Rooms.commit_bridge(slug, &1.id, "cairn")))

      # Six Bridges, one Verdict. The cap is about what a phone can show and
      # what one reading can hold, not about the bill (ADR-0010).
      view = await_reveal(slug)

      assert length(view.reveal.bridges) == 6
      assert view.reveal.closeness == 100
    end

    test "a Room too big for the Assayer to grade cannot be created" do
      assert {:error, :bad_player_count} =
               Rooms.create(MeaningGame.Steward.seat_cap() + 1, device_token())
    end

    test "a third player is turned away from a Room built for two" do
      slug = open_room(seat_limit: 2)

      {:ok, _} = Rooms.join(slug, "Mara", device_token())
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

      assert {:ok, seat} = Rooms.join(slug, "  Mara \n", device_token())
      assert seat.name == "Mara"
    end
  end

  describe "rejoining" do
    setup do
      slug = open_room()
      token = device_token()
      {:ok, seat} = Rooms.join(slug, "Mara", token)

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
      assert {:ok, seat} = Rooms.join(ctx.slug, "Mara", ctx.token)
      assert seat.id == ctx.seat.id
      assert length(Rooms.snapshot(ctx.slug, nil).seats) == 1
    end

    test "a browser that forgot its token gets its Seat back by name", ctx do
      new_token = device_token()

      assert {:ok, seat} = Rooms.join(ctx.slug, "mara", new_token)
      assert seat.id == ctx.seat.id
      assert length(Rooms.snapshot(ctx.slug, nil).seats) == 1
      assert {:ok, ^seat} = Rooms.rejoin(ctx.slug, new_token)
    end

    test "claiming a Seat by name does not evict the browser already holding it", ctx do
      second_browser = device_token()
      {:ok, _} = Rooms.join(ctx.slug, "Mara", second_browser)

      # The Pixel that was here first is still here, still Mara, still
      # without typing anything.
      assert Rooms.rejoin(ctx.slug, ctx.token) == {:ok, ctx.seat}
      assert Rooms.rejoin(ctx.slug, second_browser) == {:ok, ctx.seat}
      assert length(Rooms.snapshot(ctx.slug, nil).seats) == 1
    end

    test "a full Room still lets its own players back in", ctx do
      {:ok, _} = Rooms.join(ctx.slug, "Jacob", device_token())
      assert Rooms.snapshot(ctx.slug, nil).open_seats == 0

      forgetful = device_token()
      assert {:ok, seat} = Rooms.join(ctx.slug, "Mara", forgetful)
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
      {:ok, mara} = Rooms.join(slug, "Mara", token)
      {:ok, _} = Rooms.join(slug, "Jacob", device_token())
      before = Rooms.snapshot(slug, mara.id)

      # The phone locks. Its view process — the Room's only client — goes away,
      # and the Room is told nothing, because there is nothing it needs to do.
      {client, ref} = spawn_monitor(fn -> Rooms.snapshot(slug, mara.id) end)
      assert_receive {:DOWN, ^ref, :process, ^client, :normal}

      # It wakes and asks for everything rather than for what it missed.
      assert Process.alive?(GenServer.whereis(Server.via(slug)))
      assert Rooms.rejoin(slug, token) == {:ok, mara}
      assert Rooms.snapshot(slug, mara.id) == before
    end

    test "the stage and the phones are told the same roster" do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      stage = Rooms.snapshot(slug, nil)

      assert Enum.map(stage.seats, & &1.name) ==
               Enum.map(Rooms.snapshot(slug, mara.id).seats, & &1.name)

      assert Enum.map(stage.seats, & &1.name) ==
               Enum.map(Rooms.snapshot(slug, jacob.id).seats, & &1.name)

      assert stage.you == nil
      assert Rooms.snapshot(slug, jacob.id).you.name == "Jacob"
    end
  end

  describe "playing a Page" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)
      :ok = Rooms.subscribe(slug)

      %{slug: slug, mara: mara, jacob: jacob}
    end

    test "the Bookends are up for both phones and the stage", ctx do
      for viewer <- [ctx.mara.id, ctx.jacob.id, nil] do
        view = Rooms.snapshot(ctx.slug, viewer)

        assert view.phase == :bridging
        assert [_lantern, _harbour] = view.bookends
      end
    end

    test "the last Bridge in fires the Assayer and the reveal lands", ctx do
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      assert Rooms.snapshot(ctx.slug, nil).phase == :bridging

      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")

      assert_receive :room_changed
      view = await_reveal(ctx.slug)

      assert view.reveal.closeness == 80
      assert view.reveal.band == :almost
      refute view.reveal.melded?
      assert Enum.map(view.reveal.bridges, & &1.bridge) == ["cairn", "cairo"]
      refute Map.has_key?(view.reveal, :reasoning)
    end

    test "the reveal is held for the beat rather than shown the moment it is graded", ctx do
      beat(200)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "beacon")

      # Long enough for the fake Assayer to have answered several times over,
      # and well short of the beat the players were promised.
      Process.sleep(50)
      assert Rooms.snapshot(ctx.slug, nil).phase == :assaying

      assert await_reveal(ctx.slug).reveal.closeness == 0
    end

    test "a Bridge nobody else can see until they have written their own", ctx do
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")

      jacob = Rooms.snapshot(ctx.slug, ctx.jacob.id)

      assert jacob.your_bridge == nil
      refute inspect(jacob) =~ "cairn"
      assert Enum.map(jacob.seats, & &1.committed?) == [true, false]
      assert Rooms.snapshot(ctx.slug, ctx.mara.id).your_bridge == "cairn"
    end

    test "a committed Bridge is final", ctx do
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")

      assert {:error, :already_committed} =
               Rooms.commit_bridge(ctx.slug, ctx.mara.id, "beacon")

      assert {:error, :bridge_required} = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "  ")
    end

    test "an accidental rule break does not cost an attempt or commit", ctx do
      assert {:error, {:illegal_bridge, "\"lanterns\" shares a root with \"lantern\"."}} =
               Rooms.commit_bridge(ctx.slug, ctx.mara.id, "lanterns")

      assert {:error,
              {:illegal_bridge,
               "Letters, digits, spaces, hyphens and apostrophes only (\"beacon!\")."}} =
               Rooms.commit_bridge(ctx.slug, ctx.mara.id, "beacon!")

      assert {:error, {:illegal_bridge, "Too long to fit on a card."}} =
               Rooms.commit_bridge(ctx.slug, ctx.mara.id, String.duplicate("a", 41))

      # Mara's seat is still uncommitted and attempt is still 1
      snapshot = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert snapshot.phase == :bridging
      assert snapshot.your_bridge == nil
      assert snapshot.attempt.number == 1

      # A legal bridge (including phrases) succeeds
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "Viking beaches")
    end

    test "an Assayer that falls over is a Page that still reveals", ctx do
      steward(mode: :raise)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")

      view = await_reveal(ctx.slug)

      assert view.reveal.closeness == nil
      refute view.reveal.graded?
      assert Process.alive?(GenServer.whereis(Server.via(ctx.slug)))
    end

    test "an Assayer with no verdict hands the call to the players", ctx do
      steward(mode: :unavailable)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")

      view = await_reveal(ctx.slug)

      assert view.reveal.closeness == nil
      assert view.reveal.melded? == false
      refute view.reveal.graded?
      assert Enum.map(view.reveal.bridges, & &1.bridge) == ["cairn", "cairo"]
    end

    test "a phone that slept through the whole Page snapshots straight into the reveal", ctx do
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      mara = Rooms.snapshot(ctx.slug, ctx.mara.id)

      # They melded, so the Page she woke into is a Page that has ended.
      assert mara.phase == :closed
      assert mara.reveal == Rooms.snapshot(ctx.slug, nil).reveal
    end

    test "a slow Assayer does not block the Room", ctx do
      steward(delay_ms: 100)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")

      # The Room answers while the verdict is still out.
      assert Rooms.snapshot(ctx.slug, nil).phase == :assaying
      assert await_reveal(ctx.slug).reveal.closeness == 80
    end

    test "an Assayer that answers is never called slow, however long the beat runs", ctx do
      # A beat long enough that the whole test happens inside it, and a first
      # rung the Assayer would be standing on by now if answering did not stand
      # the ladder down.
      beat(2_000)
      escalation(slow: 20)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")

      Process.sleep(100)
      view = Rooms.snapshot(ctx.slug, nil)

      assert view.phase == :assaying
      assert view.assayer_step == nil
    end
  end

  describe "four phones at a table" do
    setup do
      slug = open_room(seat_limit: 4)

      seats =
        for name <- ~w(Mara Jacob Ada Ida) do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          seat
        end

      for seat <- seats, do: :ok = Rooms.give(slug, seat.id, "setting #{seat.name}")
      await_phase(slug, :bridging)

      %{slug: slug, seats: seats}
    end

    test "the table fills, and the Page is up on all four phones", ctx do
      for seat <- ctx.seats do
        view = Rooms.snapshot(ctx.slug, seat.id)

        assert view.phase == :bridging
        assert view.open_seats == 0
        assert Enum.map(view.seats, & &1.name) == ["Mara", "Jacob", "Ada", "Ida"]
      end
    end

    test "the last of four Bridges is one reveal, after the beat", ctx do
      beat(120)

      for {seat, bridge} <- Enum.zip(ctx.seats, ~w(cairn cairo beacon signal)) do
        assert :ok = Rooms.commit_bridge(ctx.slug, seat.id, bridge)
      end

      # The theatre still runs at four: the grade is in long before the reveal.
      assert Rooms.snapshot(ctx.slug, nil).phase == :assaying

      view = await_reveal(ctx.slug)

      assert Enum.map(view.reveal.bridges, & &1.bridge) == ~w(cairn cairo beacon signal)
      assert is_integer(view.reveal.closeness)
      assert view.reveal.quip != nil
      assert length(view.reveal.furthest) == 2
      assert view.next_bookends == Enum.map(view.reveal.furthest, & &1.bridge)
    end

    test "a phone that slept through it snapshots back into the same reveal", ctx do
      for {seat, bridge} <- Enum.zip(ctx.seats, ~w(cairn cairo beacon signal)) do
        :ok = Rooms.commit_bridge(ctx.slug, seat.id, bridge)
      end

      await_reveal(ctx.slug)
      ada = Enum.at(ctx.seats, 2)

      assert Rooms.snapshot(ctx.slug, ada.id).reveal == Rooms.snapshot(ctx.slug, nil).reveal
      assert Rooms.snapshot(ctx.slug, ada.id).you.name == "Ada"
    end

    test "one slow Verdict escalates once, and the whole table is told the same thing", ctx do
      escalation(slow: 50, unavailable: 400)
      steward(delay_ms: 5_000)

      for {seat, bridge} <- Enum.zip(ctx.seats, ~w(cairn cairo beacon signal)) do
        :ok = Rooms.commit_bridge(ctx.slug, seat.id, bridge)
      end

      assert eventually(fn -> Rooms.snapshot(ctx.slug, nil).assayer_step == :slow end)

      view = await_reveal(ctx.slug)

      # One Verdict given up on, not six: the reveal has no number at all, and
      # nothing is still narrating the wait.
      refute view.reveal.graded?
      assert view.reveal.closeness == nil
      assert view.assayer_step == nil

      for seat <- ctx.seats do
        assert Rooms.snapshot(ctx.slug, seat.id).reveal.closeness == nil
      end
    end
  end

  describe "an Assayer that takes too long" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)

      # Rungs far enough apart that a test can catch the Room standing on each
      # one, and an Assayer slower than all of them — but not so much slower that
      # the test cannot wait for it to answer anyway, because one of these tests
      # is about what happens when it finally does.
      escalation(slow: 50, unavailable: 700)
      steward(delay_ms: 1_000)

      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairo")

      %{slug: slug, mara: mara, jacob: jacob}
    end

    test "says it is still reading", ctx do
      assert eventually(fn -> Rooms.snapshot(ctx.slug, nil).assayer_step == :slow end)
    end

    test "gives up at the last rung and hands the ruling to the players", ctx do
      view = await_reveal(ctx.slug)

      assert view.reveal.closeness == nil
      assert view.reveal.melded? == false
      refute view.reveal.graded?
      assert Enum.map(view.reveal.bridges, & &1.bridge) == ["cairn", "cairo"]

      # The wait is over, so nothing on any screen is still narrating it.
      assert view.assayer_step == nil
    end

    test "a verdict that turns up after the game gave up does not change it", ctx do
      assert await_reveal(ctx.slug).reveal.closeness == nil

      # The Assayer does answer, a full second after being asked and long after
      # the game stopped waiting at 700 ms. The pair is already graded — as
      # ungraded — and a pair is graded once, so the number on the screen the
      # couple are looking at does not move under them.
      Process.sleep(1_100)

      assert Rooms.snapshot(ctx.slug, nil).reveal.closeness == nil
      assert Process.alive?(GenServer.whereis(Server.via(ctx.slug)))
    end

    test "every screen is told the same thing about the wait", ctx do
      eventually(fn -> Rooms.snapshot(ctx.slug, nil).assayer_step == :slow end)

      assert Rooms.snapshot(ctx.slug, ctx.mara.id).assayer_step ==
               Rooms.snapshot(ctx.slug, nil).assayer_step
    end
  end

  describe "the attempt ladder" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)

      %{slug: slug, mara: mara, jacob: jacob}
    end

    # One attempt, missed or melded depending on the two words handed in.
    defp play(ctx, mara_bridge, jacob_bridge) do
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, mara_bridge)
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, jacob_bridge)

      await_reveal(ctx.slug)
    end

    test "a miss carries both Bridges forward and the next attempt is up", ctx do
      view = play(ctx, "cairn", "beacon")

      assert view.phase == :reveal
      assert view.next_bookends == ["cairn", "beacon"]

      assert :ok = Rooms.next_attempt(ctx.slug, ctx.mara.id)

      for viewer <- [ctx.mara.id, ctx.jacob.id, nil] do
        view = Rooms.snapshot(ctx.slug, viewer)

        assert view.phase == :bridging
        assert view.bookends == ["cairn", "beacon"]
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
      view = play(ctx, "cairn", "cairn")

      assert view.phase == :closed
      assert view.closed == %{because: :meld, attempt: 1}
      assert view.reveal.melded?
      assert {:error, :page_closed} = Rooms.next_attempt(ctx.slug, ctx.mara.id)
    end

    test "the last attempt closes the Page unmelded", ctx do
      attempt_cap(2)

      play(ctx, "cairn", "beacon")
      :ok = Rooms.next_attempt(ctx.slug, ctx.jacob.id)
      view = play(ctx, "wharf", "gantry")

      assert view.phase == :closed
      assert view.closed == %{because: :attempts_spent, attempt: 2}
      refute view.reveal.melded?
      assert Enum.map(view.played, & &1.bookends) == [["lantern", "harbour"]]
    end

    test "one more? is a fresh Page with the same Seats", ctx do
      play(ctx, "cairn", "cairn")

      assert :ok = Rooms.next_page(ctx.slug, ctx.mara.id)

      for viewer <- [ctx.mara.id, ctx.jacob.id, nil] do
        view = Rooms.snapshot(ctx.slug, viewer)

        assert view.phase == :giving
        assert view.reveal == nil
        assert view.played == []
        assert Enum.map(view.seats, & &1.name) == ["Mara", "Jacob"]
      end

      # Prefill remembers each seat's last Give
      assert Rooms.snapshot(ctx.slug, ctx.mara.id).your_last_give == "setting one"
      assert Rooms.snapshot(ctx.slug, ctx.jacob.id).your_last_give == "setting two"

      # New gives land, Author writes, and bridging begins again
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)

      view = Rooms.snapshot(ctx.slug, nil)
      assert view.phase == :bridging
      assert view.attempt.number == 1
    end

    test "one more? is refused while the Page is still being played", ctx do
      assert {:error, :page_open} = Rooms.next_page(ctx.slug, ctx.mara.id)

      play(ctx, "cairn", "beacon")

      assert {:error, :page_open} = Rooms.next_page(ctx.slug, ctx.mara.id)
    end
  end

  describe "supervision" do
    test "a crashed Room comes back with its Seats" do
      slug = open_room()
      token = device_token()
      {:ok, mara} = Rooms.join(slug, "Mara", token)
      before = Rooms.snapshot(slug, mara.id)

      pid = GenServer.whereis(Server.via(slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      assert once_restarted(fn -> Rooms.snapshot(slug, mara.id) end) == before
      assert Rooms.rejoin(slug, token) == {:ok, mara}
    end

    test "a crashed Room comes back with its Seats, and the Page in progress is gone" do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)
      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairo")
      await_reveal(slug)

      pid = GenServer.whereis(Server.via(slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      # Bridges and verdicts live in the process and nowhere else, so this is
      # what a crash costs until the Chronicle writes Page events down. Both
      # Seats are still here; the Page they were playing is not.
      view = once_restarted(fn -> Rooms.snapshot(slug, mara.id) end)

      assert view.phase == :giving
      assert view.reveal == nil
      assert view.your_bridge == nil
      assert Enum.map(view.seats, & &1.name) == ["Mara", "Jacob"]
    end
  end

  describe "creating a Room" do
    test "a Room is created with a Code of its own and opens under it" do
      assert {:ok, code} = Rooms.create(4, device_token())

      assert String.length(code) == 4
      assert Rooms.open!(code) == code
      assert Rooms.snapshot(code, nil).seat_limit == 4

      stop_room(code)
    end

    test "the Code is a real word nobody would be embarrassed to read aloud" do
      alias MeaningGame.Steward.Legality

      codes =
        for _ <- 1..10 do
          {:ok, code} = Rooms.create(2, device_token())
          stop_room(code)
          code
        end

      for code <- codes do
        assert Legality.in_dictionary?(code)
        refute Legality.profane?(code)
      end

      # Two Rooms never share a Code, however many are opened in one evening.
      assert length(Enum.uniq(codes)) == length(codes)
    end

    test "a table smaller than two, or bigger than a phone can show, is not a Room" do
      assert {:error, :bad_player_count} = Rooms.create(1, device_token())
      assert {:error, :bad_player_count} = Rooms.create(0, device_token())
      assert {:error, :bad_player_count} = Rooms.create("four", device_token())
    end

    test "a phone with history asks the Scribe, and the configured word becomes the Code" do
      token = device_token()
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", token)
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)
      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairns")
      await_reveal(slug)

      steward(name_word: "fork")

      assert {:ok, "fork"} = Rooms.create(2, token)
      stop_room("fork")
      stop_room(slug)
    end

    test "a phone with no history makes no model call and draws a random word" do
      token = device_token()
      # Even if the Scribe would raise, a phone with no history makes no call
      steward(name_mode: :raise)

      assert {:ok, code} = Rooms.create(2, token)
      assert String.length(code) == 4
      stop_room(code)
    end

    test "a Scribe that raises or answers nothing valid falls back to a random word" do
      token = device_token()
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", token)
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)
      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairns")
      await_reveal(slug)

      steward(name_mode: :raise)
      assert {:ok, code1} = Rooms.create(2, token)
      assert String.length(code1) == 4
      stop_room(code1)

      steward(name_mode: :unavailable)
      assert {:ok, code2} = Rooms.create(2, token)
      assert String.length(code2) == 4
      stop_room(code2)

      stop_room(slug)
    end

    test "a Scribe that is slow past its deadline falls back to a random word" do
      token = device_token()
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", token)
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)
      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairns")
      await_reveal(slug)

      # 1500ms delay exceeds the test deadline of 1000ms
      steward(name_delay_ms: 1_500)
      assert {:ok, code} = Rooms.create(2, token)
      assert String.length(code) == 4
      stop_room(code)
      stop_room(slug)
    end
  end

  describe "opening a Room" do
    test "a Code no Room could have is no Room, not a new one" do
      assert {:error, :bad_code} = Rooms.ensure_started("Not A Code")
      assert {:error, :bad_code} = Rooms.ensure_started("")

      assert_raise MeaningGame.Rooms.NoSuchRoomError, fn -> Rooms.open!("Not A Code") end
    end

    test "a Code nobody created is a 404, and visiting it creates nothing" do
      code = "cane-#{System.unique_integer([:positive])}"

      assert {:error, :no_such_room} = Rooms.ensure_started(code)
      assert_raise MeaningGame.Rooms.NoSuchRoomError, fn -> Rooms.open!(code) end

      refute MeaningGame.Repo.get_by(MeaningGame.Rooms.Room, slug: code)
    end

    test "a Code opens the same Room in any case" do
      slug = open_room()

      assert Rooms.open!(String.upcase(slug)) == slug
      assert {:ok, _} = Rooms.join(String.upcase(slug), "Mara", device_token())
      assert length(Rooms.snapshot(slug, nil).seats) == 1
    end

    test "opening the same Room twice is the same Room" do
      slug = open_room()

      assert Rooms.open!(slug) == slug
      assert {:ok, _} = Rooms.join(slug, "Mara", device_token())
      assert Rooms.open!(slug) == slug
      assert length(Rooms.snapshot(slug, nil).seats) == 1
    end
  end

  describe "the Rooms a phone holds a Seat in" do
    test "every Room this browser sat in, newest first, with its Seat" do
      phone = device_token()
      first = open_room()
      second = open_room()

      {:ok, _} = Rooms.join(first, "Mara", phone)
      {:ok, seat} = Rooms.join(second, "Mel", phone)

      assert [%{room: newest, seat: newest_seat}, %{room: oldest}] = Rooms.for_device(phone)

      assert newest.slug == second
      assert newest_seat.id == seat.id
      assert newest_seat.name == "Mel"
      assert oldest.slug == first
    end

    test "a browser that has sat nowhere is offered nothing" do
      assert Rooms.for_device(device_token()) == []
    end

    test "a Seat another phone holds is not this phone's way back in" do
      slug = open_room()
      {:ok, _} = Rooms.join(slug, "Mara", device_token())

      assert Rooms.for_device(device_token()) == []
    end
  end

  describe "subscriptions" do
    test "a subscriber hears about a new Seat" do
      slug = open_room()
      :ok = Rooms.subscribe(slug)

      {:ok, _} = Rooms.join(slug, "Mara", device_token())

      assert_receive :room_changed
    end
  end

  describe "overruling a grade through the Room" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)

      # Fake Assayer: "cairn" and "beacon" share no prefix -> closeness 0
      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "beacon")
      await_reveal(slug)

      %{slug: slug, mara: mara, jacob: jacob}
    end

    test "proposing an overrule broadcasts and shows in snapshot", ctx do
      :ok = Rooms.subscribe(ctx.slug)
      :ok = Rooms.propose_overrule(ctx.slug, ctx.mara.id)

      assert_receive :room_changed
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.overrule.pending?
      assert view.overrule.proposer_id == ctx.mara.id
      assert view.reveal.closeness == 0
    end

    test "agreeing to the overrule updates the grade and records in Chronicle", ctx do
      :ok = Rooms.propose_overrule(ctx.slug, ctx.mara.id)
      :ok = Rooms.agree_overrule(ctx.slug, ctx.jacob.id)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.reveal.closeness == 90
      assert view.reveal.melded?
      assert view.phase == :closed
      assert view.overrule == nil

      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: ctx.slug)
      assert [overrule] = MeaningGame.Chronicle.overrules(room.id)
      assert overrule.proposer_seat_id == ctx.mara.id
      assert overrule.machine_closeness == 0
      assert overrule.couple_closeness == 90
    end

    test "declining an overrule leaves the grade untouched", ctx do
      :ok = Rooms.propose_overrule(ctx.slug, ctx.mara.id)
      :ok = Rooms.decline_overrule(ctx.slug, ctx.jacob.id)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.reveal.closeness == 0
      refute view.reveal.melded?
      assert view.overrule == nil
    end

    test "overruling on the final attempt records the overrule without duplicate Chronicle pages" do
      attempt_cap(1)
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)

      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "beacon")
      await_reveal(slug)

      # Attempt 1 was the final attempt (cap is 1), so page is closed
      view = Rooms.snapshot(slug, mara.id)
      assert view.phase == :closed

      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: slug)
      initial_page_count = MeaningGame.Repo.aggregate(MeaningGame.Chronicle.Page, :count)

      # Propose and agree to overrule
      :ok = Rooms.propose_overrule(slug, mara.id)
      :ok = Rooms.agree_overrule(slug, jacob.id)

      view = Rooms.snapshot(slug, mara.id)
      assert view.reveal.closeness == 90
      assert view.reveal.melded?
      assert view.phase == :closed

      # No duplicate page was written to the Chronicle
      assert MeaningGame.Repo.aggregate(MeaningGame.Chronicle.Page, :count) == initial_page_count
      assert [overrule] = MeaningGame.Chronicle.overrules(room.id)
      assert overrule.machine_closeness == 0
      assert overrule.couple_closeness == 90
    end
  end

  describe "the fairness tap (ticket 11)" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)

      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairn")
      await_reveal(slug)

      %{slug: slug, mara: mara, jacob: jacob}
    end

    test "a player taps fairness at the reveal, persisting the row and updating the snapshot",
         ctx do
      assert :ok = Rooms.record_fairness_tap(ctx.slug, ctx.mara.id, "fair")

      # Mara's snapshot shows her tap
      view_m = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_m.your_tap == "fair"

      # Jacob's snapshot does not have a tap yet
      view_j = Rooms.snapshot(ctx.slug, ctx.jacob.id)
      assert view_j.your_tap == nil

      # Jacob taps too_harsh
      assert :ok = Rooms.record_fairness_tap(ctx.slug, ctx.jacob.id, "too_harsh")
      view_j2 = Rooms.snapshot(ctx.slug, ctx.jacob.id)
      assert view_j2.your_tap == "too_harsh"

      # Both persisted into Chronicle
      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: ctx.slug)
      taps = MeaningGame.Chronicle.fairness_taps(room.id)
      assert length(taps) == 2
      assert Enum.find(taps, &(&1.seat_id == ctx.mara.id)).label == "fair"
      assert Enum.find(taps, &(&1.seat_id == ctx.jacob.id)).label == "too_harsh"
    end

    test "tapping does not prevent or delay starting the next page", ctx do
      assert :ok = Rooms.record_fairness_tap(ctx.slug, ctx.mara.id, "fair")
      # Next attempt / page proceeds without impediment
      assert :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.phase == :giving
      assert view.your_tap == nil
    end
  end

  describe "giving settings at the table" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      steward = Application.fetch_env!(:meaning_game, :steward)
      on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

      %{slug: slug, mara: mara, jacob: jacob, steward: steward}
    end

    test "a full Room boots with no Page and is in giving phase", ctx do
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.phase == :giving
      assert view.bookends == nil
      assert view.gives_in == 0
      assert view.your_give == nil
    end

    test "a Give requires a seat and non-blank input", ctx do
      assert {:error, :no_such_seat} = Rooms.give(ctx.slug, "not-a-seat", "my setting")
      assert {:error, :give_required} = Rooms.give(ctx.slug, ctx.mara.id, "")
      assert {:error, :give_required} = Rooms.give(ctx.slug, ctx.mara.id, "   ")
    end

    test "submitting a Give shows only to the giver and updates count for others", ctx do
      assert :ok = Rooms.give(ctx.slug, ctx.mara.id, "candlelit cathedral")

      mara_view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert mara_view.your_give == "candlelit cathedral"
      assert mara_view.gives_in == 1

      jacob_view = Rooms.snapshot(ctx.slug, ctx.jacob.id)
      assert jacob_view.your_give == nil
      assert jacob_view.gives_in == 1
      refute inspect(jacob_view) =~ "candlelit cathedral"

      stage_view = Rooms.snapshot(ctx.slug, nil)
      assert stage_view.gives_in == 1
      refute inspect(stage_view) =~ "candlelit cathedral"
    end

    test "the last Give triggers the Author and transitions to bridging", ctx do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "candlelit cathedral")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "cyberpunk nightclub")

      view = await_phase(ctx.slug, :bridging)
      assert view.phase == :bridging
      assert [_b1, _b2] = view.bookends
    end

    test "an Author failure allows retry or entering new settings", ctx do
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_mode: :unavailable)
        )
      )

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")

      failure_view =
        eventually(
          fn ->
            v = Rooms.snapshot(ctx.slug, ctx.mara.id)
            v.author_failure && v
          end,
          "author failure never arrived"
        )

      assert failure_view.author_failure != nil

      # Retry author
      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_mode: :ok)
        )
      )

      assert :ok = Rooms.retry_author(ctx.slug, ctx.mara.id)
      assert await_phase(ctx.slug, :bridging).phase == :bridging
    end

    test "resetting gives allows players to enter fresh settings", ctx do
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_mode: :unavailable)
        )
      )

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")

      eventually(fn -> Rooms.snapshot(ctx.slug, ctx.mara.id).author_failure end)

      assert :ok = Rooms.reset_gives(ctx.slug, ctx.mara.id)
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.phase == :giving
      assert view.gives_in == 0
      assert view.author_failure == nil
    end

    test "a slow Fake Author reaches still-writing and then failure and recovers on retry", ctx do
      author_escalation(still_writing: 25, deadline: 80)

      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_delay_ms: 200, author_mode: :ok)
        )
      )

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")

      # Reaches still_writing at first rung
      still_view =
        eventually(
          fn ->
            v = Rooms.snapshot(ctx.slug, ctx.mara.id)
            v.author_step == :still_writing && v
          end,
          "author never reached still_writing"
        )

      assert still_view.phase == :writing
      assert still_view.author_failure == nil

      # Reaches failure at deadline
      failed_view =
        eventually(
          fn ->
            v = Rooms.snapshot(ctx.slug, ctx.mara.id)
            v.author_failure && v
          end,
          "author failure never arrived"
        )

      assert failed_view.phase == :writing
      assert failed_view.author_failure == "timed out"

      # Recovers on retry with fast author
      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_delay_ms: 0, author_mode: :ok)
        )
      )

      assert :ok = Rooms.retry_author(ctx.slug, ctx.mara.id)
      assert await_phase(ctx.slug, :bridging).phase == :bridging
    end

    test "an Author task that raises or exits applies author_failed and stays in writing", ctx do
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_mode: :raise)
        )
      )

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")

      failed_view =
        eventually(
          fn ->
            v = Rooms.snapshot(ctx.slug, ctx.mara.id)
            v.author_failure && v
          end,
          "author failure never arrived"
        )

      assert failed_view.phase == :writing
      assert failed_view.author_failure =~ "this Author is having a moment"
    end

    test "stale or unmatched author task completion is safely ignored", ctx do
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_mode: :unavailable)
        )
      )

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")

      eventually(
        fn ->
          v = Rooms.snapshot(ctx.slug, ctx.mara.id)
          v.author_failure && v
        end,
        "author failure never arrived"
      )

      pid = GenServer.whereis(MeaningGame.Rooms.Server.via(ctx.slug))

      # A late task completion with a stale ref arrives
      send(
        pid,
        {:author_completed, make_ref(), {:ok, %{bookends: ["late1", "late2"], meta: %{}}}}
      )

      # Room must remain in writing with failure reason intact, not advancing to bridging
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.phase == :writing
      assert view.author_failure == "unavailable"

      # Similarly, an unmatched error completion changes nothing
      send(pid, {:author_completed, make_ref(), {:error, :timeout}})

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.phase == :writing
      assert view.author_failure == "unavailable"
    end
  end

  describe "A/B experiments harness" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)

      %{slug: slug, mara: mara, jacob: jacob}
    end

    test "arm labels are blinded in the snapshot during play", ctx do
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      refute Map.has_key?(view, :arm)
      refute Map.has_key?(view, :current_arm)

      json = Jason.encode!(view)
      refute json =~ ~r/"arm"\s*:\s*"bait"/
      refute json =~ ~r/"arm"\s*:\s*"plain"/
    end

    test "unblinding is a deliberate action recorded in the Chronicle", ctx do
      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: ctx.slug)

      refute MeaningGame.Chronicle.experiment_unblinded?(room.id)

      assert :ok = Rooms.unblind_experiment(ctx.slug, ctx.jacob.id)
      assert MeaningGame.Chronicle.experiment_unblinded?(room.id)

      [unblinding] = MeaningGame.Chronicle.experiment_unblindings(room.id)
      assert unblinding.seat_id == ctx.jacob.id
      assert unblinding.experiment_id == "bait_against_plain"
    end
  end

  describe "speaker and switches" do
    setup do
      slug = open_room()
      token_a = device_token()
      token_b = device_token()
      {:ok, mara} = Rooms.join(slug, "Mara", token_a)
      {:ok, jacob} = Rooms.join(slug, "Jacob", token_b)

      %{slug: slug, token_a: token_a, token_b: token_b, mara: mara, jacob: jacob}
    end

    test "a new Room has no speaker and both switches off by default", ctx do
      room = Store.get_room(ctx.slug)
      assert is_nil(room.speaker)
      assert room.voice == false
      assert room.house_loop_only == false
    end

    test "claiming the speaker updates the Room and broadcasts", ctx do
      Rooms.subscribe(ctx.slug)

      assert :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      assert_receive :room_changed

      room = Store.get_room(ctx.slug)
      assert room.speaker == ctx.token_a

      # A claim from the current speaker is a no-op and does not re-broadcast
      assert :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      refute_receive :room_changed
    end

    test "claiming the speaker from another device takes it from whoever had it", ctx do
      assert :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      assert Store.get_room(ctx.slug).speaker == ctx.token_a

      Rooms.subscribe(ctx.slug)
      assert :ok = Rooms.claim_speaker(ctx.slug, ctx.token_b)
      assert_receive :room_changed

      assert Store.get_room(ctx.slug).speaker == ctx.token_b
    end

    test "releasing the speaker silences whoever had it, and a release from another device is a no-op",
         ctx do
      assert :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)

      # Releasing with a different token is a no-op
      Rooms.subscribe(ctx.slug)
      assert :ok = Rooms.release_speaker(ctx.slug, ctx.token_b)
      refute_receive :room_changed
      assert Store.get_room(ctx.slug).speaker == ctx.token_a

      # Releasing with the holding token clears the speaker and broadcasts
      assert :ok = Rooms.release_speaker(ctx.slug, ctx.token_a)
      assert_receive :room_changed
      assert is_nil(Store.get_room(ctx.slug).speaker)
    end

    test "voice and house-loop-only switches update the Room and broadcast", ctx do
      Rooms.subscribe(ctx.slug)

      assert :ok = Rooms.set_voice(ctx.slug, true)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).voice == true

      assert :ok = Rooms.set_house_loop_only(ctx.slug, true)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).house_loop_only == true

      assert :ok = Rooms.set_voice(ctx.slug, false)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).voice == false
    end

    test "speaker, voice and house-loop-only survive a Room process restart", ctx do
      assert :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      assert :ok = Rooms.set_voice(ctx.slug, true)
      assert :ok = Rooms.set_house_loop_only(ctx.slug, true)

      pid = GenServer.whereis(Server.via(ctx.slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      room =
        once_restarted(fn ->
          {:ok, _slug, _pid} = Rooms.ensure_started(ctx.slug)
          Store.get_room(ctx.slug)
        end)

      assert room.speaker == ctx.token_a
      assert room.voice == true
      assert room.house_loop_only == true
    end

    test "snapshot answers speaker?, speaker_claimed? and switches without leaking device tokens",
         ctx do
      view_a = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      view_b = Rooms.snapshot(ctx.slug, ctx.jacob.id, ctx.token_b)
      view_stage = Rooms.snapshot(ctx.slug, nil, device_token())

      for view <- [view_a, view_b, view_stage] do
        assert view.speaker? == false
        assert view.speaker_claimed? == false
        assert view.voice == false
        assert view.house_loop_only == false
        refute Map.has_key?(view, :speaker)
        refute Map.has_key?(view, :device_token)
      end

      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)
      :ok = Rooms.set_house_loop_only(ctx.slug, true)

      view_a = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      view_b = Rooms.snapshot(ctx.slug, ctx.jacob.id, ctx.token_b)
      view_stage = Rooms.snapshot(ctx.slug, nil, device_token())

      assert view_a.speaker? == true
      assert view_a.speaker_claimed? == true
      assert view_a.voice == true
      assert view_a.house_loop_only == true

      assert view_b.speaker? == false
      assert view_b.speaker_claimed? == true
      assert view_b.voice == true
      assert view_b.house_loop_only == true

      assert view_stage.speaker? == false
      assert view_stage.speaker_claimed? == true

      json = Jason.encode!(view_a)
      refute json =~ ctx.token_a
    end
  end

  describe "foley voice (the Assayer speaks)" do
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

    test "when voice is on and a speaker exists, broadcasts voice_ready and holds audio for attempt",
         ctx do
      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      assert_receive {:voice_ready, 1}, 2000
      assert {:ok, audio, :mp3} = Rooms.voice_audio(ctx.slug, 1)
      assert is_binary(audio) and byte_size(audio) > 0
      assert {:error, :not_found} = Rooms.voice_audio(ctx.slug, 2)
    end

    test "voice is not spoken when voice switch is off or no speaker exists", ctx do
      Rooms.subscribe(ctx.slug)

      # Voice switch off, speaker exists
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      assert Rooms.snapshot(ctx.slug, nil).voice == false

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      refute_receive {:voice_ready, _}, 100
      assert {:error, :not_found} = Rooms.voice_audio(ctx.slug, 1)
    end

    test "advancing to next attempt clears past attempt's audio and serves only new attempt's audio",
         ctx do
      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)

      # Attempt 1: miss
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "beacon")
      await_reveal(ctx.slug)

      assert_receive {:voice_ready, 1}, 2000
      assert {:ok, _audio, :mp3} = Rooms.voice_audio(ctx.slug, 1)

      # Advance to attempt 2
      :ok = Rooms.next_attempt(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :bridging)

      # Past attempt's audio is no longer served
      assert {:error, :not_found} = Rooms.voice_audio(ctx.slug, 1)
      assert {:error, :not_found} = Rooms.voice_audio(ctx.slug, 2)

      # Attempt 2: meld
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "valley")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "valley")
      await_reveal(ctx.slug)

      assert_receive {:voice_ready, 2}, 2000
      assert {:ok, _audio, :mp3} = Rooms.voice_audio(ctx.slug, 2)
      assert {:error, :not_found} = Rooms.voice_audio(ctx.slug, 1)
    end

    test "failing voice synthesis is dropped and logged; reveal and rules untouched", ctx do
      steward_env = Application.get_env(:meaning_game, :steward, [])
      fake_env = Keyword.get(steward_env, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(steward_env, :fake, Keyword.put(fake_env, :voice_mode, :unavailable))
      )

      on_exit(fn ->
        Application.put_env(:meaning_game, :steward, steward_env)
      end)

      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      view = await_reveal(ctx.slug)

      assert view.phase in [:reveal, :closed]
      assert view.reveal.quip != nil

      refute_receive {:voice_ready, _}, 100
      assert {:error, :not_found} = Rooms.voice_audio(ctx.slug, 1)
    end

    test "late voice arriving after next attempt started is dropped and logged", ctx do
      steward_env = Application.get_env(:meaning_game, :steward, [])
      fake_env = Keyword.get(steward_env, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(steward_env, :fake, Keyword.put(fake_env, :voice_delay_ms, 200))
      )

      on_exit(fn ->
        Application.put_env(:meaning_game, :steward, steward_env)
      end)

      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)

      # Attempt 1: miss
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "beacon")
      await_reveal(ctx.slug)

      # Quickly advance before voice delay finishes
      :ok = Rooms.next_attempt(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :bridging)

      # Wait out the delay
      Process.sleep(250)

      refute_receive {:voice_ready, 1}
      assert {:error, :not_found} = Rooms.voice_audio(ctx.slug, 1)
    end

    test "voice_meta is recorded on the Verdict in Chronicle when Page closes", ctx do
      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      assert_receive {:voice_ready, 1}, 2000

      room = Repo.get_by!(MeaningGame.Rooms.Room, slug: ctx.slug)
      pages = Chronicle.pages(room.id)
      assert length(pages) == 1
      page = hd(pages)
      assert length(page.attempts) == 1
      attempt = hd(page.attempts)
      assert length(attempt.verdicts) == 1
      verdict = hd(attempt.verdicts)

      assert is_map(verdict.voice_meta)
      assert verdict.voice_meta["provider"] != nil
      assert verdict.voice_meta["voice"] != nil
      assert verdict.voice_meta["cost"] != nil or verdict.voice_meta["cost_usd"] != nil
      assert verdict.voice_meta["latency"] != nil or verdict.voice_meta["latency_ms"] != nil
    end

    test "voice_audio and voice_meta do not leak across next_page", ctx do
      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)

      # Attempt 1: meld closes the page
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      assert_receive {:voice_ready, 1}, 2000
      assert {:ok, _audio, :mp3} = Rooms.voice_audio(ctx.slug, 1)

      # Next page starts; attempt resets to 1 but prior audio must be gone
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      assert {:error, :not_found} = Rooms.voice_audio(ctx.slug, 1)
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
