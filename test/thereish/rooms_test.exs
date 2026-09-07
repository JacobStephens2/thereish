defmodule Thereish.RoomsTest do
  @moduledoc """
  The Room through its own interface: join, rejoin, snapshot.

  Not async, because a Room is a process of its own and has to borrow the test's
  database connection.
  """
  use Thereish.DataCase, async: false

  import Thereish.RoomFixtures
  import ExUnit.CaptureLog

  alias Thereish.Chronicle
  alias Thereish.Rooms
  alias Thereish.Rooms.Server
  alias Thereish.Rooms.Store

  setup do
    Thereish.Rooms.RateLimit.reset()
    :ok
  end

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
      slug = open_room(seat_limit: Thereish.Steward.seat_cap())

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
      assert {:error, :bad_seat_count} =
               Rooms.create(Thereish.Steward.seat_cap() + 1, device_token())
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

      restarted = once_restarted(fn -> Rooms.snapshot(slug, mara.id) end)
      assert Map.drop(restarted, [:loop, :playing]) == Map.drop(before, [:loop, :playing])
      assert restarted.loop != nil
      assert restarted.playing != nil
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
      alias Thereish.Steward.Legality

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
      assert {:error, :bad_seat_count} = Rooms.create(1, device_token())
      assert {:error, :bad_seat_count} = Rooms.create(0, device_token())
      assert {:error, :bad_seat_count} = Rooms.create("four", device_token())
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

      steward(name_word: "fork", name_quip: "Fork in the road.")

      assert {:ok, "fork"} = Rooms.create(2, token)
      assert Rooms.snapshot("fork", nil).quip == "Fork in the road."
      stop_room("fork")
      stop_room(slug)
    end

    test "a phone with no history draws a random word and asks for a quip" do
      token = device_token()
      steward(quip_text: "A freshly minted room.")

      assert {:ok, code} = Rooms.create(2, token)
      assert String.length(code) == 4
      assert Rooms.snapshot(code, nil).quip == "A freshly minted room."
      stop_room(code)
    end

    test "a phone with no history succeeds when quip is slow, raises, or unavailable" do
      token1 = device_token()
      steward(quip_mode: :raise)
      assert {:ok, code1} = Rooms.create(2, token1)
      assert Rooms.snapshot(code1, nil).quip == nil
      stop_room(code1)

      token2 = device_token()
      steward(quip_mode: :unavailable)
      assert {:ok, code2} = Rooms.create(2, token2)
      assert Rooms.snapshot(code2, nil).quip == nil
      stop_room(code2)

      token3 = device_token()
      steward(quip_delay_ms: 1_500)
      assert {:ok, code3} = Rooms.create(2, token3)
      assert Rooms.snapshot(code3, nil).quip == nil
      stop_room(code3)
    end

    test "creation is rate limited per device token and per remote address" do
      prev_config = Application.get_env(:thereish, :room_creation_rate_limit)

      Application.put_env(:thereish, :room_creation_rate_limit,
        per_device: 2,
        per_address: 3,
        window_seconds: 3600
      )

      on_exit(fn ->
        if prev_config,
          do: Application.put_env(:thereish, :room_creation_rate_limit, prev_config),
          else: Application.delete_env(:thereish, :room_creation_rate_limit)

        Thereish.Rooms.RateLimit.reset()
      end)

      token = device_token()
      ip = "192.168.1.50"

      assert {:ok, code1} = Rooms.create(2, token, address: ip)
      stop_room(code1)

      # 2nd creation with this token is refused (per_device is 2)
      assert {:error, :rate_limited} = Rooms.create(2, token, address: ip)

      # Different token, same IP: 2nd creation on this IP is allowed (since per_address is 3)
      token2 = device_token()
      assert {:ok, code2} = Rooms.create(2, token2, address: ip)
      stop_room(code2)

      # 3rd creation on this IP is refused (per_address is 3)
      token3 = device_token()
      assert {:error, :rate_limited} = Rooms.create(2, token3, address: ip)
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

  describe "the new-Room notice" do
    defmodule FailingMailerAdapter do
      use Swoosh.Adapter
      def deliver(_email, _config), do: raise("SES connection failed")
      def deliver_many(_emails, _config), do: raise("SES connection failed")
    end

    test "creating a Room from a device with no history delivers exactly one notice carrying the Code, the count, the time and a link; a device with history delivers none" do
      # Device with no history:
      token_new = device_token()
      assert {:ok, code_new} = Rooms.create(2, token_new)

      assert_receive {:email, email}, 1_000
      assert email.to == [{"", "operator@example.com"}]
      assert email.from == {"", "notice@thereish.app"}
      assert email.subject =~ code_new
      assert email.text_body =~ code_new
      assert email.text_body =~ "2"
      assert email.text_body =~ "/r/#{code_new}"
      refute_received {:email, _}

      stop_room(code_new)

      # Device with history:
      token_with_history = device_token()
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", token_with_history)
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)
      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairns")
      await_reveal(slug)

      # Clear any mailbox messages
      receive do
        {:email, _} -> :ok
      after
        0 -> :ok
      end

      assert {:ok, code_returning} = Rooms.create(2, token_with_history)
      await_notice()
      refute_received {:email, _}

      stop_room(code_returning)
      stop_room(slug)
    end

    test "delivery runs in a supervised task; a Mailer that raises leaves creation successful and logs" do
      token = device_token()

      previous_mailer_config = Application.get_env(:thereish, Thereish.Mailer)
      Application.put_env(:thereish, Thereish.Mailer, adapter: FailingMailerAdapter)

      on_exit(fn ->
        Application.put_env(:thereish, Thereish.Mailer, previous_mailer_config)
      end)

      log =
        capture_log(fn ->
          assert {:ok, code} = Rooms.create(2, token)
          await_notice()
          stop_room(code)
        end)

      assert log =~ "SES connection failed"
    end

    test "with no credentials configured the Mailer is not called" do
      token = device_token()

      previous_notice_config = Application.get_env(:thereish, :notice)
      Application.put_env(:thereish, :notice, to: nil, from: nil)

      on_exit(fn ->
        Application.put_env(:thereish, :notice, previous_notice_config)
      end)

      assert {:ok, code} = Rooms.create(2, token)
      await_notice()
      refute_received {:email, _}

      stop_room(code)
    end

    test "creating a Room with nil device token delivers no notice" do
      assert {:ok, code} = Rooms.create(2, nil)
      await_notice()
      refute_received {:email, _}

      stop_room(code)
    end
  end

  describe "opening a Room" do
    test "a Code no Room could have is no Room, not a new one" do
      assert {:error, :bad_code} = Rooms.ensure_started("Not A Code")
      assert {:error, :bad_code} = Rooms.ensure_started("")

      assert_raise Thereish.Rooms.NoSuchRoomError, fn -> Rooms.open!("Not A Code") end
    end

    test "a Code nobody created is a 404, and visiting it creates nothing" do
      code = "cane-#{System.unique_integer([:positive])}"

      assert {:error, :no_such_room} = Rooms.ensure_started(code)
      assert_raise Thereish.Rooms.NoSuchRoomError, fn -> Rooms.open!(code) end

      refute Thereish.Repo.get_by(Thereish.Rooms.Room, slug: code)
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

      room = Thereish.Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)
      assert [overrule] = Thereish.Chronicle.overrules(room.id)
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

      room = Thereish.Repo.get_by!(Thereish.Rooms.Room, slug: slug)
      initial_page_count = Thereish.Repo.aggregate(Thereish.Chronicle.Page, :count)

      # Propose and agree to overrule
      :ok = Rooms.propose_overrule(slug, mara.id)
      :ok = Rooms.agree_overrule(slug, jacob.id)

      view = Rooms.snapshot(slug, mara.id)
      assert view.reveal.closeness == 90
      assert view.reveal.melded?
      assert view.phase == :closed

      # No duplicate page was written to the Chronicle
      assert Thereish.Repo.aggregate(Thereish.Chronicle.Page, :count) == initial_page_count
      assert [overrule] = Thereish.Chronicle.overrules(room.id)
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
      room = Thereish.Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)
      taps = Thereish.Chronicle.fairness_taps(room.id)
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

      steward = Application.fetch_env!(:thereish, :steward)
      on_exit(fn -> Application.put_env(:thereish, :steward, steward) end)

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
        :thereish,
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
        :thereish,
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
        :thereish,
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
        :thereish,
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
        :thereish,
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
        :thereish,
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
        :thereish,
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

      pid = GenServer.whereis(Thereish.Rooms.Server.via(ctx.slug))

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
      room = Thereish.Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)

      refute Thereish.Chronicle.experiment_unblinded?(room.id)

      assert :ok = Rooms.unblind_experiment(ctx.slug, ctx.jacob.id)
      assert Thereish.Chronicle.experiment_unblinded?(room.id)

      [unblinding] = Thereish.Chronicle.experiment_unblindings(room.id)
      assert unblinding.seat_id == ctx.jacob.id
      assert unblinding.experiment_id == "bait_against_plain"
    end

    test "author_model assigns alternating arms and allows bookends taps at closed", ctx do
      room = Thereish.Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)
      [asgn1] = Thereish.Chronicle.experiment_assignments(room.id, "author_model")
      assert asgn1.arm == "flash"

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_phase(ctx.slug, :closed)

      view1 = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view1.phase == :closed
      assert view1.your_bookends_tap == nil

      assert :ok = Rooms.tap_bookends(ctx.slug, ctx.mara.id, "great")
      view_m = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_m.your_bookends_tap == "great"

      assert :ok = Rooms.tap_bookends(ctx.slug, ctx.mara.id, "fine")
      assert Rooms.snapshot(ctx.slug, ctx.mara.id).your_bookends_tap == "fine"

      assert :ok = Rooms.tap_bookends(ctx.slug, ctx.jacob.id, "flat")
      assert Rooms.snapshot(ctx.slug, ctx.jacob.id).your_bookends_tap == "flat"

      [outcome1] = Thereish.Chronicle.experiment_outcomes(room.id, "author_model")
      assert outcome1.arm == "flash"
      assert outcome1.taps[to_string(ctx.mara.id)] == "fine"
      assert outcome1.taps[to_string(ctx.jacob.id)] == "flat"
      assert outcome1.closing_band == "deep_meld"

      assert :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "harbour")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "lantern")
      await_phase(ctx.slug, :bridging)

      assignments = Thereish.Chronicle.experiment_assignments(room.id, "author_model")
      assert length(assignments) == 2
      assert Enum.map(assignments, & &1.arm) == ["flash", "astra"]
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

    test "a new Room has no speaker, voice off, and music page by default", ctx do
      room = Store.get_room(ctx.slug)
      assert is_nil(room.speaker)
      assert room.voice == false
      assert room.music == "page"
    end

    test "migration pair converts house_loop_only true to house and drops house_loop_only" do
      migrations_dir = Application.app_dir(:thereish, "priv/repo/migrations")
      expand_file = Path.join(migrations_dir, "20260907140000_add_music_to_rooms.exs")

      contract_file =
        Path.join(migrations_dir, "20260907140001_remove_house_loop_only_from_rooms.exs")

      assert File.exists?(expand_file)
      assert File.exists?(contract_file)
      assert File.read!(expand_file) =~ "add :music"

      assert File.read!(expand_file) =~
               "UPDATE rooms SET music = 'house' WHERE house_loop_only = true"

      assert File.read!(contract_file) =~ "remove :house_loop_only"

      # Verify the expand-and-contract migration pair on a table with the pre-migration shape
      Ecto.Adapters.SQL.query!(Thereish.Repo, """
      CREATE TEMP TABLE test_migration_rooms (
        id UUID PRIMARY KEY,
        slug VARCHAR(255),
        seat_limit INT,
        voice BOOLEAN DEFAULT false,
        house_loop_only BOOLEAN DEFAULT false,
        inserted_at TIMESTAMP,
        updated_at TIMESTAMP
      )
      """)

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      Ecto.Adapters.SQL.query!(
        Thereish.Repo,
        "INSERT INTO test_migration_rooms (id, slug, seat_limit, voice, house_loop_only, inserted_at, updated_at) VALUES (gen_random_uuid(), 'mig-true', 2, false, true, $1, $1)",
        [now]
      )

      Ecto.Adapters.SQL.query!(
        Thereish.Repo,
        "INSERT INTO test_migration_rooms (id, slug, seat_limit, voice, house_loop_only, inserted_at, updated_at) VALUES (gen_random_uuid(), 'mig-false', 2, false, false, $1, $1)",
        [now]
      )

      # Expand: add music column and backfill from house_loop_only
      Ecto.Adapters.SQL.query!(
        Thereish.Repo,
        "ALTER TABLE test_migration_rooms ADD COLUMN music VARCHAR(255) DEFAULT 'page' NOT NULL"
      )

      Ecto.Adapters.SQL.query!(
        Thereish.Repo,
        "UPDATE test_migration_rooms SET music = 'house' WHERE house_loop_only = true"
      )

      res_true =
        Ecto.Adapters.SQL.query!(
          Thereish.Repo,
          "SELECT music FROM test_migration_rooms WHERE slug = 'mig-true'",
          []
        )

      res_false =
        Ecto.Adapters.SQL.query!(
          Thereish.Repo,
          "SELECT music FROM test_migration_rooms WHERE slug = 'mig-false'",
          []
        )

      assert res_true.rows == [["house"]]
      assert res_false.rows == [["page"]]

      # Contract: remove house_loop_only column
      Ecto.Adapters.SQL.query!(
        Thereish.Repo,
        "ALTER TABLE test_migration_rooms DROP COLUMN house_loop_only"
      )

      cols =
        Ecto.Adapters.SQL.query!(
          Thereish.Repo,
          "SELECT column_name FROM information_schema.columns WHERE table_name = 'test_migration_rooms'"
        ).rows
        |> List.flatten()

      assert "music" in cols
      refute "house_loop_only" in cols
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

    test "voice and music switches update the Room and broadcast", ctx do
      Rooms.subscribe(ctx.slug)

      assert :ok = Rooms.set_voice(ctx.slug, true)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).voice == true

      assert :ok = Rooms.set_music(ctx.slug, "off")
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).music == "off"

      assert :ok = Rooms.set_music(ctx.slug, :house)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).music == "house"

      assert :ok = Rooms.set_music(ctx.slug, "page")
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).music == "page"

      assert :ok = Rooms.set_voice(ctx.slug, false)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).voice == false
    end

    test "speaker, voice and music survive a Room process restart", ctx do
      assert :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      assert :ok = Rooms.set_voice(ctx.slug, true)
      assert :ok = Rooms.set_music(ctx.slug, "off")

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
      assert room.music == "off"
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
        assert view.music == "page"
        refute Map.has_key?(view, :house_loop_only)
        refute Map.has_key?(view, :speaker)
        refute Map.has_key?(view, :device_token)
      end

      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)
      :ok = Rooms.set_music(ctx.slug, "house")

      view_a = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      view_b = Rooms.snapshot(ctx.slug, ctx.jacob.id, ctx.token_b)
      view_stage = Rooms.snapshot(ctx.slug, nil, device_token())

      assert view_a.speaker? == true
      assert view_a.speaker_claimed? == true
      assert view_a.voice == true
      assert view_a.music == "house"

      assert view_b.speaker? == false
      assert view_b.speaker_claimed? == true
      assert view_b.voice == true
      assert view_b.music == "house"
      assert view_stage.speaker? == false
      assert view_stage.speaker_claimed? == true

      json = Jason.encode!(view_a)
      refute json =~ ctx.token_a
      refute json =~ ctx.token_b
    end
  end

  describe "the Room starts when everyone is here (ticket 08)" do
    test "Rooms.create/1 opens a count-free Room at the seat cap" do
      assert {:ok, code} = Rooms.create(device_token())
      on_exit(fn -> stop_room(code) end)

      room = Rooms.get_room(code)
      assert room.seat_limit == Thereish.Steward.seat_cap()
    end

    test "a Page starts when seats present declare gives complete and late seats wait for next Page" do
      assert {:ok, slug} = Rooms.create(device_token())
      on_exit(fn -> stop_room(slug) end)

      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      :ok = Rooms.give(slug, mara.id, "lighthouse")

      # 1 give is not enough to start
      assert {:error, :not_enough_gives} = Rooms.start_page(slug, mara.id)

      :ok = Rooms.give(slug, jacob.id, "candle")

      # A third person arrives but hasn't entered a setting
      {:ok, ada} = Rooms.join(slug, "Ada", device_token())

      # Room decides to start with Mara and Jacob's settings
      assert :ok = Rooms.start_page(slug, mara.id)

      # Author completes and transitions to bridging
      await_phase(slug, :bridging)

      ada_view = Rooms.snapshot(slug, ada.id)
      mara_view = Rooms.snapshot(slug, mara.id)

      assert ada_view.late? == true
      assert mara_view.late? == false

      # Ada cannot commit a bridge on this Page
      assert {:error, :not_playing_page} = Rooms.commit_bridge(slug, ada.id, "shore")

      # Mara and Jacob commit bridges
      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairo")

      view = await_reveal(slug)
      assert length(view.reveal.bridges) == 2

      # Fast forward or overrule to close
      :ok = Rooms.propose_overrule(slug, mara.id)
      :ok = Rooms.agree_overrule(slug, jacob.id)

      assert Rooms.snapshot(slug, nil).phase == :closed

      # Starting next page includes Ada
      :ok = Rooms.next_page(slug, ada.id)

      new_ada_view = Rooms.snapshot(slug, ada.id)
      assert new_ada_view.phase == :giving
      assert new_ada_view.late? == false

      assert :ok = Rooms.give(slug, ada.id, "starlight")
    end
  end

  describe "Sides: couple versus couple through the Room" do
    test "pairing seats forms Sides, broadcasts, and unpairing clears them" do
      {:ok, slug} = Rooms.create(4, device_token())
      Rooms.open!(slug)
      Rooms.subscribe(slug)

      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      {:ok, _ada} = Rooms.join(slug, "Ada", device_token())
      {:ok, _ida} = Rooms.join(slug, "Ida", device_token())

      assert :ok = Rooms.pair_seats(slug, mara.id, jacob.id)
      assert_receive :room_changed

      view = Rooms.snapshot(slug, mara.id)
      assert view.sides_mode? == true
      assert length(view.sides) == 2
      [side_a, side_b] = view.sides
      assert side_a.name == "Mara & Jacob"
      assert side_a.you? == true
      assert side_b.name == "Ada & Ida"
      assert side_b.you? == false

      # Unpairing clears sides
      assert :ok = Rooms.unpair_seat(slug, mara.id)
      assert_receive :room_changed
      view_unpaired = Rooms.snapshot(slug, mara.id)
      assert view_unpaired.sides_mode? == false
      assert view_unpaired.sides == nil

      stop_room(slug)
    end

    test "playing an attempt in Sides mode reveals side-by-side verdicts" do
      {:ok, slug} = Rooms.create(4, device_token())
      Rooms.open!(slug)

      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      {:ok, ada} = Rooms.join(slug, "Ada", device_token())
      {:ok, ida} = Rooms.join(slug, "Ida", device_token())

      :ok = Rooms.pair_seats(slug, mara.id, jacob.id)

      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      :ok = Rooms.give(slug, ada.id, "setting three")
      :ok = Rooms.give(slug, ida.id, "setting four")
      await_phase(slug, :bridging)

      # In Fake Assayer: "cairn" and "cairns" share prefix -> closeness 91 (melded!)
      # "wharf" and "signal" share no prefix -> closeness 0
      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairns")
      :ok = Rooms.commit_bridge(slug, ada.id, "wharf")
      :ok = Rooms.commit_bridge(slug, ida.id, "signal")

      view = await_reveal(slug)
      assert view.phase == :closed
      assert view.reveal.mode == :sides
      assert length(view.reveal.sides) == 2

      [side_a, side_b] = view.reveal.sides
      assert side_a.name == "Mara & Jacob"
      assert side_a.closeness >= 90
      assert side_a.melded? == true
      assert side_a.closer? == true

      assert side_b.name == "Ada & Ida"
      assert side_b.closeness == 0
      assert side_b.melded? == false
      assert side_b.closer? == false

      stop_room(slug)
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
      steward_env = Application.get_env(:thereish, :steward, [])
      fake_env = Keyword.get(steward_env, :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(steward_env, :fake, Keyword.put(fake_env, :voice_mode, :unavailable))
      )

      on_exit(fn ->
        Application.put_env(:thereish, :steward, steward_env)
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

    test "failing voice synthesis records voice_meta with zero cost and failure on Verdict",
         ctx do
      steward_env = Application.get_env(:thereish, :steward, [])
      fake_env = Keyword.get(steward_env, :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(steward_env, :fake, Keyword.put(fake_env, :voice_mode, :unavailable))
      )

      on_exit(fn ->
        Application.put_env(:thereish, :steward, steward_env)
      end)

      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_voice(ctx.slug, true)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      room = Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)
      pages = Chronicle.pages(room.id)
      assert length(pages) == 1
      page = hd(pages)
      assert length(page.attempts) == 1
      attempt = hd(page.attempts)
      assert length(attempt.verdicts) == 1
      verdict = hd(attempt.verdicts)

      assert is_map(verdict.voice_meta)
      assert verdict.voice_meta["provider"] == "fake"
      assert verdict.voice_meta["voice"] == "fake-voice"
      assert verdict.voice_meta["cost_usd"] == 0.0
      assert verdict.voice_meta["failure"] =~ "unavailable"
    end

    test "late voice arriving after next attempt started is dropped and logged", ctx do
      steward_env = Application.get_env(:thereish, :steward, [])
      fake_env = Keyword.get(steward_env, :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(steward_env, :fake, Keyword.put(fake_env, :voice_delay_ms, 200))
      )

      on_exit(fn ->
        Application.put_env(:thereish, :steward, steward_env)
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

      room = Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)
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

  describe "couples and the meld map (ticket 07)" do
    test "joining with a partner marks both seats as a couple and survives room restart" do
      slug = open_room(seat_limit: 4)

      assert {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      assert {:ok, jacob} = Rooms.join(slug, "Jacob", device_token(), mara.id)

      view = Rooms.snapshot(slug, mara.id)
      mara_seat = Enum.find(view.seats, &(&1.id == mara.id))
      jacob_seat = Enum.find(view.seats, &(&1.id == jacob.id))

      assert mara_seat.partner_id == jacob.id
      assert mara_seat.partner_name == "Jacob"
      assert mara_seat.couple? == true

      assert jacob_seat.partner_id == mara.id
      assert jacob_seat.partner_name == "Mara"
      assert jacob_seat.couple? == true

      # Survives process crash and restart
      stop_room(slug)

      once_restarted(fn ->
        view_after = Rooms.snapshot(slug, mara.id)
        m = Enum.find(view_after.seats, &(&1.id == mara.id))
        j = Enum.find(view_after.seats, &(&1.id == jacob.id))

        assert m.partner_id == jacob.id
        assert j.partner_id == mara.id
      end)
    end

    test "two seats can be paired after joining via Rooms.pair_seats/3" do
      slug = open_room(seat_limit: 4)

      assert {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      assert {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      assert :ok = Rooms.pair_seats(slug, mara.id, jacob.id)

      view = Rooms.snapshot(slug, mara.id)
      m = Enum.find(view.seats, &(&1.id == mara.id))
      j = Enum.find(view.seats, &(&1.id == jacob.id))

      assert m.partner_id == jacob.id
      assert j.partner_id == mara.id
    end

    test "an Attempt commit grades all pairs alongside the one Verdict" do
      slug = open_room(seat_limit: 4)

      assert {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      assert {:ok, jacob} = Rooms.join(slug, "Jacob", device_token(), mara.id)
      assert {:ok, bram} = Rooms.join(slug, "Bram", device_token())
      assert {:ok, esme} = Rooms.join(slug, "Esme", device_token(), bram.id)

      Enum.each([mara, jacob, bram, esme], fn s ->
        :ok = Rooms.give(slug, s.id, "setting #{s.name}")
      end)

      await_phase(slug, :bridging)

      :ok = Rooms.commit_bridge(slug, mara.id, "dock")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairn")
      :ok = Rooms.commit_bridge(slug, bram.id, "cairo")
      :ok = Rooms.commit_bridge(slug, esme.id, "beacon")

      view = await_reveal(slug)

      # The one Verdict is preserved (ADR-0010)
      assert view.reveal.closeness != nil
      assert view.reveal.furthest != nil

      # Pairs are present: 4 choose 2 = 6 pairs
      assert is_list(view.reveal.pairs)
      assert length(view.reveal.pairs) == 6

      # Mara's view puts Mara & Jacob couple first
      mara_view = Rooms.snapshot(slug, mara.id)
      [first_pair | _] = mara_view.reveal.pairs
      assert first_pair.names == ["Mara", "Jacob"]
      assert first_pair.couple? == true

      # Bram's view puts Bram & Esme couple first
      bram_view = Rooms.snapshot(slug, bram.id)
      [first_pair_bryan | _] = bram_view.reveal.pairs
      assert first_pair_bryan.names == ["Bram", "Esme"]
      assert first_pair_bryan.couple? == true

      assert Enum.count(view.reveal.pairs, & &1.couple?) == 2
      assert Enum.count(view.reveal.pairs, & &1.cross_couple?) == 4
    end
  end

  describe "Foley scoring and track management" do
    setup do
      slug = open_room()
      token_a = device_token()
      token_b = device_token()
      {:ok, mara} = Rooms.join(slug, "Mara", token_a)
      {:ok, jacob} = Rooms.join(slug, "Jacob", token_b)

      %{slug: slug, mara: mara, jacob: jacob, token_a: token_a, token_b: token_b}
    end

    test "when Author writes the Page, a score task runs and the track lands on the snapshot",
         ctx do
      Rooms.subscribe(ctx.slug)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "summer camp")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "viking beaches")

      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        not is_nil(view[:track])
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_binary(view.track.path)
      assert view.track.format == :mp3
      assert view.track.meta.provider == "fake"
    end

    test "a scored track arriving for a Page that has moved on is dropped", ctx do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)

      # Play through to closed
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      pid = GenServer.whereis(Server.via(ctx.slug))
      stale_ref = make_ref()

      stale_track = %{
        path: "/media/tracks/stale.mp3",
        duration: 100,
        format: :mp3,
        meta: %{provider: "fake"}
      }

      # While closed (before next_page), a late scored message is dropped and does not overwrite track
      send(pid, {:scored, stale_ref, {:ok, stale_track}})
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_nil(view[:track]) or view.track.path != stale_track.path

      # Move to next page
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      # Send a late scored message with an old page ref directly to the Room Server
      send(pid, {:scored, stale_ref, {:ok, stale_track}})

      # The current snapshot should have no track
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_nil(view[:track])
    end

    test "setting page mid-Page with no Track and no task running starts a score task", ctx do
      :ok = Rooms.set_music(ctx.slug, "house")

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "cabin in woods")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "desert night")

      await_phase(ctx.slug, :bridging)

      # Under house, no track and no task running
      Process.sleep(50)
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_nil(view[:track])

      # Switch to page mid-Page
      Rooms.subscribe(ctx.slug)
      assert :ok = Rooms.set_music(ctx.slug, "page")
      assert_receive :room_changed

      # Score task starts and delivers track
      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        not is_nil(view[:track])
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert String.starts_with?(view.track.path, "/media/tracks/fake-")
    end

    test "under house or off, score task does not start, and late track is kept for later switch back",
         ctx do
      :ok = Rooms.set_music(ctx.slug, "off")

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "cabin in woods")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "desert night")

      await_phase(ctx.slug, :bridging)

      Process.sleep(50)
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_nil(view[:track])

      # Under house, late answer is kept rather than played
      :ok = Rooms.set_music(ctx.slug, "house")
      pid = GenServer.whereis(Server.via(ctx.slug))
      page_ref = :sys.get_state(pid).current_page_ref

      fake_track = %{
        path: "/media/tracks/late-answer.mp3",
        duration: 120,
        format: :mp3,
        meta: %{provider: "fake"}
      }

      send(pid, {:scored, page_ref, {:ok, fake_track}})

      # Under house, the track is NOT exposed in snapshot
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_nil(view[:track])

      # Switch back to page: kept track is immediately exposed
      :ok = Rooms.set_music(ctx.slug, "page")
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.track.path == "/media/tracks/late-answer.mp3"
    end

    test "a failing score task leaves track nil and records failure in music_meta on the Chronicle page",
         ctx do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.put(fake_config, :music_mode, :unavailable)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)

      # Track remains nil (leaving loop playing)
      Process.sleep(50)
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_nil(view[:track])

      # Solve the page with a meld
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      eventually(fn ->
        pages = Thereish.Chronicle.page_views(ctx.slug)
        pages != [] and hd(pages).music_meta != nil
      end)

      [page | _] = Thereish.Chronicle.page_views(ctx.slug)
      assert page.music_meta[:failure] != nil or page.music_meta["failure"] != nil
    end

    test "successful score records music_meta on the closed Chronicle page", ctx do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "ancient ruins")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "starry night")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        not is_nil(view[:track])
      end)

      # Meld to close page
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      eventually(fn ->
        pages = Thereish.Chronicle.page_views(ctx.slug)
        pages != [] and hd(pages).music_meta != nil
      end)

      [page | _] = Thereish.Chronicle.page_views(ctx.slug)
      assert page.music_meta[:provider] == "fake" or page.music_meta["provider"] == "fake"
      assert page.music_meta[:cost_usd] != nil or page.music_meta["cost_usd"] != nil
    end
  end

  describe "the Scribe titles the Track" do
    setup do
      slug = open_room()
      token_a = device_token()
      token_b = device_token()
      {:ok, mara} = Rooms.join(slug, "Mara", token_a)
      {:ok, jacob} = Rooms.join(slug, "Jacob", token_b)

      %{slug: slug, mara: mara, jacob: jacob}
    end

    defp set_fake(opts) do
      steward = Application.get_env(:thereish, :steward, [])
      fake = Keyword.get(steward, :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(steward, :fake, Keyword.merge(fake, opts))
      )

      on_exit(fn ->
        Application.put_env(:thereish, :steward, steward)
      end)
    end

    test "title lands on Track before delayed Track answers", ctx do
      set_fake(music_delay_ms: 50, title_delay_ms: 0)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "summer camp")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "viking beaches")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        view[:track] != nil and view.track[:title] != nil
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.track.title == "Summer Camp · Viking Beaches"
      assert view.track.path =~ "/media/tracks/"
      assert view.music_meta[:title] == "Summer Camp · Viking Beaches"
      assert view.music_meta[:path] == view.track.path
      assert view.music_meta[:title_cost_usd] != nil
    end

    test "track lands before title (Track before title race)", ctx do
      set_fake(music_delay_ms: 0, title_delay_ms: 60)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "lantern")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "harbour")
      await_phase(ctx.slug, :bridging)

      # Track lands first
      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        view[:track] != nil
      end)

      # Eventually title lands and updates track
      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        view.track[:title] != nil
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.track.title == "Lantern · Harbour"
      assert view.music_meta[:title] == "Lantern · Harbour"
      assert view.music_meta[:title_cost_usd] != nil
    end

    test "cache hit answers file and title without provider call", ctx do
      gives = ["glacier", "tundra"]

      cached_track = %{
        title: "Frozen Horizon",
        path: "/media/tracks/frozen-glacier-tundra.mp3",
        duration: 120,
        format: :mp3,
        meta: %{provider: "cached", cost_usd: 0.04}
      }

      {:ok, _} = Thereish.Steward.TrackCache.put(gives, cached_track)

      # Break provider calls to prove cache hit requires no provider call
      set_fake(music_mode: :unavailable, title_mode: :unavailable)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "glacier")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "tundra")
      await_phase(ctx.slug, :bridging)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.track != nil
      assert view.track.title == "Frozen Horizon"
      assert view.track.path == "/media/tracks/frozen-glacier-tundra.mp3"
      assert view.music_meta[:title] == "Frozen Horizon"
    end

    test "dropped title: title for a Page that moved on is dropped", ctx do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting a")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting b")
      await_phase(ctx.slug, :bridging)

      pid = GenServer.whereis(Server.via(ctx.slug))
      old_page_ref = :sys.get_state(pid).current_page_ref

      # Advance to next attempt and meld to close page
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      # Send late title for the old page ref
      send(pid, {:titled, old_page_ref, {:ok, %{title: "Late Title", meta: %{cost_usd: 0.0}}}})

      # Current track does not adopt late title
      state = :sys.get_state(pid)
      refute state[:current_title] == "Late Title"
    end

    test "race: both late (both title and track arrive after page moved on)", ctx do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting c")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting d")
      await_phase(ctx.slug, :bridging)

      pid = GenServer.whereis(Server.via(ctx.slug))
      old_page_ref = :sys.get_state(pid).current_page_ref

      # Advance to next attempt and meld to close page
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      # Send both late title and late track for the old page ref
      send(pid, {:titled, old_page_ref, {:ok, %{title: "Late Title", meta: %{cost_usd: 0.0}}}})

      send(
        pid,
        {:scored, old_page_ref,
         {:ok, %{path: "/media/tracks/late.mp3", duration: 120, format: :mp3, meta: %{}}}}
      )

      # Neither late title nor late track lands on the room
      state = :sys.get_state(pid)
      refute state[:current_title] == "Late Title"
      refute state[:current_track] && state.current_track[:path] == "/media/tracks/late.mp3"
    end

    test "closed Chronicle page carries title and path and title cost in music_meta", ctx do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "deep sea")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "coral reef")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        view[:track] != nil and view.track[:title] != nil
      end)

      # Meld to close page
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      eventually(fn ->
        pages = Thereish.Chronicle.page_views(ctx.slug)

        pages != [] and hd(pages).music_meta != nil and
          (hd(pages).music_meta[:title] != nil or hd(pages).music_meta["title"] != nil)
      end)

      [page | _] = Thereish.Chronicle.page_views(ctx.slug)
      assert page.music_meta[:title] != nil or page.music_meta["title"] != nil
      assert page.music_meta[:path] != nil or page.music_meta["path"] != nil
      assert page.music_meta[:title_cost_usd] != nil or page.music_meta["title_cost_usd"] != nil
    end
  end

  describe "in-play count (Spend stays a ledger of the record)" do
    setup do
      slug = open_room()
      token_a = device_token()
      token_b = device_token()
      {:ok, mara} = Rooms.join(slug, "Mara", token_a)
      {:ok, jacob} = Rooms.join(slug, "Jacob", token_b)
      %{slug: slug, mara: mara, jacob: jacob, token_a: token_a, token_b: token_b}
    end

    test "in_play_count is 1 for a Room in bridging and 0 after its Page closes", ctx do
      room = Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)

      # In giving, phase is not bridging/assaying/reveal
      assert Rooms.snapshot(ctx.slug, nil).phase == :giving
      assert Rooms.in_play_count(ctx.slug) == 0

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "lantern")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "harbour")
      await_phase(ctx.slug, :bridging)

      assert Rooms.in_play_count(ctx.slug) == 1
      assert Rooms.in_play_count(room.id) == 1
      assert Rooms.in_play_count() >= 1

      # Melding closes the page
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      eventually(
        fn ->
          Rooms.snapshot(ctx.slug, nil).phase == :closed
        end,
        "the room never closed"
      )

      assert Rooms.in_play_count(ctx.slug) == 0
      assert Rooms.in_play_count(room.id) == 0
    end

    test "in_play_count is 0 for an unknown or unstarted room" do
      assert Rooms.in_play_count("nonexistent-slug") == 0
      assert Rooms.in_play_count(Ecto.UUID.generate()) == 0
    end

    test "in_play_sentence formats the sentence and omits when zero" do
      assert Rooms.in_play_sentence(0) == nil
      assert Rooms.in_play_sentence(1) == "1 Page in play, not yet counted"
      assert Rooms.in_play_sentence(2) == "2 Pages in play, not yet counted"
      assert Rooms.in_play_sentence(10) == "10 Pages in play, not yet counted"
    end
  end

  describe "loop rotation (ticket 03)" do
    setup do
      slug = open_room()
      token_a = device_token()
      token_b = device_token()
      {:ok, mara} = Rooms.join(slug, "Mara", token_a)
      {:ok, jacob} = Rooms.join(slug, "Jacob", token_b)
      %{slug: slug, mara: mara, jacob: jacob, token_a: token_a, token_b: token_b}
    end

    test "snapshot carries wait music / loop as name and path in giving and bridging", ctx do
      # In giving, wait music is present
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert %{name: name, path: path} = view.loop
      assert is_binary(name) and byte_size(name) > 0
      assert is_binary(path)

      # Write page 1
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert %{name: name, path: path} = view.loop
      assert is_binary(name) and byte_size(name) > 0
      assert is_binary(path)
      room = Store.get_room(ctx.slug)
      assert view.loop in Thereish.Foley.Repertoire.pool(room.id)
    end

    test "no-immediate-repeat rule across three Pages", ctx do
      room = Store.get_room(ctx.slug)

      # Page 1
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting 1a")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting 1b")
      await_phase(ctx.slug, :bridging)

      pool1 = Thereish.Foley.Repertoire.pool(room.id)
      view1 = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view1.loop in pool1
      loop1 = view1.loop

      # Solve Page 1 to close
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      eventually(fn -> Rooms.snapshot(ctx.slug, ctx.mara.id).phase == :closed end)

      # Page 2
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting 2a")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting 2b")
      await_phase(ctx.slug, :bridging)

      pool = Thereish.Foley.Repertoire.pool(room.id)
      view2 = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view2.loop in pool
      loop2 = view2.loop
      refute loop2 == loop1

      # Solve Page 2 to close
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      eventually(fn -> Rooms.snapshot(ctx.slug, ctx.mara.id).phase == :closed end)

      # Page 3
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting 3a")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting 3b")
      await_phase(ctx.slug, :bridging)

      pool = Thereish.Foley.Repertoire.pool(room.id)
      view3 = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view3.loop in pool
      loop3 = view3.loop
      refute loop3 == loop2
    end
  end

  describe "ticket 01: The Repertoire is wait music" do
    setup do
      slug = open_room()
      token_a = device_token()
      token_b = device_token()
      {:ok, mara} = Rooms.join(slug, "Mara", token_a)
      {:ok, jacob} = Rooms.join(slug, "Jacob", token_b)
      %{slug: slug, mara: mara, jacob: jacob, token_a: token_a, token_b: token_b}
    end

    test "a brand-new Room's wait music is drawn from Repertoire and plays during giving and writing",
         ctx do
      # In giving phase
      view_giving = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_giving.phase == :giving
      assert view_giving.playing != nil
      assert view_giving.playing.kind == "repertoire"
      assert is_binary(view_giving.playing.path) and byte_size(view_giving.playing.path) > 0
      assert is_binary(view_giving.playing.title) and byte_size(view_giving.playing.title) > 0

      # Set delay on author so writing phase can be observed
      set_fake(author_delay_ms: 100, music_delay_ms: 200)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")

      # In writing phase
      view_writing = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_writing.phase == :writing
      assert view_writing.playing != nil
      assert view_writing.playing.kind == "repertoire"
      assert view_writing.playing.path == view_giving.playing.path

      # In bridging phase before track lands: wait music still playing
      await_phase(ctx.slug, :bridging)
      view_bridging_wait = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_bridging_wait.playing.kind == "repertoire"

      # When track lands: playing switches to track
      eventually(fn ->
        Rooms.snapshot(ctx.slug, ctx.mara.id).track != nil
      end)

      view_bridging_track = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_bridging_track.playing.kind == "track"
      assert view_bridging_track.playing.path == view_bridging_track.track.path
      assert view_bridging_track.playing.title == view_bridging_track.track.title
    end

    test "under house, playing kind is repertoire; under off, playing is nil", ctx do
      view_init = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_init.playing.kind == "repertoire"

      :ok = Rooms.set_music(ctx.slug, "house")
      view_house = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_house.music == "house"
      assert view_house.playing != nil
      assert view_house.playing.kind == "repertoire"
      assert is_nil(view_house.track)

      :ok = Rooms.set_music(ctx.slug, "off")
      view_off = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_off.music == "off"
      assert is_nil(view_off.playing)
      assert is_nil(view_off.track)
    end

    test "House/Off scoring lifecycle: starts no score, keeps in-flight track without playing, plays when switched to page",
         ctx do
      :ok = Rooms.set_music(ctx.slug, "house")

      # Give prompts to move through to bridging
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "forest path")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "misty lake")
      await_phase(ctx.slug, :bridging)

      pid = GenServer.whereis(Server.via(ctx.slug))
      server_state = :sys.get_state(pid)

      # Under House: no score task was started
      refute Map.get(server_state, :score_task_running, false)
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.playing.kind == "repertoire"
      assert is_nil(view.track)

      # An in-flight score arrives while under House: it finishes and is kept, not played
      page_ref = server_state.current_page_ref

      fake_track = %{
        path: "/media/tracks/house-kept.mp3",
        duration: 100,
        format: :mp3,
        title: "House Kept",
        meta: %{provider: "fake"}
      }

      send(pid, {:scored, page_ref, {:ok, fake_track}})

      # Still under House: kept track is NOT played; wait music remains playing
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.playing.kind == "repertoire"
      assert is_nil(view.track)

      # Switching back to page plays the kept track immediately
      :ok = Rooms.set_music(ctx.slug, "page")
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.playing.kind == "track"
      assert view.playing.path == fake_track.path
      assert view.playing.title == fake_track.title

      # Under Off: bus is silenced (playing is nil)
      :ok = Rooms.set_music(ctx.slug, "off")
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_nil(view.playing)

      # Switching back to page resumes playing the kept track
      :ok = Rooms.set_music(ctx.slug, "page")
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.playing.kind == "track"
      assert view.playing.path == fake_track.path
    end

    test "unsettled vs settled Room draw rules", ctx do
      # Stranger track in TrackCache
      {:ok, _} =
        Thereish.Steward.TrackCache.put(["glacier", "tundra"], %{
          title: "Glacier Tundra",
          path: "/media/tracks/glacier.mp3"
        })

      # ctx.slug has no Chronicle tracks (unsettled)
      room = Store.get_room(ctx.slug)
      unsettled_pool = Thereish.Foley.Repertoire.pool(room.id)
      assert "/media/tracks/glacier.mp3" in Enum.map(unsettled_pool, & &1.path)

      # Now settle ctx.slug with its own Chronicle page
      now = DateTime.utc_now()

      %Thereish.Chronicle.Page{}
      |> Thereish.Chronicle.Page.changeset(%{
        room_id: room.id,
        document: %{bookends: ["glacier", "tundra"]},
        author_meta: %{arm: "flash"},
        music_meta: %{
          path: "/media/tracks/our-song.mp3",
          title: "Our Song",
          provider: "fake"
        },
        closed_because: "meld",
        melded: true,
        closeness: 95,
        opened_at: now,
        closed_at: now
      })
      |> Repo.insert!()

      assert Thereish.Foley.Repertoire.settled?(room.id)

      settled_pool = Thereish.Foley.Repertoire.pool(room.id)
      settled_paths = Enum.map(settled_pool, & &1.path)

      assert "/media/tracks/our-song.mp3" in settled_paths
      refute "/media/tracks/glacier.mp3" in settled_paths

      for loop <- Thereish.Foley.Loops.all() do
        assert loop.path in settled_paths
      end
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
