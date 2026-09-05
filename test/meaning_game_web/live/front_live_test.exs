defmodule MeaningGameWeb.FrontLiveTest do
  @moduledoc """
  The door, from the outside: a Code to type, a Room to open, and the way back
  into a Room this phone is already in.

  Each `conn` is a browser, because the device token that finds a Seat lives in
  its session cookie.
  """
  use MeaningGameWeb.ConnCase, async: false

  import MeaningGame.RoomFixtures
  import Phoenix.LiveViewTest

  alias MeaningGame.Rooms

  defp type_code(view, code), do: view |> form("form", %{"code" => code}) |> render_submit()

  defp phone_at(slug), do: build_conn() |> get(~p"/r/#{slug}")

  defp join(view, name), do: view |> form("form", %{"name" => name}) |> render_submit()

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
      refute MeaningGame.Repo.get_by(MeaningGame.Rooms.Room, slug: "zzzz")
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
      join(view, "Melissa")

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
      join(view, "Melissa")

      {:ok, front, _} = live(get(phone, ~p"/"))

      assert {:error, {:live_redirect, %{to: to}}} =
               front |> element("[data-role=rejoin]") |> render_click()

      assert to == "/r/#{slug}"

      {:ok, back, html} = live(get(phone, to))

      assert html =~ "You are"
      assert has_element?(back, "[data-role=you]", "Melissa")
    end

    test "a phone that has sat nowhere is offered nothing to rejoin", %{conn: conn} do
      {:ok, front, _} = live(conn, ~p"/")

      refute has_element?(front, "[data-role=rejoin]")
    end
  end

  describe "New Room" do
    test "opens a Room of the chosen size and lands in it with the Code shown large",
         %{conn: conn} do
      {:ok, new, html} = live(conn, ~p"/new")

      assert html =~ "How many players?"
      assert has_element?(new, "select[name=players] option[value=\"4\"]")
      assert has_element?(new, "select[name=players] option[value=\"6\"]")
      refute has_element?(new, "select[name=players] option[value=\"7\"]")
      refute has_element?(new, "select[name=players] option[value=\"1\"]")

      assert {:error, {:live_redirect, %{to: to}}} =
               new |> form("form", %{"players" => "4"}) |> render_submit()

      "/r/" <> code = to
      on_exit(fn -> stop_room(code) end)

      {:ok, room, _} = live(conn, to)

      assert has_element?(room, "[data-role=code]", String.upcase(code))
      assert has_element?(room, "[data-role=join-url]", "/r/#{code}")
      assert Rooms.snapshot(code, nil).seat_limit == 4
    end

    test "defaults to the couch's two", %{conn: conn} do
      {:ok, new, _} = live(conn, ~p"/new")

      assert has_element?(new, "select[name=players] option[value=\"2\"][selected]")
    end

    test "the creator joins by name like everybody else", %{conn: conn} do
      {:ok, new, _} = live(conn, ~p"/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               new |> form("form", %{"players" => "2"}) |> render_submit()

      "/r/" <> code = to
      on_exit(fn -> stop_room(code) end)

      {:ok, room, _} = live(conn, to)

      assert has_element?(room, "input[name=name]")
      assert Rooms.snapshot(code, nil).seats == []
    end
  end

  describe "four phones at a table" do
    test "everyone types the Code and a name, and a fifth is turned away" do
      slug = open_room(seat_limit: 4)

      phones =
        for name <- ~w(Melissa Jacob Ada Ida) do
          {:ok, view, _} = live(phone_at(slug))
          join(view, name)
          view
        end

      for view <- phones do
        assert has_element?(view, "[data-role=open-seats]", "All 4 seats taken")
        assert has_element?(view, "[data-role=room-code]")
      end

      {:ok, fifth, _} = live(phone_at(slug))

      assert join(fifth, "Ola") =~ "Every seat is taken"
    end

    test "the Code and the URL are on every phone while Seats are open" do
      slug = open_room(seat_limit: 4)

      {:ok, view, _} = live(phone_at(slug))
      join(view, "Melissa")

      assert has_element?(view, "[data-role=code]", String.upcase(slug))

      # The Room's own URL, so a latecomer can be sent one thing rather than
      # a host and a Code to type into it.
      assert has_element?(view, "[data-role=join-url]", "/r/#{slug}")
      assert has_element?(view, "[data-role=open-seats]", "Waiting for 3 more")
    end
  end
end
