defmodule MeaningGameWeb.RoomLiveTest do
  @moduledoc """
  Two phones and a stage, the way they sit on the couch.

  Each phone is its own `conn`, because a `conn` is a browser here: the device
  token that finds a Seat lives in its session cookie.
  """
  use MeaningGameWeb.ConnCase, async: false

  import MeaningGame.RoomFixtures
  import Phoenix.LiveViewTest

  alias MeaningGame.Rooms

  defp join(view, name), do: view |> form("form", %{"name" => name}) |> render_submit()

  defp phone(slug), do: build_conn() |> get(~p"/r/#{slug}")

  # Just the page, without LiveView's own wrapper, whose session tokens are new
  # on every connection and say nothing about what the player sees.
  defp rendered_room(view), do: view |> element("#room") |> render()

  describe "joining" do
    test "a phone types a name and is in the Room" do
      slug = open_room()
      {:ok, melissa, html} = live(phone(slug))

      assert html =~ "Nobody yet"

      html = join(melissa, "Melissa")

      assert html =~ "You are"
      assert has_element?(melissa, "[data-seat]", "Melissa")
      refute has_element?(melissa, "form")
    end

    test "two phones and a stage all show the same roster" do
      slug = open_room()

      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      for view <- [melissa, jacob, stage] do
        assert has_element?(view, "[data-seat]", "Melissa")
        assert has_element?(view, "[data-seat]", "Jacob")
      end

      assert render(stage) =~ "All 2 seats taken"
    end

    test "each phone is told which Seat is its own, and the stage holds none" do
      slug = open_room()

      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      assert render(melissa) =~ "You are <span class=\"font-semibold\">Melissa</span>"
      assert render(jacob) =~ "You are <span class=\"font-semibold\">Jacob</span>"
      refute render(stage) =~ "You are"
    end

    test "a phone with no name typed is told to type one" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))

      assert join(melissa, "  ") =~ "Type a name first."
      assert has_element?(melissa, "form")
    end

    test "a phone arriving at a full Room is told so" do
      slug = open_room(seat_limit: 2)
      {:ok, _} = Rooms.join(slug, "Melissa", device_token())
      {:ok, _} = Rooms.join(slug, "Jacob", device_token())

      {:ok, ada, _} = live(phone(slug))

      assert join(ada, "Ada") =~ "Every seat is taken"
    end
  end

  describe "coming back" do
    test "reopening the URL lands in the same Seat with no name to retype" do
      slug = open_room()
      conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, melissa, _} = live(conn)
      join(melissa, "Melissa")

      # The tab is closed and the URL opened again on the same phone.
      {:ok, again, html} = live(get(conn, ~p"/r/#{slug}"))

      assert html =~ "You are"
      refute has_element?(again, "form")
      assert has_element?(again, "[data-seat]", "Melissa")
    end

    test "a different browser at the same URL is a different player" do
      slug = open_room(seat_limit: 3)
      {:ok, melissa, _} = live(phone(slug))
      join(melissa, "Melissa")

      {:ok, jacob, html} = live(phone(slug))

      assert has_element?(jacob, "form")
      assert html =~ "Melissa"
    end

    test "a phone whose socket dies mid-Room comes back to the identical view" do
      slug = open_room()
      conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, melissa, _} = live(conn)
      join(melissa, "Melissa")
      {:ok, _} = Rooms.join(slug, "Jacob", device_token())
      before = rendered_room(melissa)

      # The phone locks and the socket dies, taking the view process with it.
      Process.flag(:trap_exit, true)
      ref = Process.monitor(melissa.pid)
      Process.exit(melissa.pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _pid, :killed}

      # It wakes: same URL, same cookie, same view, nothing retyped.
      {:ok, again, _} = live(get(conn, ~p"/r/#{slug}"))

      assert rendered_room(again) == before
    end

    test "a phone waking from lock asks for the whole view again" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      join(melissa, "Melissa")

      {:ok, _} = Rooms.join(slug, "Jacob", device_token())

      html = render_hook(melissa, "resync", %{})

      assert html =~ "Melissa"
      assert html =~ "Jacob"
    end
  end

  describe "a URL with no Room behind it" do
    test "is a 404 rather than a Room conjured out of the typo" do
      assert_error_sent 404, fn -> get(build_conn(), "/r/NOT-A-SLUG") end
      assert_error_sent 404, fn -> get(build_conn(), "/r/NOT-A-SLUG/stage") end
    end
  end

  describe "the stage" do
    test "shows the URL a phone should open" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      assert has_element?(stage, "[data-role=join-url]", "/r/#{slug}")
    end

    test "the bare URL is the couch, on the phone and on the stage" do
      Rooms.ensure_started(Rooms.default_slug())
      on_exit(fn -> stop_default_room() end)

      assert {:ok, _phone, _} = live(build_conn(), ~p"/")
      assert {:ok, stage, _} = live(build_conn(), ~p"/stage")

      assert has_element?(stage, "[data-role=join-url]")
    end
  end

  # The default Room is the one Room without a slug of its own, so the test that
  # touches it has to put it away itself.
  defp stop_default_room do
    case GenServer.whereis(MeaningGame.Rooms.Server.via(Rooms.default_slug())) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(MeaningGame.Rooms.Supervisor, pid)
    end
  end
end
