defmodule ThereishWeb.FrontLiveTest do
  @moduledoc """
  The door, from the outside: a Code to type, a Room to open, and the way back
  into a Room this phone is already in.

  Each `conn` is a browser, because the device token that finds a Seat lives in
  its session cookie.
  """
  use ThereishWeb.ConnCase, async: false

  import Thereish.RoomFixtures
  import Phoenix.LiveViewTest

  alias Thereish.Rooms

  defp type_code(view, code), do: view |> form("form", %{"code" => code}) |> render_submit()

  defp phone_at(slug), do: build_conn() |> get(~p"/r/#{slug}")

  defp join(view, name),
    do: view |> form("form[phx-submit=join]", %{"name" => name}) |> render_submit()

  describe "the front page" do
    test "asks for a Code and offers a New Room", %{conn: conn} do
      {:ok, front, html} = live(conn, ~p"/")

      assert page_title(front) =~ "Thereish"
      assert has_element?(front, "h1", "Thereish")
      assert html =~ "Code"
      assert has_element?(front, "input[name=code]")
      assert has_element?(front, "[data-role=new-room]")
    end

    test "a Code opens its Room, in whatever case it was typed", %{conn: conn} do
      slug = open_room()

      {:ok, front, _} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: to}}} = type_code(front, String.upcase(slug))
      assert to == "/r/#{slug}"
    end

    test "a Code no Room has is said plainly, and conjures nothing", %{conn: conn} do
      {:ok, front, _} = live(conn, ~p"/")

      html = type_code(front, "zzzz")

      assert html =~ "No Room has the Code ZZZZ"
      refute Thereish.Repo.get_by(Thereish.Rooms.Room, slug: "zzzz")
    end

    test "an empty box asks for the word rather than opening anything", %{conn: conn} do
      {:ok, front, _} = live(conn, ~p"/")

      assert type_code(front, "  ") =~ "Type the Code you were told"
    end

    test "offers a one-tap way back into every Room this phone sits in" do
      first = open_room()
      second = open_room()
      phone = build_conn() |> get(~p"/r/#{first}")

      {:ok, view, _} = live(phone)
      join(view, "Mara")

      {:ok, view, _} = live(get(phone, ~p"/r/#{second}"))
      join(view, "Mel")

      {:ok, front, _} = live(get(phone, ~p"/"))

      assert has_element?(front, "[data-role=rejoin][data-code=#{first}]", String.upcase(first))
      assert has_element?(front, "[data-role=rejoin][data-code=#{second}]", "as Mel")

      # Newest Seat first: the Room this phone was in last is the one it is
      # most likely to be going back to.
      html = render(front)
      {newest_at, _} = :binary.match(html, String.upcase(second))
      {oldest_at, _} = :binary.match(html, String.upcase(first))
      assert newest_at < oldest_at
    end

    test "a rejoin link lands a phone back in its own Seat" do
      slug = open_room()
      phone = build_conn() |> get(~p"/r/#{slug}")

      {:ok, view, _} = live(phone)
      join(view, "Mara")

      {:ok, front, _} = live(get(phone, ~p"/"))

      assert {:error, {:live_redirect, %{to: to}}} =
               front |> element("[data-role=rejoin]") |> render_click()

      assert to == "/r/#{slug}"

      {:ok, back, html} = live(get(phone, to))

      assert html =~ "You are"
      assert has_element?(back, "[data-role=you]", "Mara")
    end

    test "a phone that has sat nowhere is offered nothing to rejoin", %{conn: conn} do
      {:ok, front, _} = live(conn, ~p"/")

      refute has_element?(front, "[data-role=rejoin]")
    end

    test "rejoin link renders the Room's quip when present, and nothing when absent" do
      first = open_room(quip: "A room with a quip.")
      second = open_room(quip: nil)
      phone = build_conn() |> get(~p"/r/#{first}")

      {:ok, view, _} = live(phone)
      join(view, "Mara")

      {:ok, view, _} = live(get(phone, ~p"/r/#{second}"))
      join(view, "Mel")

      {:ok, front, _} = live(get(phone, ~p"/"))

      assert has_element?(front, "[data-role=rejoin-quip]", "A room with a quip.")
      html = render(front)
      assert [_match] = Regex.scan(~r/data-role="rejoin-quip"/, html)
    end
  end

  describe "New Room" do
    test "opens a count-free Room at seat cap and lands in it with the Code shown large",
         %{conn: conn} do
      {:ok, new, _html} = live(conn, ~p"/new")

      refute has_element?(new, "select[name=players]")
      refute has_element?(new, "[data-role=full-table-switch]")
      assert has_element?(new, "[data-role=open-room]")

      assert {:error, {:live_redirect, %{to: to}}} =
               new |> form("form") |> render_submit()

      "/r/" <> code = to
      on_exit(fn -> stop_room(code) end)

      {:ok, room, _} = live(conn, to)

      assert has_element?(room, "[data-role=code]", String.upcase(code))
      assert has_element?(room, "[data-role=join-url]", "/r/#{code}")
      assert Rooms.snapshot(code, nil).seat_limit == Thereish.Steward.seat_cap()
    end

    test "the creator joins by name like everybody else", %{conn: conn} do
      {:ok, new, _} = live(conn, ~p"/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               new |> form("form") |> render_submit()

      "/r/" <> code = to
      on_exit(fn -> stop_room(code) end)

      {:ok, room, _} = live(conn, to)

      assert has_element?(room, "input[name=name]")
      assert Rooms.snapshot(code, nil).seats == []
    end

    test "room creation is refused with 'Give it a minute' when rate limited per device" do
      prev_config = Application.get_env(:thereish, :room_creation_rate_limit)

      Application.put_env(:thereish, :room_creation_rate_limit,
        per_device: 2,
        per_address: 100,
        window_seconds: 3600
      )

      on_exit(fn ->
        if prev_config,
          do: Application.put_env(:thereish, :room_creation_rate_limit, prev_config),
          else: Application.delete_env(:thereish, :room_creation_rate_limit)
      end)

      Thereish.Rooms.RateLimit.reset()

      phone = build_conn() |> get(~p"/new")
      {:ok, new1, _} = live(phone)
      {:error, {:live_redirect, %{to: to1}}} = new1 |> form("form") |> render_submit()
      "/r/" <> code1 = to1
      on_exit(fn -> stop_room(code1) end)

      phone = get(phone, ~p"/new")
      {:ok, new2, _} = live(phone)
      html = new2 |> form("form") |> render_submit()
      assert html =~ "Give it a minute"
      assert has_element?(new2, "[data-role=error]", "Give it a minute")
    end

    test "room creation is refused with 'Give it a minute' when rate limited per remote address" do
      prev_config = Application.get_env(:thereish, :room_creation_rate_limit)

      Application.put_env(:thereish, :room_creation_rate_limit,
        per_device: 100,
        per_address: 2,
        window_seconds: 3600
      )

      on_exit(fn ->
        if prev_config,
          do: Application.put_env(:thereish, :room_creation_rate_limit, prev_config),
          else: Application.delete_env(:thereish, :room_creation_rate_limit)
      end)

      Thereish.Rooms.RateLimit.reset()

      phone1 = build_conn() |> get(~p"/new")
      {:ok, new1, _} = live(phone1)
      {:error, {:live_redirect, %{to: to1}}} = new1 |> form("form") |> render_submit()
      "/r/" <> code1 = to1
      on_exit(fn -> stop_room(code1) end)

      phone2 = build_conn() |> get(~p"/new")
      {:ok, new2, _} = live(phone2)
      html = new2 |> form("form") |> render_submit()
      assert html =~ "Give it a minute"
      assert has_element?(new2, "[data-role=error]", "Give it a minute")
    end
  end

  describe "four phones at a table" do
    test "everyone types the Code and a name, and a fifth is turned away" do
      slug = open_room(seat_limit: 4)

      phones =
        for name <- ~w(Mara Jacob Ada Ida) do
          {:ok, view, _} = live(phone_at(slug))
          join(view, name)
          view
        end

      for view <- phones do
        refute has_element?(view, "[data-role=open-seats]")
        assert has_element?(view, "[data-role=room-code]")
      end

      {:ok, fifth, _} = live(phone_at(slug))

      assert join(fifth, "Ola") =~ "Every seat is taken"
    end

    test "the Code and the URL are on every phone while Seats are open" do
      slug = open_room(seat_limit: 4)

      {:ok, view, _} = live(phone_at(slug))
      join(view, "Mara")

      assert has_element?(view, "[data-role=code]", String.upcase(slug))

      # The Room's own URL, so a latecomer can be sent one thing rather than
      # a host and a Code to type into it.
      assert has_element?(view, "[data-role=join-url]", "/r/#{slug}")
      assert has_element?(view, "[data-role=open-seats]", "Waiting for 1 more")
    end
  end
end
