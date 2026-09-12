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

    test "a six-Seat Full table Page opens with six Bookends" do
      slug = open_room(seat_limit: 6)

      seats =
        for name <- ~w(Mara Jacob Ada Ida Ola Ora) do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          seat
        end

      Enum.each(seats, &(:ok = Rooms.give(slug, &1.id, "setting #{&1.name}")))
      view = await_phase(slug, :bridging)

      assert view.bookends == ["lantern", "harbour", "summit", "ember", "grove", "spire"]
      assert view.full_table == true
    end

    test "a six-Seat Full table Page plays from Gives to close" do
      slug = open_room(seat_limit: 6)
      names = ~w(Mara Jacob Ada Ida Ola Ora)
      bridges = ~w(cairn beacon wharf signal torch lamp)

      seats =
        for name <- names do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          seat
        end

      Enum.each(seats, &(:ok = Rooms.give(slug, &1.id, "setting #{&1.name}")))
      view = await_phase(slug, :bridging)
      assert length(view.bookends) == 6

      for {seat, word} <- Enum.zip(seats, bridges) do
        :ok = Rooms.commit_bridge(slug, seat.id, word)
      end

      view = await_reveal(slug)
      assert view.next_bookends == bridges
      assert Enum.map(view.bookend_chips, & &1.word) == view.bookends
      refute Enum.any?(view.bookend_chips, & &1.mask)

      :ok = Rooms.next_attempt(slug, hd(seats).id)
      view = await_phase(slug, :bridging)
      assert view.bookends == bridges
      assert Enum.map(view.bookend_chips, & &1.seat_id) == Enum.map(seats, & &1.id)

      Enum.each(seats, &(:ok = Rooms.commit_bridge(slug, &1.id, "stone")))
      view = await_reveal(slug)
      assert view.phase == :closed
      assert view.reveal.melded?

      room = Store.get_room(slug)
      [page] = Chronicle.book(room.id)
      assert page.full_table == true

      assert hd(page.attempts).bookends == [
               "lantern",
               "harbour",
               "summit",
               "ember",
               "grove",
               "spire"
             ]

      assert hd(page.attempts).carried == bridges
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
      assert view.next_bookends == ~w(cairn cairo beacon signal)
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

  describe "the Assayer remembers its Quips (ticket 11)" do
    test "the assay request carries the Room's last five Quips, oldest dropped" do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      room = Rooms.get_room(slug)

      quips = [
        "Oldest quip, the one that should drop.",
        "Second quip about a lighthouse.",
        "Third quip about a picnic.",
        "Fourth quip about a harbour.",
        "Fifth quip about a cairn.",
        "Sixth quip, still in the window."
      ]

      now = DateTime.utc_now()

      for {quip, index} <- Enum.with_index(quips, 1) do
        entry = remembered_page(mara.id, jacob.id, quip)

        assert {:ok, _page} =
                 Chronicle.write(room.id, entry, DateTime.add(now, index, :second))
      end

      steward(assay_capture: self())

      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)
      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairo")

      assert_receive {:assay, request}, 2_000
      assert request.prior_quips == tl(quips)
      refute "Oldest quip, the one that should drop." in request.prior_quips
    end

    defp remembered_page(mara_id, jacob_id, quip) do
      %{
        page: %{bookends: ["lantern", "harbour"]},
        closed_because: :meld,
        melded?: true,
        closeness: 91,
        attempts: [
          %{
            number: 1,
            bookends: ["lantern", "harbour"],
            closeness: 91,
            melded?: true,
            bridges: [
              %{seat_id: mara_id, bridge: "cairn"},
              %{seat_id: jacob_id, bridge: "cairns"}
            ],
            verdicts: [
              %{
                seat_ids: [mara_id, jacob_id],
                bridges: ["cairn", "cairns"],
                graded?: true,
                closeness: 91,
                band: :meld,
                reasoning: "Same root.",
                quip: quip,
                meta: %{model: "fake", prompt_version: "assay-3", latency_ms: 10, cost_usd: 0.0}
              }
            ]
          }
        ]
      }
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

  describe "hiding a Room from this browser's list" do
    test "drops the shortcut without dropping the Seat, the Room, or the Chronicle" do
      phone = device_token()
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", phone)
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())
      :ok = Rooms.give(slug, mara.id, "setting one")
      :ok = Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)
      :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, jacob.id, "cairns")
      await_phase(slug, :closed)

      room = Rooms.get_room(slug)
      assert [page] = Chronicle.pages(room.id)

      assert [%{room: %{slug: ^slug}}] = Rooms.listed_for_device(phone)
      assert :ok = Rooms.hide(slug, phone)

      assert Rooms.listed_for_device(phone) == []
      assert [%{room: kept_room, seat: kept_seat}] = Rooms.for_device(phone)
      assert kept_room.id == room.id
      assert kept_seat.id == mara.id
      assert kept_seat.device_tokens == [phone]
      assert Rooms.get_room(slug).id == room.id
      assert [kept_page] = Chronicle.pages(room.id)
      assert kept_page.id == page.id
      assert {:ok, seated} = Rooms.rejoin(slug, phone)
      assert seated.id == mara.id
    end

    test "another browser that holds the same Seat still sees the Room" do
      slug = open_room()
      pixel = device_token()
      ipad = device_token()
      {:ok, seat} = Rooms.join(slug, "Mara", pixel)
      {:ok, same} = Rooms.join(slug, "Mara", ipad)
      assert same.id == seat.id

      assert :ok = Rooms.hide(slug, pixel)

      assert Rooms.listed_for_device(pixel) == []
      assert [%{room: %{slug: ^slug}, seat: listed}] = Rooms.listed_for_device(ipad)
      assert listed.id == seat.id
      assert {:ok, seated} = Rooms.rejoin(slug, pixel)
      assert seated.id == seat.id
    end

    test "hiding twice is still hidden, and a Code nobody has cannot be hidden" do
      phone = device_token()
      slug = open_room()
      {:ok, _} = Rooms.join(slug, "Mara", phone)

      assert :ok = Rooms.hide(slug, phone)
      assert :ok = Rooms.hide(slug, phone)
      assert Rooms.listed_for_device(phone) == []
      assert {:error, :no_such_room} = Rooms.hide("zzzz", phone)
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

  describe "masks drawn and kept (ticket 16)" do
    setup do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      steward = Application.fetch_env!(:thereish, :steward)
      on_exit(fn -> Application.put_env(:thereish, :steward, steward) end)

      %{slug: slug, mara: mara, jacob: jacob, steward: steward}
    end

    test "a Mask lands on the snapshot for the giving Seat when a Give lands (Fake)", ctx do
      assert :ok = Rooms.give(ctx.slug, ctx.mara.id, "candlelit cathedral")

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        view.your_mask != nil && view
      end)

      mara_view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert mara_view.your_mask != nil
      assert mara_view.your_mask.url =~ "/media/masks/mask-"

      mara_seat = Enum.find(mara_view.seats, &(&1.id == ctx.mara.id))
      assert mara_seat.mask.url =~ "/media/masks/mask-"

      # Other seat and stage before reveal
      jacob_view = Rooms.snapshot(ctx.slug, ctx.jacob.id)
      assert jacob_view.your_mask == nil
      assert Enum.find(jacob_view.seats, &(&1.id == ctx.mara.id)).mask == :face_down

      stage_view = Rooms.snapshot(ctx.slug, nil)
      assert Enum.find(stage_view.seats, &(&1.id == ctx.mara.id)).mask == :face_down
    end

    test "refusal retries once with a softened prompt then yields the dot; no third call", ctx do
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, draw_mode: :refused, draw_capture: self())
        )
      )

      assert :ok = Rooms.give(ctx.slug, ctx.mara.id, "candlelit cathedral")

      assert_receive {:draw, "candlelit cathedral", _colour, opts}
      refute opts[:softened]

      assert_receive {:draw, "candlelit cathedral", _colour, retry_opts}
      assert retry_opts[:softened] == true

      refute_receive {:draw, _, _, _}, 100

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        view.your_mask == :dot && view
      end)

      mara_view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert mara_view.your_mask == :dot
      assert Enum.find(mara_view.seats, &(&1.id == ctx.mara.id)).mask == :dot
    end

    test "late Mask replaces the dot in place without a page reload", ctx do
      :ok = Rooms.subscribe(ctx.slug)

      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, draw_mode: :refused)
        )
      )

      assert :ok = Rooms.give(ctx.slug, ctx.mara.id, "candlelit cathedral")

      eventually(fn ->
        Rooms.snapshot(ctx.slug, ctx.mara.id).your_mask == :dot
      end)

      # Drain existing messages
      receive do
        :room_changed -> :ok
      after
        0 -> :ok
      end

      # Now simulate a late mask arriving
      room_pid = GenServer.whereis(Server.via(ctx.slug))
      late_mask = %{url: "/media/masks/mask-late.png", meta: %{}}
      send(room_pid, {:mask_landed, ctx.mara.id, nil, {:ok, late_mask}})

      assert_receive :room_changed

      mara_view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert mara_view.your_mask == late_mask
      assert Enum.find(mara_view.seats, &(&1.id == ctx.mara.id)).mask == late_mask
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

      [page] = Chronicle.pages(room.id)
      count = page.author_meta["count"] || page.author_meta[:count]
      assert count == 2

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

    test "a new Room has no speaker, quips on, music page by default, Full table on, and no voice column",
         ctx do
      room = Store.get_room(ctx.slug)
      assert is_nil(room.speaker)
      assert room.quips == true
      assert room.music == "page"
      assert room.prologue_skipped == false
      assert room.full_table == true
      refute :voice in Thereish.Rooms.Room.__schema__(:fields)
    end

    test "migration adds prologue_skipped column" do
      migrations_dir = Application.app_dir(:thereish, "priv/repo/migrations")

      migration_file =
        Path.join(migrations_dir, "20260910120000_add_prologue_skipped_to_rooms.exs")

      assert File.exists?(migration_file)
      content = File.read!(migration_file)
      assert content =~ "add :prologue_skipped, :boolean"
    end

    test "migration adds full_table column defaulting on so existing Rooms read as Full tables" do
      migrations_dir = Application.app_dir(:thereish, "priv/repo/migrations")

      migration_file =
        Path.join(migrations_dir, "20260911130000_add_full_table_to_rooms.exs")

      assert File.exists?(migration_file)
      content = File.read!(migration_file)
      assert content =~ "add :full_table, :boolean"
      assert content =~ "default: true"
    end

    test "migration drops voice and adds quips column" do
      migrations_dir = Application.app_dir(:thereish, "priv/repo/migrations")

      migration_file =
        Path.join(migrations_dir, "20260909160000_drop_voice_and_add_quips_to_rooms.exs")

      assert File.exists?(migration_file)
      content = File.read!(migration_file)
      assert content =~ "remove :voice"
      assert content =~ "add :quips, :boolean"
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

    test "quips, music and Full table switches update the Room and broadcast", ctx do
      Rooms.subscribe(ctx.slug)

      assert :ok = Rooms.set_quips(ctx.slug, false)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).quips == false

      assert :ok = Rooms.set_music(ctx.slug, "off")
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).music == "off"

      assert :ok = Rooms.set_music(ctx.slug, :house)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).music == "house"

      assert :ok = Rooms.set_music(ctx.slug, "page")
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).music == "page"

      assert :ok = Rooms.set_quips(ctx.slug, true)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).quips == true

      assert :ok = Rooms.set_full_table(ctx.slug, false)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).full_table == false

      assert :ok = Rooms.set_full_table(ctx.slug, true)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).full_table == true
    end

    test "speaker, quips, music and Full table survive a Room process restart", ctx do
      assert :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      assert :ok = Rooms.set_quips(ctx.slug, false)
      assert :ok = Rooms.set_music(ctx.slug, "off")
      assert :ok = Rooms.set_full_table(ctx.slug, false)

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
      assert room.quips == false
      assert room.music == "off"
      assert room.full_table == false
      refute Map.has_key?(room, :voice)
    end

    test "skip_prologue sets the Room fact and broadcasts", ctx do
      Rooms.subscribe(ctx.slug)

      assert :ok = Rooms.skip_prologue(ctx.slug)
      assert_receive :room_changed
      assert Store.get_room(ctx.slug).prologue_skipped == true

      view = Rooms.snapshot(ctx.slug, nil, ctx.token_a)
      assert view.prologue_skipped == true
      assert is_nil(view.prologue)
    end

    test "prologue_skipped survives a Room process restart", ctx do
      assert :ok = Rooms.skip_prologue(ctx.slug)

      pid = GenServer.whereis(Server.via(ctx.slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      room =
        once_restarted(fn ->
          {:ok, _slug, _pid} = Rooms.ensure_started(ctx.slug)
          Store.get_room(ctx.slug)
        end)

      assert room.prologue_skipped == true
    end

    test "play_prologue starts active prologue and snapshot exposes it, skip ends it", ctx do
      Rooms.subscribe(ctx.slug)

      assert :ok = Rooms.play_prologue(ctx.slug)
      assert_receive :room_changed

      view = Rooms.snapshot(ctx.slug, nil, ctx.token_a)
      assert is_map(view.prologue)
      assert is_binary(view.prologue.reading)
      assert is_binary(view.prologue.text)

      assert :ok = Rooms.skip_prologue(ctx.slug)
      assert_receive :room_changed

      view_after = Rooms.snapshot(ctx.slug, nil, ctx.token_a)
      assert is_nil(view_after.prologue)
      assert view_after.prologue_skipped == true
    end

    test "snapshot answers speaker?, speaker_claimed? and switches without leaking device tokens",
         ctx do
      view_a = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      view_b = Rooms.snapshot(ctx.slug, ctx.jacob.id, ctx.token_b)
      view_stage = Rooms.snapshot(ctx.slug, nil, device_token())

      for view <- [view_a, view_b, view_stage] do
        assert view.speaker? == false
        assert view.speaker_claimed? == false
        assert view.quips == true
        assert view.music == "page"
        assert view.full_table == true
        refute Map.has_key?(view, :voice)
        refute Map.has_key?(view, :house_loop_only)
        refute Map.has_key?(view, :speaker)
        refute Map.has_key?(view, :device_token)
      end

      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)
      :ok = Rooms.set_quips(ctx.slug, false)
      :ok = Rooms.set_music(ctx.slug, "house")
      :ok = Rooms.set_full_table(ctx.slug, false)

      view_a = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      view_b = Rooms.snapshot(ctx.slug, ctx.jacob.id, ctx.token_b)
      view_stage = Rooms.snapshot(ctx.slug, nil, device_token())

      assert view_a.speaker? == true
      assert view_a.speaker_claimed? == true
      assert view_a.quips == false
      assert view_a.music == "house"
      assert view_a.full_table == false
      refute Map.has_key?(view_a, :voice)

      assert view_b.speaker? == false
      assert view_b.speaker_claimed? == true
      assert view_b.quips == false
      assert view_b.music == "house"
      assert view_b.full_table == false
      refute Map.has_key?(view_b, :voice)

      assert view_stage.speaker? == false
      assert view_stage.speaker_claimed? == true
      assert view_stage.quips == false
      assert view_stage.music == "house"
      assert view_stage.full_table == false
      refute Map.has_key?(view_stage, :voice)

      json = Jason.encode!(view_a)
      refute json =~ ctx.token_a
      refute json =~ ctx.token_b
    end

    test "flipping Full table mid-Page changes the Room fact only and leaves the Page's Bookends",
         ctx do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      view = await_phase(ctx.slug, :bridging)
      bookends = view.bookends
      assert view.full_table == true
      assert is_list(bookends)

      assert :ok = Rooms.set_full_table(ctx.slug, false)

      flipped = Rooms.snapshot(ctx.slug, nil)
      assert flipped.full_table == false
      assert flipped.phase == :bridging
      assert flipped.bookends == bookends
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

    test "when a speaker exists, broadcasts voice_ready and holds audio for attempt", ctx do
      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      assert_receive {:voice_ready, 1}, 2000
      assert {:ok, audio, :mp3} = Rooms.voice_audio(ctx.slug, 1)
      assert is_binary(audio) and byte_size(audio) > 0
      assert {:error, :not_found} = Rooms.voice_audio(ctx.slug, 2)
    end

    test "voice is not spoken when no speaker exists", ctx do
      Rooms.subscribe(ctx.slug)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      refute_receive {:voice_ready, _}, 100
      assert {:error, :not_found} = Rooms.voice_audio(ctx.slug, 1)
    end

    test "with quips hidden, spoken line handed to speak is the band word only; with quips on, line includes quip",
         ctx do
      steward_env = Application.get_env(:thereish, :steward, [])
      fake_env = Keyword.get(steward_env, :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(steward_env, :fake, Keyword.put(fake_env, :voice_recipient, self()))
      )

      on_exit(fn ->
        Application.put_env(:thereish, :steward, steward_env)
      end)

      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)

      # Attempt 1: quips is default on
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "beacon")
      await_reveal(ctx.slug)

      assert_receive {:fake_speak, line1}, 2000
      assert line1 =~ "miss."
      assert line1 =~ "walk into a bar"

      # Attempt 2: turn quips off
      :ok = Rooms.set_quips(ctx.slug, false)
      :ok = Rooms.next_attempt(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :bridging)

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "valley")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "valley")
      await_reveal(ctx.slug)

      assert_receive {:fake_speak, line2}, 2000
      assert line2 == "deep meld"
    end

    test "advancing to next attempt clears past attempt's audio and serves only new attempt's audio",
         ctx do
      Rooms.subscribe(ctx.slug)
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token_a)

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

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)

      room = Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)

      # Voice failure is a Task; the Verdict row waits for it (ADR-0003).
      eventually(fn ->
        match?(
          [%{attempts: [%{verdicts: [%{voice_meta: %{}}]}]}],
          Chronicle.pages(room.id)
        )
      end)

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

    test "music events emit readable info log lines with room code, page ref, event name and timing",
         ctx do
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: :warning) end)

      Rooms.subscribe(ctx.slug)

      log =
        capture_log([level: :info], fn ->
          :ok = Rooms.give(ctx.slug, ctx.mara.id, "forest lake")
          :ok = Rooms.give(ctx.slug, ctx.jacob.id, "pine needles")

          await_phase(ctx.slug, :bridging)

          eventually(fn ->
            view = Rooms.snapshot(ctx.slug, ctx.mara.id)
            not is_nil(view[:track])
          end)
        end)

      pid = GenServer.whereis(Server.via(ctx.slug))
      page_ref = :sys.get_state(pid).track_page_ref
      page_ref_str = inspect(page_ref)

      info_lines =
        log
        |> String.split("\n")
        |> Enum.filter(&(&1 =~ "[info]" and &1 =~ ctx.slug and &1 =~ page_ref_str))

      assert Enum.any?(info_lines, &(&1 =~ "cache miss" and &1 =~ ~r/\+\d+ms/))
      assert Enum.any?(info_lines, &(&1 =~ "score queued" and &1 =~ ~r/\+\d+ms/))
      assert Enum.any?(info_lines, &(&1 =~ "score started" and &1 =~ ~r/\+\d+ms/))
      assert Enum.any?(info_lines, &(&1 =~ "track landed" and &1 =~ ~r/\+\d+ms/))
    end

    test "holdover across next_page and a stale score: landed track holds over and stale score is dropped",
         ctx do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)

      # Wait for track to land
      eventually(fn -> Rooms.snapshot(ctx.slug, ctx.mara.id).playing.kind == "track" end)
      landed_view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      landed_track = landed_view.playing

      # Play through to closed
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # After page closes: snapshot kind is holdover and title is kept
      view_closed = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_closed.playing.kind == "holdover"
      assert view_closed.playing.path == landed_track.path
      assert view_closed.playing.title == landed_track.title

      pid = GenServer.whereis(Server.via(ctx.slug))
      stale_ref = make_ref()

      stale_track = %{
        path: "/media/tracks/stale.mp3",
        duration: 100,
        format: :mp3,
        title: "Stale Track",
        meta: %{provider: "fake"}
      }

      # While closed (before next_page), a late scored message is dropped and does not overwrite holdover
      send(pid, {:scored, stale_ref, {:ok, stale_track}})
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.playing.kind == "holdover"
      assert view.playing.path == landed_track.path

      # Move to next page: landed track holds over into giving
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      view_p2 = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_p2.playing.kind == "holdover"
      assert view_p2.playing.path == landed_track.path
      assert view_p2.playing.title == landed_track.title

      # Send a late scored message with an old page ref directly to the Room Server
      send(pid, {:scored, stale_ref, {:ok, stale_track}})

      # Stale score is dropped and does not replace holdover
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.playing.kind == "holdover"
      assert view.playing.path == landed_track.path
    end

    test "giving and writing keep holdover until new Page's track lands during writing", ctx do
      # Play Page 1 to closed with landed track
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "mountain sunrise")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "ocean cliff")
      await_phase(ctx.slug, :bridging)

      eventually(fn -> Rooms.snapshot(ctx.slug, ctx.mara.id).playing.kind == "track" end)
      p1_track = Rooms.snapshot(ctx.slug, ctx.mara.id).playing

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "vista")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "vista")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Move to Page 2
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      # Giving keeps Page 1's track as holdover
      view_p2_giving = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_p2_giving.playing.kind == "holdover"
      assert view_p2_giving.playing.path == p1_track.path
      assert view_p2_giving.playing.title == p1_track.title

      # Add delay to author and music scoring so we can observe writing phase
      set_fake(author_delay_ms: 100, music_delay_ms: 150, vamp_mode: :unavailable)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "whispering pines")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "winding river")

      # Writing keeps Page 1's track as holdover
      view_p2_writing = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_p2_writing.phase == :writing
      assert view_p2_writing.playing.kind == "holdover"
      assert view_p2_writing.playing.path == p1_track.path
      assert view_p2_writing.playing.title == p1_track.title

      # When Page 2's track lands, it seizes the Speaker in writing
      eventually(fn ->
        Rooms.snapshot(ctx.slug, ctx.mara.id).playing.kind == "track"
      end)

      view_seized = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_seized.playing.kind == "track"
      assert view_seized.playing.path != p1_track.path
    end

    test "if the previous Page never landed a Track, wait music is still a Repertoire draw on next_page",
         ctx do
      # Configure fake so scoring fails
      set_fake(music_mode: :unavailable)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)

      # In bridging, wait music is a Repertoire draw
      view_bridging = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_bridging.playing.kind == "repertoire"

      # Play through to closed
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Closed snapshot playing kind is still repertoire (no landed track)
      view_closed = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_closed.playing.kind == "repertoire"

      # Move to next page
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      # On next_page, wait music is still a Repertoire draw
      view_p2 = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view_p2.playing.kind == "repertoire"
      assert is_binary(view_p2.playing.path)
      assert is_binary(view_p2.playing.title)
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

    test "failing score emits readable warning log line carrying room code, page ref, failure reason, and timing",
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

      log =
        capture_log(fn ->
          :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
          :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
          await_phase(ctx.slug, :bridging)

          eventually(fn ->
            server_state = :sys.get_state(GenServer.whereis(Server.via(ctx.slug)))
            server_state.music_meta != nil
          end)
        end)

      pid = GenServer.whereis(Server.via(ctx.slug))
      page_ref = :sys.get_state(pid).current_page_ref
      page_ref_str = inspect(page_ref)

      warn_lines =
        log
        |> String.split("\n")
        |> Enum.filter(
          &(&1 =~ "[warning]" and &1 =~ ctx.slug and &1 =~ page_ref_str and
              &1 =~ "failure with reason")
        )

      assert length(warn_lines) == 1
      [warn_line] = warn_lines
      assert warn_line =~ ":music_unavailable"
      assert warn_line =~ ~r/\+\d+ms/
    end

    test "log_music_event defines and emits vamp landed in the stated shape for when the vamp ticket lands",
         ctx do
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: :warning) end)

      page_ref = make_ref()
      gives_landed_at = System.monotonic_time(:millisecond) - 150

      log =
        capture_log([level: :info], fn ->
          Server.log_music_event(ctx.slug, page_ref, "vamp landed", gives_landed_at)
        end)

      ref_str = inspect(page_ref)

      assert log =~ "[info]"
      assert log =~ ctx.slug
      assert log =~ ref_str
      assert log =~ "vamp landed"
      assert log =~ ~r/\+\d+ms/
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

    test "on Track cache miss: Room starts Vamp and score together; snapshot shows Vamp before Track and Track replacing it; cache hit skips Vamp",
         ctx do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      # vamp_delay_ms: 0, music_delay_ms: 200
      # Vamp lands immediately, but final scored track takes 200 ms
      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config,
            vamp_delay_ms: 0,
            music_delay_ms: 200
          )
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: :warning) end)

      Rooms.subscribe(ctx.slug)

      log =
        capture_log([level: :info], fn ->
          :ok = Rooms.give(ctx.slug, ctx.mara.id, "frozen lake")
          :ok = Rooms.give(ctx.slug, ctx.jacob.id, "northern lights")

          # 1. As soon as gives are in, Vamp lands before full Track download
          eventually(fn ->
            view = Rooms.snapshot(ctx.slug, ctx.mara.id)
            not is_nil(view[:vamp]) and is_nil(view[:track])
          end)

          vamp_view = Rooms.snapshot(ctx.slug, ctx.mara.id)
          assert vamp_view.vamp.format == :mp3
          assert vamp_view.vamp.duration == 30
          assert vamp_view.vamp.loop == true
          assert is_nil(vamp_view[:track])
          assert vamp_view.playing.kind == "vamp"
          assert vamp_view.playing.path == vamp_view.vamp.path
          assert is_nil(vamp_view.playing.title)

          # Vamp is never titled, cached, persisted, or made a Repertoire member
          refute Map.has_key?(vamp_view.vamp, :title) and not is_nil(vamp_view.vamp[:title])
          room = Thereish.Rooms.Store.get_room(ctx.slug)
          repertoire_paths = Enum.map(Thereish.Foley.Repertoire.members(room.id), & &1.path)
          refute vamp_view.vamp.path in repertoire_paths

          # 2. Once the full score finishes, the track replaces the Vamp on snapshot
          eventually(fn ->
            view = Rooms.snapshot(ctx.slug, ctx.mara.id)
            is_nil(view[:vamp]) and not is_nil(view[:track])
          end)

          final_view = Rooms.snapshot(ctx.slug, ctx.mara.id)
          assert is_nil(final_view[:vamp])
          assert final_view.track.format == :mp3
          assert String.starts_with?(final_view.track.path, "/media/tracks/fake-")
          assert final_view.playing.kind == "track"
          assert final_view.playing.path == final_view.track.path
        end)

      # Verify music log lines appear for vamp started, vamp landed, and track landed
      assert log =~ ~r/Foley music for room #{ctx.slug}.*: vamp started \(\+\d+ms\)/
      assert log =~ ~r/Foley music for room #{ctx.slug}.*: vamp landed \(\+\d+ms\)/
      assert log =~ ~r/Foley music for room #{ctx.slug}.*: track landed \(\+\d+ms\)/

      # 3. Cache hit skips Vamp (lands no Vamp)
      # Create a dummy disk file for the track so TrackCache considers it valid
      final_track_path = Rooms.snapshot(ctx.slug, ctx.mara.id).track.path
      disk_path = Thereish.Steward.TrackCache.disk_path(final_track_path)
      File.mkdir_p!(Path.dirname(disk_path))
      File.write!(disk_path, "mp3-bytes")
      on_exit(fn -> File.rm(disk_path) end)

      # Play through to closed
      await_phase(ctx.slug, :bridging)
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Move to next page and submit identical gives -> cache hit skips Vamp
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      hit_log =
        capture_log([level: :info], fn ->
          :ok = Rooms.give(ctx.slug, ctx.mara.id, "frozen lake")
          :ok = Rooms.give(ctx.slug, ctx.jacob.id, "northern lights")

          eventually(fn ->
            view = Rooms.snapshot(ctx.slug, ctx.mara.id)
            not is_nil(view[:track]) and view.track.path == final_track_path
          end)

          hit_view = Rooms.snapshot(ctx.slug, ctx.mara.id)
          assert is_nil(hit_view[:vamp])
          assert hit_view.track.path == final_track_path
          assert hit_view.playing.kind == "track"
        end)

      assert hit_log =~ ~r/Foley music for room #{ctx.slug}.*: cache hit/
      refute hit_log =~ "vamp started"
      refute hit_log =~ "vamp landed"
    end

    test "on Page 2+: holdover plays during giving, Vamp replaces holdover on cache miss, and Track replaces Vamp",
         ctx do
      # Play Page 1 to closed with a landed track
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "ancient ruins")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "lost temple")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        view.playing.kind == "track"
      end)

      p1_track = Rooms.snapshot(ctx.slug, ctx.mara.id).playing

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Move to Page 2
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      # 1. During giving, Page 1's track holds over
      p2_giving = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert p2_giving.playing.kind == "holdover"
      assert p2_giving.playing.path == p1_track.path

      # Configure Fake: Vamp lands immediately (0 ms), Track takes 200 ms
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config,
            vamp_mode: :ok,
            vamp_delay_ms: 0,
            music_delay_ms: 200
          )
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "whispering pines")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "winding river")

      # 2. Vamp lands before full Track download and replaces holdover
      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        view.playing.kind == "vamp"
      end)

      vamp_view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert vamp_view.playing.kind == "vamp"
      assert not is_nil(vamp_view[:vamp])
      assert vamp_view.playing.path == vamp_view.vamp.path

      # 3. Once full score finishes, Track replaces Vamp
      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        view.playing.kind == "track"
      end)

      track_view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_nil(track_view[:vamp])
      assert track_view.playing.kind == "track"
      assert track_view.playing.path != p1_track.path
    end

    test "same Gives bring back the same Track directly from cache without stream", ctx do
      # Pre-seed track cache
      gives = ["quiet library", "old books"]
      cached_path = "/media/tracks/preseeded-library.mp3"
      cached_file = Thereish.Steward.TrackCache.disk_path(cached_path)
      File.mkdir_p!(Path.dirname(cached_file))
      File.write!(cached_file, "mp3-bytes")
      on_exit(fn -> File.rm(cached_file) end)

      {:ok, _} =
        Thereish.Steward.TrackCache.put(gives, %{
          title: "Quiet Library",
          path: cached_path,
          duration: 120,
          format: "mp3",
          meta: %{provider: "fake"}
        })

      Rooms.subscribe(ctx.slug)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "quiet library")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "old books")

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        not is_nil(view[:track])
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert view.track.path == cached_path
      assert view.track.format == :mp3
      assert view.playing.path == cached_path
    end

    test "a cache row with a missing file is a miss, is removed, and scores fresh", ctx do
      gives = ["lost temple", "ancient ruins"]
      missing_path = "/media/tracks/missing-temple-ruins.mp3"
      cache_key = Thereish.Steward.TrackCache.key(gives)

      # Ensure the file is not on disk
      disk_path = Thereish.Steward.TrackCache.disk_path(missing_path)
      File.rm(disk_path)

      {:ok, _} =
        Thereish.Steward.TrackCache.put(gives, %{
          title: "Lost Temple",
          path: missing_path,
          duration: 120,
          format: "mp3",
          meta: %{provider: "fake"}
        })

      assert Thereish.Repo.get_by(Thereish.Steward.TrackCache, key: cache_key) != nil

      Rooms.subscribe(ctx.slug)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "lost temple")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "ancient ruins")

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        not is_nil(view[:track])
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      # Fresh score instead of the missing cached file
      refute view.track.path == missing_path
      assert view.track.path =~ "ancient ruins-lost temple"
      # The dangling row was replaced: TrackCache now holds the newly scored track
      cached_row = Thereish.Repo.get_by(Thereish.Steward.TrackCache, key: cache_key)
      assert cached_row != nil
      assert cached_row.path != missing_path
      assert cached_row.path == view.track.path
    end

    test "stale vamp message arriving for moved-on Page is dropped", ctx do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting alpha")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting beta")
      await_phase(ctx.slug, :bridging)

      # Play through to closed
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      pid = GenServer.whereis(Server.via(ctx.slug))
      stale_ref = make_ref()

      stale_vamp = %{
        path: "/media/vamps/stale.mp3",
        duration: 30,
        format: :mp3,
        loop: true,
        meta: %{provider: "fake"}
      }

      # Dropped while closed
      send(pid, {:vamped, stale_ref, {:ok, stale_vamp}})
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_nil(view[:vamp]) or view.vamp.path != stale_vamp.path

      # Move to next page
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      # Send late vamp message for old page_ref
      send(pid, {:vamped, stale_ref, {:ok, stale_vamp}})
      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert is_nil(view[:vamp]) or view.vamp.path != stale_vamp.path
    end

    test "score job failing leaves Repertoire playing, records failure in music_meta, and room does not stall",
         ctx do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config,
            music_mode: :unavailable
          )
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      Rooms.subscribe(ctx.slug)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "misty forest")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "mountain creek")

      # When score generation fails, track reverts to nil (Repertoire playing)
      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        is_nil(view[:track]) and view.playing.kind == "repertoire"
      end)

      # Room does not stall: players can still bridge, commit, and meld
      await_phase(ctx.slug, :bridging)
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

    test "two Rooms scoring at once run one at a time (Rooms test with the Fake)" do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config, music_delay_ms: 120)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      slug1 = open_room()
      slug2 = open_room()
      token_a = device_token()
      token_b = device_token()
      token_c = device_token()
      token_d = device_token()

      {:ok, alice} = Rooms.join(slug1, "Alice", token_a)
      {:ok, bob} = Rooms.join(slug1, "Bob", token_b)
      {:ok, carol} = Rooms.join(slug2, "Carol", token_c)
      {:ok, dave} = Rooms.join(slug2, "Dave", token_d)

      :ok = Rooms.give(slug1, alice.id, "glacier peak")
      :ok = Rooms.give(slug1, bob.id, "frozen tundra")
      :ok = Rooms.give(slug2, carol.id, "desert dune")
      :ok = Rooms.give(slug2, dave.id, "sandstorm")

      await_phase(slug1, :bridging)
      await_phase(slug2, :bridging)

      # Room 1 scores first. When Room 1's track lands, Room 2 is still queued!
      eventually(fn ->
        not is_nil(Rooms.snapshot(slug1, alice.id)[:track])
      end)

      # At the moment Room 1 finishes, Room 2 has not landed its track yet
      view2_snapshot = Rooms.snapshot(slug2, carol.id)
      assert is_nil(view2_snapshot[:track])

      # Then Room 2 completes after its own turn
      eventually(fn ->
        not is_nil(Rooms.snapshot(slug2, carol.id)[:track])
      end)

      view2_final = Rooms.snapshot(slug2, carol.id)
      assert not is_nil(view2_final[:track])
    end

    test "a queued Page's snapshot keeps playing what it had until its turn", ctx do
      # Play Page 1 to closed with a landed track
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "ancient stone")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "mossy brook")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        Rooms.snapshot(ctx.slug, ctx.mara.id).playing.kind == "track"
      end)

      p1_track = Rooms.snapshot(ctx.slug, ctx.mara.id).playing

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Move to Page 2
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      # Now occupy the score queue with another Room
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config, music_delay_ms: 150, vamp_mode: :unavailable)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      slug_other = open_room()
      {:ok, p1} = Rooms.join(slug_other, "PlayerOne", device_token())
      {:ok, p2} = Rooms.join(slug_other, "PlayerTwo", device_token())
      :ok = Rooms.give(slug_other, p1.id, "heavy fog")
      :ok = Rooms.give(slug_other, p2.id, "dim lanterns")
      await_phase(slug_other, :bridging)

      # Start Page 2 scoring in ctx.slug - it gets queued behind slug_other
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "autumn woods")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "crackling fire")
      await_phase(ctx.slug, :bridging)

      # While queued, ctx.slug's snapshot keeps playing what it had (Page 1's holdover track)
      queued_snapshot = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert queued_snapshot.playing.kind == "holdover"
      assert queued_snapshot.playing.path == p1_track.path

      # Once turn comes, Page 2 track lands
      eventually(fn ->
        snapshot = Rooms.snapshot(ctx.slug, ctx.mara.id)

        not is_nil(snapshot[:track]) and snapshot.playing.kind == "track" and
          snapshot.playing.path != p1_track.path
      end)
    end

    test "a second music change during an in-flight score starts no second score", ctx do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config, music_delay_ms: 100)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "deep canyon")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "echoing wind")
      await_phase(ctx.slug, :bridging)

      # While score is in flight, toggle music to house and back to page
      :ok = Rooms.set_music(ctx.slug, "house")
      :ok = Rooms.set_music(ctx.slug, "page")

      # Track lands without duplicate scoring
      eventually(fn ->
        not is_nil(Rooms.snapshot(ctx.slug, ctx.mara.id)[:track])
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id)
      assert not is_nil(view.track)
    end

    test "a success after a recorded failure replaces the Page's music record, and the Chronicle shows the Track",
         ctx do
      # Configure fake so initial score fails
      set_fake(music_mode: :unavailable)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "sprint")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "hoard")
      await_phase(ctx.slug, :bridging)

      # Solve the page to close it with failure recorded
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "vault")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "vault")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      eventually(fn ->
        pages = Thereish.Chronicle.page_views(ctx.slug)
        pages != [] and hd(pages).music_meta != nil
      end)

      [page_before | _] = Thereish.Chronicle.page_views(ctx.slug)
      assert page_before.music_meta[:failure] != nil or page_before.music_meta["failure"] != nil
      assert Thereish.Chronicle.page_track(page_before) == nil

      # Now a score succeeds for this page
      pid = GenServer.whereis(Server.via(ctx.slug))
      page_ref = :sys.get_state(pid).current_page_ref

      successful_track = %{
        path: "/media/tracks/fake-sprint-hoard.mp3",
        duration: 120,
        format: :mp3,
        title: "Sprint and Hoard",
        meta: %{provider: "fake", model: "fake-music", cost_usd: 0.04}
      }

      send(pid, {:scored, page_ref, {:ok, successful_track}})

      # The Page's music record in Chronicle is replaced by the success
      eventually(fn ->
        [page_after | _] = Thereish.Chronicle.page_views(ctx.slug)
        page_after.music_meta[:path] != nil or page_after.music_meta["path"] != nil
      end)

      [page_after | _] = Thereish.Chronicle.page_views(ctx.slug)
      assert is_nil(page_after.music_meta[:failure]) and is_nil(page_after.music_meta["failure"])

      assert page_after.music_meta[:path] == "/media/tracks/fake-sprint-hoard.mp3" or
               page_after.music_meta["path"] == "/media/tracks/fake-sprint-hoard.mp3"

      # The Chronicle shows the Track
      assert track = Thereish.Chronicle.page_track(page_after)
      assert track.path == "/media/tracks/fake-sprint-hoard.mp3"
      assert track.title == "Sprint and Hoard"
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

      cached_file = Thereish.Steward.TrackCache.disk_path(cached_track.path)
      File.mkdir_p!(Path.dirname(cached_file))
      File.write!(cached_file, "mp3-bytes")
      on_exit(fn -> File.rm(cached_file) end)

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

    test "cache hit emits readable info log line carrying room code, page ref, and timing", ctx do
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: :warning) end)

      gives = ["glacier", "tundra"]

      cached_track = %{
        title: "Frozen Horizon",
        path: "/media/tracks/frozen-glacier-tundra.mp3",
        duration: 120,
        format: :mp3,
        meta: %{provider: "cached", cost_usd: 0.04}
      }

      # A cache row whose file is gone is a miss (ticket 04), so the row this
      # hit is read from needs its file on disk.
      cached_file = Thereish.Steward.TrackCache.disk_path(cached_track.path)
      File.mkdir_p!(Path.dirname(cached_file))
      File.write!(cached_file, "mp3-bytes")
      on_exit(fn -> File.rm(cached_file) end)

      {:ok, _} = Thereish.Steward.TrackCache.put(gives, cached_track)

      log =
        capture_log([level: :info], fn ->
          :ok = Rooms.give(ctx.slug, ctx.mara.id, "glacier")
          :ok = Rooms.give(ctx.slug, ctx.jacob.id, "tundra")
          await_phase(ctx.slug, :bridging)
        end)

      pid = GenServer.whereis(Server.via(ctx.slug))
      page_ref = :sys.get_state(pid).track_page_ref
      page_ref_str = inspect(page_ref)

      hit_lines =
        log
        |> String.split("\n")
        |> Enum.filter(
          &(&1 =~ "[info]" and &1 =~ ctx.slug and &1 =~ page_ref_str and &1 =~ "cache hit")
        )

      assert length(hit_lines) == 1
      [hit_line] = hit_lines
      assert hit_line =~ ~r/\+\d+ms/
      refute log =~ "score queued"
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
      set_fake(author_delay_ms: 100, music_delay_ms: 200, vamp_mode: :unavailable)

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

  describe "ticket 03: Next" do
    setup do
      slug = open_room()
      token_a = device_token()
      token_b = device_token()
      {:ok, mara} = Rooms.join(slug, "Mara", token_a)
      {:ok, jacob} = Rooms.join(slug, "Jacob", token_b)
      :ok = Rooms.claim_speaker(slug, token_a)
      %{slug: slug, mara: mara, jacob: jacob, token_a: token_a, token_b: token_b}
    end

    test "Next on a Repertoire draw advances the deal without repeating until exhausted, then reshuffles",
         ctx do
      view = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view.next? == true
      assert view.playing.kind == "repertoire"
      initial_path = view.playing.path

      members = Thereish.Foley.Repertoire.members(Store.get_room(ctx.slug).id)
      repertoire_size = length(members)
      assert repertoire_size >= 5

      # Step through the remaining deal (repertoire_size - 1 steps)
      {played_paths, last_path} =
        Enum.reduce(1..(repertoire_size - 1), {[], initial_path}, fn _, {seen, current_path} ->
          assert :ok = Rooms.next(ctx.slug, ctx.token_a)
          v = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
          assert v.next? == true
          assert v.music == "page"
          assert v.playing.kind == "repertoire"
          refute v.playing.path == current_path
          refute v.playing.path in seen
          refute v.playing.path == initial_path
          {[v.playing.path | seen], v.playing.path}
        end)

      # All remaining members have been played; initial_path was never repeated
      assert length(played_paths) == repertoire_size - 1
      refute initial_path in played_paths

      # Deal is exhausted now. Next must reshuffle, never repeating the thing now playing
      assert :ok = Rooms.next(ctx.slug, ctx.token_a)
      reshuffled_view = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert reshuffled_view.playing.kind == "repertoire"
      refute reshuffled_view.playing.path == last_path
    end

    test "Next on holdover leaves last Page's Track and plays a shuffle from the opening draw; mode stays page",
         ctx do
      set_fake(music_delay_ms: 0)

      # Give prompts to advance to bridging and land a track
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a).playing.kind == "track"
      end)

      landed_track = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a).playing

      # Finish Page 1 to closed
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Advance to Page 2
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      # Landed track from Page 1 holds over
      view_holdover = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_holdover.playing.kind == "holdover"
      assert view_holdover.playing.path == landed_track.path
      assert view_holdover.next? == true

      # Skip on holdover: leaves last Page's track, plays a Repertoire draw, mode stays page
      assert :ok = Rooms.next(ctx.slug, ctx.token_a)

      view_after_skip = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_after_skip.music == "page"
      assert view_after_skip.playing.kind == "repertoire"
      refute view_after_skip.playing.path == landed_track.path

      # In-flight track for Page 2 still seizes the Speaker when it lands
      set_fake(author_delay_ms: 100, music_delay_ms: 200, vamp_mode: :unavailable)
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "p2 setting 1")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "p2 setting 2")
      await_phase(ctx.slug, :writing)

      # During writing before score lands: still playing repertoire
      assert Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a).playing.kind == "repertoire"

      # Simulate Page 2 score landing
      pid = GenServer.whereis(Server.via(ctx.slug))
      server_state = :sys.get_state(pid)
      p2_ref = server_state.current_page_ref

      p2_track = %{
        path: "/media/tracks/p2-landed.mp3",
        duration: 100,
        format: :mp3,
        title: "Page Two Score",
        meta: %{provider: "fake"}
      }

      send(pid, {:scored, p2_ref, {:ok, p2_track}})

      # Seizes the speaker immediately
      view_p2_landed = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_p2_landed.playing.kind == "track"
      assert view_p2_landed.playing.path == p2_track.path
      assert view_p2_landed.playing.title == p2_track.title
    end

    test "Next is refused (and is a no-op) while this Page's Track is on the Speaker", ctx do
      set_fake(music_delay_ms: 0)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a).playing.kind == "track"
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view.playing.kind == "track"

      # Next is not offered
      assert view.next? == false

      # Next call is refused
      current_path = view.playing.path
      assert {:error, :refused} = Rooms.next(ctx.slug, ctx.token_a)

      # Playing track is unchanged
      view_after = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_after.playing.kind == "track"
      assert view_after.playing.path == current_path
    end

    test "Next is not offered and is refused when only one playable member remains", ctx do
      pid = GenServer.whereis(Server.via(ctx.slug))
      single = %{name: "Only Loop", title: "Only Loop", path: "/audio/only.mp3"}

      :sys.replace_state(pid, fn state ->
        state
        |> Map.put(:eligible_members, [single])
        |> Map.put(:wait_music, single)
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view.next? == false

      assert {:error, :refused} = Rooms.next(ctx.slug, ctx.token_a)
    end

    test "Next from a non-speaking device is a no-op", ctx do
      initial_view = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      initial_path = initial_view.playing.path

      # Jacob (non-speaking device) calls next -> no-op
      assert :ok = Rooms.next(ctx.slug, ctx.token_b)

      view_after = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_after.playing.path == initial_path

      # Call without device_token -> no-op
      assert :ok = Rooms.next(ctx.slug, nil)
      view_after_nil = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_after_nil.playing.path == initial_path

      # Mara (speaking device) calls next -> advances
      assert :ok = Rooms.next(ctx.slug, ctx.token_a)
      view_advanced = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      refute view_advanced.playing.path == initial_path
    end
  end

  describe "ticket 04: Never" do
    setup do
      slug = open_room()
      token_a = device_token()
      token_b = device_token()
      {:ok, mara} = Rooms.join(slug, "Mara", token_a)
      {:ok, jacob} = Rooms.join(slug, "Jacob", token_b)
      :ok = Rooms.claim_speaker(slug, token_a)
      room = Store.get_room(slug)

      %{
        slug: slug,
        room: room,
        mara: mara,
        jacob: jacob,
        token_a: token_a,
        token_b: token_b
      }
    end

    test "Never in this Room leaves the member out of every later draw, including after process restart",
         ctx do
      view = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view.never? == true
      assert view.playing.kind == "repertoire"
      nevered_path = view.playing.path

      # Mara (speaker) taps Never
      assert :ok = Rooms.never(ctx.slug, ctx.token_a)

      # Song changes immediately to another member, mode stays page
      new_view = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert new_view.music == "page"
      refute new_view.playing.path == nevered_path
      assert new_view.playing.kind == "repertoire"

      # Never is persisted in DB for this room
      assert nevered_path in Store.list_nevers(ctx.room.id)

      # Kill the room process to test restart recovery
      pid = GenServer.whereis(Server.via(ctx.slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      # On restart, the nevered member is not in the Repertoire or deal
      restarted_view =
        once_restarted(fn ->
          {:ok, _slug, _pid} = Rooms.ensure_started(ctx.slug)
          Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
        end)

      refute restarted_view.playing.path == nevered_path

      # Over many draws/skips in the restarted room, nevered_path never returns
      for _ <- 1..10 do
        assert :ok = Rooms.next(ctx.slug, ctx.token_a)
        v = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
        refute v.playing.path == nevered_path
      end
    end

    test "The same member remains drawable in another Room (cross-Room isolation)", ctx do
      slug_b = open_room()
      token_other = device_token()
      {:ok, _player_b} = Rooms.join(slug_b, "Other", token_other)
      :ok = Rooms.claim_speaker(slug_b, token_other)
      room_b = Store.get_room(slug_b)

      view_a = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      nevered_path = view_a.playing.path

      # Room A nevers the member
      assert :ok = Rooms.never(ctx.slug, ctx.token_a)
      assert nevered_path in Store.list_nevers(ctx.room.id)
      refute nevered_path in Store.list_nevers(room_b.id)

      # Room B's eligible members still include that path
      members_b = Thereish.Foley.Repertoire.members(room_b.id)
      assert Enum.any?(members_b, fn m -> m.path == nevered_path end)
    end

    test "Never on the last remaining playable member is refused; Next stays hidden", ctx do
      pid = GenServer.whereis(Server.via(ctx.slug))
      single = %{name: "Only Loop", title: "Only Loop", path: "/audio/only.mp3"}

      :sys.replace_state(pid, fn state ->
        state
        |> Map.put(:eligible_members, [single])
        |> Map.put(:wait_music, single)
        |> Map.put(:deal, [])
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      # Both Next and Never are hidden
      assert view.next? == false
      assert view.never? == false

      # Calls to never and next are refused
      assert {:error, :refused} = Rooms.never(ctx.slug, ctx.token_a)
      assert {:error, :refused} = Rooms.next(ctx.slug, ctx.token_a)

      # Still playing the only loop
      view_after = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_after.playing.path == single.path
    end

    test "Never on this Page's Track refuses it, Speaker advances the deal, mode stays page, and does not hold over",
         ctx do
      set_fake(music_delay_ms: 0)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a).playing.kind == "track"
      end)

      view = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view.playing.kind == "track"
      # Next is hidden while Page's Track is playing, but Never is shown
      assert view.next? == false
      assert view.never? == true
      track_path = view.playing.path

      # Tap Never on this Page's Track
      assert :ok = Rooms.never(ctx.slug, ctx.token_a)

      # Never: Speaker plays Repertoire, mode stays page
      view_after_never = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_after_never.music == "page"
      assert view_after_never.playing.kind == "repertoire"
      refute view_after_never.playing.path == track_path
      assert track_path in Store.list_nevers(ctx.room.id)

      # Complete Attempt and close Page
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Advance to next Page
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      # The nevered Track does NOT hold over!
      view_p2 = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_p2.playing.kind == "repertoire"
      refute view_p2.playing.path == track_path
    end

    test "Never on holdover refuses that old Track here and advances the deal; in-flight Track can still land",
         ctx do
      set_fake(music_delay_ms: 0)

      # Page 1 lands track and closes
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a).playing.kind == "track"
      end)

      p1_track = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a).playing

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Next page -> Page 1's track holds over
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      await_phase(ctx.slug, :giving)

      view_holdover = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_holdover.playing.kind == "holdover"
      assert view_holdover.playing.path == p1_track.path
      assert view_holdover.never? == true
      assert view_holdover.next? == true

      # Never on holdover refuses the old track here
      assert :ok = Rooms.never(ctx.slug, ctx.token_a)

      view_after_never = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_after_never.music == "page"
      assert view_after_never.playing.kind == "repertoire"
      refute view_after_never.playing.path == p1_track.path
      assert p1_track.path in Store.list_nevers(ctx.room.id)

      # Page 2 Gives submitted and score starts
      set_fake(author_delay_ms: 100, music_delay_ms: 200)
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "p2 setting 1")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "p2 setting 2")
      await_phase(ctx.slug, :writing)

      # In-flight Page 2 track lands and seizes the Speaker
      pid = GenServer.whereis(Server.via(ctx.slug))
      server_state = :sys.get_state(pid)
      p2_ref = server_state.current_page_ref

      p2_track = %{
        path: "/media/tracks/p2-landed-after-never.mp3",
        duration: 100,
        format: :mp3,
        title: "Page Two Fresh",
        meta: %{provider: "fake"}
      }

      send(pid, {:scored, p2_ref, {:ok, p2_track}})

      view_p2_landed = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_p2_landed.playing.kind == "track"
      assert view_p2_landed.playing.path == p2_track.path
    end

    test "Never from a non-speaking device is a no-op", ctx do
      view_before = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      initial_path = view_before.playing.path

      # Jacob (token_b, non-speaker) calls Never -> no-op
      assert :ok = Rooms.never(ctx.slug, ctx.token_b)
      view_after_jacob = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_after_jacob.playing.path == initial_path
      refute initial_path in Store.list_nevers(ctx.room.id)

      # nil token -> no-op
      assert :ok = Rooms.never(ctx.slug, nil)
      view_after_nil = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      assert view_after_nil.playing.path == initial_path
      refute initial_path in Store.list_nevers(ctx.room.id)

      # Mara (speaking device) calls Never -> refuses member
      assert :ok = Rooms.never(ctx.slug, ctx.token_a)
      view_after_mara = Rooms.snapshot(ctx.slug, ctx.mara.id, ctx.token_a)
      refute view_after_mara.playing.path == initial_path
      assert initial_path in Store.list_nevers(ctx.room.id)
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
