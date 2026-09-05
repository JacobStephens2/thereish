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
      :ok = Rooms.subscribe(slug)

      %{slug: slug, mara: mara, jacob: jacob}
    end

    test "the Anchors are up for both phones and the stage", ctx do
      for viewer <- [ctx.mara.id, ctx.jacob.id, nil] do
        view = Rooms.snapshot(ctx.slug, viewer)

        assert view.phase == :bridging
        assert [_lantern, _harbour] = view.anchors
      end
    end

    test "the last Bridge in fires the Assayer and the reveal lands", ctx do
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      assert Rooms.snapshot(ctx.slug, nil).phase == :bridging

      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")

      assert_receive :room_changed
      view = await_reveal(ctx.slug)

      assert view.reveal.closeness == 80
      assert view.reveal.band == :meld
      assert view.reveal.melded?
      assert Enum.map(view.reveal.bridges, & &1.bridge) == ["cairn", "cairo"]
      assert view.reveal.reasoning =~ "cairn"
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

      assert {:error, {:illegal_bridge, "\"xyzzyq\" is not in the dictionary."}} =
               Rooms.commit_bridge(ctx.slug, ctx.mara.id, "xyzzyq")

      assert {:error, {:illegal_bridge, "Not in this Room."}} =
               Rooms.commit_bridge(ctx.slug, ctx.mara.id, "damn")

      # Mara's seat is still uncommitted and attempt is still 1
      snapshot = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert snapshot.phase == :bridging
      assert snapshot.your_bridge == nil
      assert snapshot.attempt.number == 1

      # A legal bridge succeeds
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "beacon")
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
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")
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
      assert view.next_anchors == Enum.map(view.reveal.furthest, & &1.bridge)
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
      escalation(slow: 50, provisional: 200, unavailable: 400)
      steward(delay_ms: 5_000)

      for {seat, bridge} <- Enum.zip(ctx.seats, ~w(cairn cairo beacon signal)) do
        :ok = Rooms.commit_bridge(ctx.slug, seat.id, bridge)
      end

      assert eventually(fn -> Rooms.snapshot(ctx.slug, nil).assayer_step == :slow end)

      assert eventually(fn ->
               snap = Rooms.snapshot(ctx.slug, nil)
               snap.assayer_step == :provisional and snap.provisional_band != nil
             end)

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

      # Rungs far enough apart that a test can catch the Room standing on each
      # one, and an Assayer slower than all of them — but not so much slower that
      # the test cannot wait for it to answer anyway, because one of these tests
      # is about what happens when it finally does.
      escalation(slow: 50, provisional: 400, unavailable: 700)
      steward(delay_ms: 1_000)

      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairo")

      %{slug: slug, mara: mara, jacob: jacob}
    end

    test "says it is still reading, and then that it is still nothing", ctx do
      assert eventually(fn -> Rooms.snapshot(ctx.slug, nil).assayer_step == :slow end)

      assert eventually(fn ->
               snap = Rooms.snapshot(ctx.slug, nil)
               snap.assayer_step == :provisional and snap.provisional_band != nil
             end)
    end

    test "gives up at the last rung and hands the ruling to the players", ctx do
      view = await_reveal(ctx.slug)

      assert view.reveal.closeness == nil
      assert view.reveal.melded? == false
      refute view.reveal.graded?
      assert view.reveal.quip != nil
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
      assert view.next_anchors == ["cairn", "beacon"]

      assert :ok = Rooms.next_attempt(ctx.slug, ctx.mara.id)

      for viewer <- [ctx.mara.id, ctx.jacob.id, nil] do
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
      assert Enum.map(view.played, & &1.anchors) == [["lantern", "harbour"]]
    end

    test "one more? is a fresh Page with the same Seats", ctx do
      play(ctx, "cairn", "cairo")

      assert :ok = Rooms.next_page(ctx.slug, ctx.mara.id)

      for viewer <- [ctx.mara.id, ctx.jacob.id, nil] do
        view = Rooms.snapshot(ctx.slug, viewer)

        assert view.phase == :bridging
        assert view.attempt.number == 1
        assert view.anchors != ["lantern", "harbour"]
        assert view.reveal == nil
        assert view.played == []
        assert Enum.map(view.seats, & &1.name) == ["Mara", "Jacob"]
      end
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

    test "a crashed Room comes back at the Anchors, and the Page in progress is gone" do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
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

      assert view.phase == :bridging
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
      assert view.reveal.closeness == 100
      assert view.reveal.melded?
      assert view.phase == :closed
      assert view.overrule == nil

      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: ctx.slug)
      assert [overrule] = MeaningGame.Chronicle.overrules(room.id)
      assert overrule.proposer_seat_id == ctx.mara.id
      assert overrule.machine_closeness == 0
      assert overrule.couple_closeness == 100
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
      assert view.reveal.closeness == 100
      assert view.reveal.melded?
      assert view.phase == :closed

      # No duplicate page was written to the Chronicle
      assert MeaningGame.Repo.aggregate(MeaningGame.Chronicle.Page, :count) == initial_page_count
      assert [overrule] = MeaningGame.Chronicle.overrules(room.id)
      assert overrule.machine_closeness == 0
      assert overrule.couple_closeness == 100
    end
  end

  describe "authored pool in Room lifecycle" do
    test "draws next Page from authored pool and refuses to repeat when exhausted" do
      {:ok, _page} =
        MeaningGame.Pages.insert_page(%{
          id: "P-POOL-1",
          chapter: "room pool chapter",
          theme: "room pool chapter",
          give: nil,
          anchors: ["candle", "shadow"],
          bait: "flame",
          deep_bridges: ["glow", "darkness"],
          likely_bridges: ["flame", "glow", "darkness", "wax"],
          why_these: "Candle and shadow invite flame.",
          band_scripts: %{
            "miss" => "Lost in dark.",
            "adjacent" => "Near the light.",
            "close" => "Passable. In the glow.",
            "meld" => "Two minds at the flame.",
            "deep_meld" => "Deep shadow."
          },
          meta: %{model: "fake", attempts: 1, cost_usd: 0.0}
        })

      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      # First page of room was drawn from pool
      snapshot = Rooms.snapshot(slug, mara.id)
      assert snapshot.anchors == ["candle", "shadow"]

      # Play through to meld it
      :ok = Rooms.commit_bridge(slug, mara.id, "flame")
      :ok = Rooms.commit_bridge(slug, jacob.id, "flame")
      await_reveal(slug)

      # Next page call refuses to repeat because pool is drained
      assert {:error, :pool_exhausted} = Rooms.next_page(slug, mara.id)
    end
  end

  describe "the fairness tap (ticket 11)" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairo")
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
      assert view.your_tap == nil
    end
  end

  describe "naming a setting (ticket 12)" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      # Seed one normal page in pool so room has existing pool
      {:ok, _} =
        MeaningGame.Pages.insert_page(%{
          id: "P-EXISTING-01",
          chapter: "the harbour",
          theme: "the harbour",
          give: nil,
          anchors: ["lantern", "harbour"],
          bait: "lighthouse",
          deep_bridges: ["beacon", "buoy"],
          likely_bridges: ["lighthouse", "beacon", "buoy"],
          why_these: "Harbour anchors",
          band_scripts: %{
            "miss" => "m",
            "adjacent" => "a",
            "close" => "c",
            "meld" => "meld",
            "deep_meld" => "dm"
          },
          meta: %{model: "fake-author", prompt_version: "v1", attempts: 1, cost_usd: 0.0}
        })

      steward = Application.fetch_env!(:meaning_game, :steward)
      on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

      %{slug: slug, mara: mara, jacob: jacob, steward: steward}
    end

    test "a Give requires a seat and non-blank input", ctx do
      assert {:error, :no_such_seat} = Rooms.give(ctx.slug, "not-a-seat", "my setting")
      assert {:error, :give_required} = Rooms.give(ctx.slug, ctx.mara.id, "")
      assert {:error, :give_required} = Rooms.give(ctx.slug, ctx.mara.id, "   ")
    end

    test "a Give queues a background Author run, play continues meanwhile, and arriving Pages join pool",
         ctx do
      # Configure fake author to take 15ms per page
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_delay_ms: 15, author_mode: :ok)
        )
      )

      give = "the world St. Thérèse grew up in"
      assert :ok = Rooms.give(ctx.slug, ctx.mara.id, give)

      # In-flight immediately:
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.give_status != nil
      assert view.give_status.status == :in_flight
      assert view.give_status.give == give

      # Play continues meanwhile! Commit bridges on current page without stalling:
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")
      await_reveal(ctx.slug)

      view_mid = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_mid.phase == :closed

      # Wait for background Author task to complete
      view_landed =
        eventually(
          fn ->
            v = Rooms.snapshot(ctx.slug, ctx.mara.id)
            v[:give_status] && v.give_status[:status] == :landed && v
          end,
          "the Author task never completed"
        )

      assert view_landed.give_status.status == :landed
      assert view_landed.give_announcement != nil
      assert view_landed.give_announcement.give == give
      assert view_landed.give_announcement.count > 0

      # The arriving pages have joined the pool
      give_pages =
        MeaningGame.Repo.all(from(p in MeaningGame.Pages.AuthoredPage, where: p.give == ^give))

      assert length(give_pages) == view_landed.give_announcement.count

      # Starting the next page moves to the Give setting!
      assert :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      view_next = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_next.page_give == give
      assert view_next.anchors != nil
    end

    test "a failed or refused Author run degrades cleanly and leaves the evening playable", ctx do
      # Configure fake author to fail/refuse
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_delay_ms: 10, author_mode: :refused)
        )
      )

      give = "some forbidden content"
      assert :ok = Rooms.give(ctx.slug, ctx.mara.id, give)

      # Wait for task to fail
      view =
        eventually(
          fn ->
            v = Rooms.snapshot(ctx.slug, ctx.mara.id)
            v[:give_status] && v.give_status[:status] == :failed && v
          end,
          "the Author failure never landed"
        )

      assert view.give_status.status == :failed
      assert view.give_status.give == give
      assert view.give_failure != nil
      assert view.give_failure.give == give
      assert view.give_failure.reason =~ "declined"

      # The evening remains completely playable from existing pool:
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")
      await_reveal(ctx.slug)

      view_after = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_after.phase == :closed
      assert view_after.reveal != nil
    end
  end

  describe "A/B experiments harness (ticket 13)" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

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

    test "every Page assignment and outcome are Chronicle events", ctx do
      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: ctx.slug)

      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairo")
      await_reveal(ctx.slug)

      assert [assignment] = MeaningGame.Chronicle.experiment_assignments(room.id)
      assert assignment.arm in ["bait", "plain"]
      assert assignment.experiment_id == "bait_against_plain"

      assert [outcome] = MeaningGame.Chronicle.experiment_outcomes(room.id)
      assert outcome.arm == assignment.arm
      assert outcome.melded == true
      assert outcome.attempts_count == 1
    end

    test "scoring respects arm: bait convergence scores 75 in bait arm and 100 in plain arm",
         ctx do
      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: ctx.slug)

      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "lighthouse")
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "lighthouse")
      reveal_view = await_reveal(ctx.slug)

      [outcome1] = MeaningGame.Chronicle.experiment_outcomes(room.id)

      if outcome1.arm == "bait" do
        assert reveal_view.reveal.closeness == 75
        assert outcome1.trap_converged == true
      else
        assert reveal_view.reveal.closeness == 100
        assert outcome1.trap_converged == false
      end

      # Seed another page in authored pool with known bait
      chapter = "stratified-test-chapter"

      {:ok, _} =
        MeaningGame.Pages.insert_page(%{
          id: "P-DETERMINISTIC-01",
          chapter: chapter,
          theme: chapter,
          anchors: ["beacon", "shore"],
          bait: "light",
          deep_bridges: ["reef"],
          likely_bridges: ["light", "reef"],
          why_these: "Test chapter",
          band_scripts: %{
            "miss" => "m",
            "adjacent" => "a",
            "close" => "c",
            "meld" => "meld",
            "deep_meld" => "dm"
          },
          meta: %{model: "fake", attempts: 1, cost_usd: 0.0}
        })

      # Pre-seed plain in chapter history so next assignment is deterministically bait
      {:ok, _} =
        MeaningGame.Chronicle.record_experiment_assignment(room.id, %{
          page_identifier: "P-DETERMINISTIC-00",
          experiment_id: "bait_against_plain",
          arm: "plain",
          chapter: chapter,
          assigned_at: DateTime.utc_now()
        })

      assert :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "light")
      assert :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "light")
      reveal2 = await_reveal(ctx.slug)

      # Deterministically assigned to bait because plain was trailing
      outcomes = MeaningGame.Chronicle.experiment_outcomes(room.id)
      outcome2 = List.last(outcomes)
      assert outcome2.arm == "bait"
      assert reveal2.reveal.closeness == 75
      assert outcome2.trap_converged == true
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
