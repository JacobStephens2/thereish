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

      assert eventually(fn -> Rooms.snapshot(slug, mara.id) end) == before
      assert Rooms.rejoin(slug, token) == {:ok, mara}
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
      assert {:ok, _} = Rooms.join(slug, "Mara", device_token())
      assert Rooms.open!(slug) == slug
      assert length(Rooms.snapshot(slug, nil).seats) == 1
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

  # The registry entry outlives the process it points at by a moment, so a call
  # made the instant after a kill can land on a corpse.
  defp eventually(fun, tries \\ 50) do
    fun.()
  catch
    :exit, reason ->
      if tries > 0 do
        Process.sleep(10)
        eventually(fun, tries - 1)
      else
        exit(reason)
      end
  end
end
