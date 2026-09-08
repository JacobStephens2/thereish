defmodule ThereishWeb.RoomLiveTest do
  @moduledoc """
  Two phones and a stage, the way they sit on the couch.

  Each phone is its own `conn`, because a `conn` is a browser here: the device
  token that finds a Seat lives in its session cookie.
  """
  use ThereishWeb.ConnCase, async: false

  import Thereish.RoomFixtures
  import Phoenix.LiveViewTest

  alias Thereish.Rooms

  defp join(view, name), do: view |> form("form", %{"name" => name}) |> render_submit()

  defp commit(view, bridge) do
    view |> form("[data-role=bridge-form]", %{"bridge" => bridge}) |> render_submit()
  end

  defp give_setting(view, give) do
    view |> form("[data-role=setting-form]", %{"give" => give}) |> render_submit()
  end

  defp play_to_bridging(melissa, jacob, slug, give1 \\ "setting one", give2 \\ "setting two") do
    give_setting(melissa, give1)
    give_setting(jacob, give2)
    await_phase(slug, :bridging)
    eventually(fn -> has_element?(melissa, "[data-role=bridge-form]") end)
    eventually(fn -> has_element?(jacob, "[data-role=bridge-form]") end)
  end

  defp phone(slug), do: build_conn() |> get(~p"/r/#{slug}")

  # The reveal arrives on its own time — a beat, then a verdict — so a view
  # waits for it here the way a phone on the couch does.
  defp await_reveal_on(view) do
    eventually(
      fn -> has_element?(view, "[data-role=reveal]") && render(view) end,
      "the reveal never arrived on this view"
    )
  end

  # Just the page, without LiveView's own wrapper, whose session tokens are new
  # on every connection and say nothing about what the player sees.
  defp rendered_room(view), do: view |> element("#room") |> render()

  defp assert_order(html, patterns) when is_list(patterns) do
    indices =
      Enum.map(patterns, fn pattern ->
        case :binary.match(html, pattern) do
          {idx, _} -> idx
          :nomatch -> flunk("Expected to find #{inspect(pattern)} in rendered output")
        end
      end)

    Enum.chunk_every(indices, 2, 1, :discard)
    |> Enum.each(fn [a, b] -> assert a < b end)
  end

  describe "joining" do
    test "a phone types a name and is in the Room" do
      slug = open_room()
      {:ok, melissa, html} = live(phone(slug))

      assert html =~ "Nobody yet"

      # In :waiting, speaker bar and Code card render above the join form
      assert_order(html, [
        ~s(data-role="speaker-bar"),
        ~s(data-role="room-code"),
        ~s(phx-submit="join")
      ])

      html = join(melissa, "Melissa")

      assert html =~ "You are"
      assert has_element?(melissa, "[data-seat]", "Melissa")
      refute has_element?(melissa, "form")

      # After joining in :waiting, Code card renders before "In the Room"
      assert_order(html, [~s(data-role="room-code"), "In the Room"])
    end

    test "Code card renders the Room's quip beneath the Code when present, and nothing when absent" do
      slug_with_quip = open_room(quip: "A gentle word for quiet hours.")
      {:ok, view, _html} = live(phone(slug_with_quip))
      assert has_element?(view, "[data-role=code-quip]", "A gentle word for quiet hours.")

      slug_no_quip = open_room(quip: nil)
      {:ok, view_no_quip, _html} = live(phone(slug_no_quip))
      refute has_element?(view_no_quip, "[data-role=code-quip]")
    end

    test "Stage header renders the Room's quip beside the join line when present, and nothing when absent" do
      slug_with_quip = open_room(quip: "A gentle word for quiet hours.")
      {:ok, stage, _html} = live(build_conn(), ~p"/r/#{slug_with_quip}/stage")
      assert has_element?(stage, "[data-role=stage-quip]", "A gentle word for quiet hours.")

      slug_no_quip = open_room(quip: nil)
      {:ok, stage_no_quip, _html} = live(build_conn(), ~p"/r/#{slug_no_quip}/stage")
      refute has_element?(stage_no_quip, "[data-role=stage-quip]")
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
    test "a browser that already holds a Seat is back in it without typing" do
      slug = open_room()
      conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, melissa, _} = live(conn)
      join(melissa, "Melissa")

      # Reload: same cookie, no form, name already up.
      {:ok, again, _} = live(get(conn, ~p"/r/#{slug}"))

      assert render(again) =~ "You are <span class=\"font-semibold\">Melissa</span>"
      refute has_element?(again, "form")
    end

    test "a device token that belongs to another Room cannot claim a Seat" do
      room_a = open_room()
      room_b = open_room()

      conn = get(build_conn(), ~p"/r/#{room_a}")
      {:ok, view, _} = live(conn)
      join(view, "Melissa")

      # Same browser visits Room B. It does not own a Seat there, so it is
      # asked for a name like anyone else.
      {:ok, in_b, _} = live(get(conn, ~p"/r/#{room_b}"))

      assert has_element?(in_b, "form")
      refute render(in_b) =~ "You are"
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

  describe "playing a Page" do
    setup do
      slug = open_room()
      melissa_conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, melissa, _} = live(melissa_conn)
      {:ok, jacob, _} = live(phone(slug))

      join(melissa, "Melissa")
      join(jacob, "Jacob")
      play_to_bridging(melissa, jacob, slug)

      %{slug: slug, melissa: melissa, melissa_conn: melissa_conn, jacob: jacob}
    end

    test "the Bookends are up on both phones and the stage", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")

      for view <- [ctx.melissa, ctx.jacob, stage] do
        assert has_element?(view, "[data-role=bookends-caption]", "Bookends")
        assert has_element?(view, "[data-role=bookends]", "lantern")
        assert has_element?(view, "[data-role=bookends]", "harbour")
      end
    end

    test "during bridging, the Attempt line, Bookends and Bridge form come first and speaker bar and Code card are below",
         ctx do
      html = render(ctx.melissa)

      assert_order(html, [
        ~s(data-role="attempt"),
        ~s(data-role="bookends"),
        ~s(data-role="bridge-form"),
        ~s(data-role="speaker-bar"),
        ~s(data-role="room-code"),
        "In the Room"
      ])
    end

    test "a phone with no Seat mid-Page renders join form first, then speaker bar and Code card before In the Room",
         ctx do
      {:ok, onlooker, _} = live(phone(ctx.slug))
      html = render(onlooker)

      assert_order(html, [
        ~s(phx-submit="join"),
        ~s(data-role="speaker-bar"),
        ~s(data-role="room-code"),
        "In the Room"
      ])
    end

    test "an illegal bridge is caught on the phone before commit and on commit", ctx do
      assert has_element?(ctx.melissa, "label", "Your bridge")

      ctx.melissa
      |> form("[data-role=bridge-form]", %{"bridge" => "lanterns"})
      |> render_change()

      assert has_element?(
               ctx.melissa,
               "[data-role=bridge-error]",
               "\"lanterns\" shares a root with \"lantern\"."
             )

      commit(ctx.melissa, "lanterns")

      assert has_element?(
               ctx.melissa,
               "[data-role=bridge-error]",
               "\"lanterns\" shares a root with \"lantern\"."
             )

      assert has_element?(ctx.melissa, "[data-role=bridge-form]")
      refute has_element?(ctx.melissa, "[data-role=your-bridge]")

      commit(ctx.melissa, "beacon")
      assert has_element?(ctx.melissa, "[data-role=your-bridge]", "Your bridge: beacon")
      refute has_element?(ctx.melissa, "[data-role=bridge-form]")
    end

    test "a Bridge is written on one phone and seen on none of the others", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")

      commit(ctx.melissa, "cairn")

      assert has_element?(ctx.melissa, "[data-role=your-bridge]", "cairn")
      refute has_element?(ctx.melissa, "[data-role=bridge-form]")

      refute render(ctx.jacob) =~ "cairn"
      refute render(stage) =~ "cairn"

      # What the other phone and the stage are told is that she is done, and
      # nothing else.
      for view <- [ctx.jacob, stage] do
        assert has_element?(view, "[data-seat][data-committed=true]", "Melissa")
        assert has_element?(view, "[data-seat][data-committed=false]", "Jacob")
      end

      assert has_element?(ctx.jacob, "[data-role=bridge-form]")
    end

    test "the last commit reveals both Bridges, graded, on both phones", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- [ctx.melissa, ctx.jacob] do
        html = await_reveal_on(view)

        assert html =~ "cairn"
        assert html =~ "cairo"
        assert has_element?(view, "[data-role=closeness]", "80")
        assert has_element?(view, "[data-role=band]", "almost")
        refute has_element?(view, "[data-role=reasoning]")
        refute render(view) =~ "share 4 letters"
        # The joke is about the two words they actually wrote, and it is on
        # every screen the number is on (ADR-0005).
        assert has_element?(view, "[data-role=quip]", "\"cairn\" and \"cairo\"")
      end
    end

    test "a slow Assayer is narrated on every screen rather than left as a hang", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")
      escalation(slow: 50, unavailable: 700)
      steward(delay_ms: 5_000)

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- [ctx.melissa, ctx.jacob, stage] do
        assert eventually(fn -> has_element?(view, "[data-role=phase][data-step=slow]") end)
      end

      # And when it never answers, the game says so and the call is theirs.
      html = await_reveal_on(stage)

      assert html =~ "No verdict"
      assert html =~ "yours to call"
    end

    test "a miss is graded and said out loud, same as a Meld", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "beacon")

      html = await_reveal_on(ctx.melissa)

      assert html =~ "cairn"
      assert html =~ "beacon"
      assert has_element?(ctx.melissa, "[data-role=closeness]", "0")
      assert has_element?(ctx.melissa, "[data-role=band]", "miss")
    end

    test "a phone that locked through the reveal wakes into it", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")
      await_reveal_on(ctx.jacob)

      Process.flag(:trap_exit, true)
      ref = Process.monitor(ctx.melissa.pid)
      Process.exit(ctx.melissa.pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _pid, :killed}

      {:ok, again, html} = live(get(ctx.melissa_conn, ~p"/r/#{ctx.slug}"))

      assert html =~ "cairn"
      assert has_element?(again, "[data-role=closeness]", "80")
    end

    test "an empty Bridge is a nudge rather than a commit", ctx do
      assert commit(ctx.melissa, "   ") =~ "Write a word first."
      assert has_element?(ctx.melissa, "[data-role=bridge-form]")
    end

    test "the Assayer having no verdict is said plainly", ctx do
      steward(mode: :unavailable)

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      html = await_reveal_on(ctx.melissa)

      assert html =~ "cairn"
      assert html =~ "No verdict"
      refute has_element?(ctx.melissa, "[data-role=closeness]")
    end
  end

  describe "a Page that misses, and a Page that ends" do
    setup do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))

      join(melissa, "Melissa")
      join(jacob, "Jacob")
      play_to_bridging(melissa, jacob, slug)

      %{
        slug: slug,
        melissa: melissa,
        jacob: jacob,
        screens: [melissa, jacob]
      }
    end

    defp press(view, role), do: view |> element("[data-role=#{role}]") |> render_click()

    defp miss(ctx, melissa_bridge \\ "cairn", jacob_bridge \\ "beacon") do
      commit(ctx.melissa, melissa_bridge)
      commit(ctx.jacob, jacob_bridge)

      await_reveal_on(ctx.melissa)
    end

    test "the failed Bridges become the next attempt's Bookends, on every screen", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")

      miss(ctx)

      # The tap says what it is going to do before it does it.
      assert has_element?(ctx.melissa, "[data-role=again]", "cairn and beacon")
      assert has_element?(stage, "[data-role=carry-forward]")
      refute has_element?(stage, "[data-role=again]")

      press(ctx.melissa, "again")

      for view <- [ctx.melissa, ctx.jacob, stage] do
        assert has_element?(view, "[data-role=bookends]", "cairn")
        assert has_element?(view, "[data-role=bookends]", "beacon")
        assert has_element?(view, "[data-role=attempt]", "Attempt 2 of 5")
        refute has_element?(view, "[data-role=reveal]")
      end

      assert has_element?(ctx.jacob, "[data-role=bridge-form]")
    end

    test "a Meld is the end of the Page and says so", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairns")
      await_reveal_on(ctx.melissa)

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=ending-line]", "melded first try")
        # The grade the reveal landed on is still up under it.
        assert has_element?(view, "[data-role=closeness]", "91")
        refute has_element?(view, "[data-role=again]")
        refute has_element?(view, "[data-role=attempt]")
      end

      assert has_element?(ctx.melissa, "[data-role=one-more]")
    end

    test "the last attempt ends it unmelded, with the arc of how it got there", ctx do
      attempt_cap(2)

      miss(ctx)
      press(ctx.jacob, "again")
      miss(ctx, "wharf", "gantry")

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=ending-line]", "2 attempts")
        assert has_element?(view, "[data-role=arc] [data-attempt='1']", "lantern + harbour")
        assert has_element?(view, "[data-role=arc] [data-attempt='1']", "cairn · beacon")
        refute has_element?(view, "[data-role=again]")
      end
    end

    test "one more? is one tap, and returns to giving for both of them", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairns")
      await_reveal_on(ctx.melissa)

      press(ctx.melissa, "one-more")

      assert has_element?(ctx.melissa, "[data-role=setting-form]")
      assert has_element?(ctx.jacob, "[data-role=setting-form]")

      # Prefill shows last give
      assert render(ctx.melissa) =~ "value=\"setting one\""
      assert render(ctx.jacob) =~ "value=\"setting two\""

      # Submitting new settings begins bridging again
      play_to_bridging(ctx.melissa, ctx.jacob, ctx.slug, "fresh one", "fresh two")

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=attempt]", "Attempt 1 of 5")
        refute has_element?(view, "[data-role=ending]")
        refute has_element?(view, "[data-role=reveal]")
      end

      assert has_element?(ctx.jacob, "[data-role=bridge-form]")
      assert has_element?(ctx.jacob, "[data-seat]", "Melissa")
    end

    test "both of them tapping at once is one next attempt, not two", ctx do
      miss(ctx)

      press(ctx.melissa, "again")

      # Jacob's thumb was already on the way down. The event is pushed rather
      # than clicked, because his button is gone from the screen by now and the
      # tap that outran the re-render is the whole point.
      render_click(ctx.jacob, "next_attempt", %{})

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=attempt]", "Attempt 2 of 5")
        assert has_element?(view, "[data-role=bookends]", "cairn")
      end
    end
  end

  describe "a URL with no Room behind it" do
    test "is a 404 rather than a Room conjured out of the typo" do
      assert_error_sent 404, fn -> get(build_conn(), "/r/Not_A_Code") end
      assert_error_sent 404, fn -> get(build_conn(), "/r/Not_A_Code/stage") end

      # A word shaped exactly like a Code, that nobody opened a Room under, is
      # still nothing: visiting a path has stopped creating Rooms.
      assert_error_sent 404, fn -> get(build_conn(), "/r/nobodyshome") end
      refute Thereish.Repo.get_by(Thereish.Rooms.Room, slug: "nobodyshome")
    end
  end

  describe "the stage" do
    test "shows one verdict for the whole table when there are more than two of them" do
      slug = open_room(seat_limit: 3)
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      # Melissa and Jacob land on the same word. Ada is somewhere else. Nobody
      # writes anything until the third of them is in the Room.
      phones =
        for {name, bridge} <- [{"Melissa", "cairn"}, {"Jacob", "cairo"}, {"Ada", "beacon"}] do
          {:ok, view, _} = live(phone(slug))
          join(view, name)
          {view, bridge}
        end

      for {view, name} <- Enum.zip(Enum.map(phones, &elem(&1, 0)), ~w(Melissa Jacob Ada)) do
        give_setting(view, "setting #{name}")
      end

      await_phase(slug, :bridging)

      for {view, bridge} <- phones, do: commit(view, bridge)

      await_reveal_on(stage)

      # Every Bridge, one number in one band, one quip, one line of reasoning,
      # and the two words the table is sent to next (ADR-0010).
      for bridge <- ~w(cairn cairo beacon) do
        assert has_element?(stage, "[data-bridge]", bridge)
      end

      assert has_element?(stage, "[data-role=closeness]")
      assert has_element?(stage, "[data-role=quip]")
      refute has_element?(stage, "[data-role=reasoning]")
      refute has_element?(stage, "[data-role=furthest]")
      refute has_element?(stage, "[data-role=pair]")

      # Two of three landing on one word is not the table being of one mind.
      assert has_element?(stage, "[data-role=band]", "miss")

      # Structure and position: header -> attempt -> bookends -> bridges -> closeness -> quip -> foot strip
      html = render(stage)

      assert_order(html, [
        "<header",
        ~s(data-role="attempt"),
        ~s(data-role="bookends"),
        ~s(data-role="comparison"),
        ~s(data-role="closeness"),
        ~s(data-role="quip"),
        ~s(data-role="stage-foot")
      ])
    end

    test "shows the URL a phone should open" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      assert has_element?(stage, "[data-role=join-url]", "/r/#{slug}")
    end

    test "heading, controls, and chronicle link share the header; join URL and roster share the foot" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      html = render(stage)

      # Header has Thereish heading, controls, and Chronicle link, but no join URL
      assert has_element?(stage, "header h1", "Thereish")
      assert has_element?(stage, "header a[href*='chronicle']", "The Chronicle")
      refute has_element?(stage, "header [data-role=join-url]")

      # Footer strip has join URL and roster together; no separate "In the Room" heading
      assert has_element?(stage, "footer [data-role=join-url]", "/r/#{slug}")
      assert has_element?(stage, "[data-role=stage-foot] [data-role=join-url]", "/r/#{slug}")
      assert has_element?(stage, "footer [data-role=roster]")
      assert has_element?(stage, "footer [data-seat]", "Melissa")
      assert has_element?(stage, "footer [data-seat]", "Jacob")

      assert has_element?(
               stage,
               "[data-role=stage-foot] [data-role=open-seats]",
               "All 2 seats taken"
             )

      refute has_element?(stage, "h2", "In the Room")
      refute html =~ "In the Room"

      # Order: header -> play content -> stage-foot
      assert_order(html, ["<header", ~s(data-role="stage-foot")])
    end
  end

  describe "overruling from the couch" do
    test "two phones and a stage: propose, agree to a meld, and chain to next page" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")
      play_to_bridging(melissa, jacob, slug)

      # "cairn" and "beacon" share no prefix -> fake assayer grades 0
      commit(melissa, "cairn")
      commit(jacob, "beacon")

      await_reveal_on(melissa)
      await_reveal_on(jacob)
      await_reveal_on(stage)

      refute has_element?(melissa, "[data-role=closeness]")
      assert has_element?(stage, "[data-role=closeness]", "0")

      # Melissa proposes an overrule
      melissa |> element("[data-role=propose-overrule]") |> render_click()

      # Visible on all three views while pending
      assert render(melissa) =~ "You proposed an overrule"

      assert has_element?(
               jacob,
               "[data-role=overrule-pending]",
               "Melissa proposed overruling this grade to a Meld"
             )

      assert has_element?(stage, "[data-role=overrule-pending]", "Melissa proposed an overrule")
      assert has_element?(jacob, "[data-role=agree-overrule]")
      assert has_element?(jacob, "[data-role=decline-overrule]")

      # Grade remains 0 on stage; phones remain quiet
      refute has_element?(melissa, "[data-role=closeness]")
      refute has_element?(jacob, "[data-role=closeness]")
      assert has_element?(stage, "[data-role=closeness]", "0")

      # Jacob agrees
      jacob |> element("[data-role=agree-overrule]") |> render_click()

      # Overrule takes effect: stage shows 90 (meld floor), all three show banner, phones quiet
      assert has_element?(stage, "[data-role=closeness]", "90")
      assert has_element?(stage, "[data-role=band]", "meld")

      for view <- [melissa, jacob, stage] do
        assert render(view) =~ "Overruled jointly"
      end

      refute has_element?(melissa, "[data-role=closeness]")
      refute has_element?(jacob, "[data-role=closeness]")

      # Ending shows it melded
      assert has_element?(stage, "[data-role=ending-line]", "melded first try")

      # "One more?" starts the next page cleanly
      assert has_element?(melissa, "[data-role=one-more]")
      melissa |> element("[data-role=one-more]") |> render_click()

      assert has_element?(melissa, "[data-role=setting-form]")
      assert has_element?(jacob, "[data-role=setting-form]")
      refute render(melissa) =~ "Overruled"
    end

    test "declining an overrule leaves the grade untouched" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))

      join(melissa, "Melissa")
      join(jacob, "Jacob")
      play_to_bridging(melissa, jacob, slug)

      commit(melissa, "cairn")
      commit(jacob, "beacon")

      await_reveal_on(melissa)
      await_reveal_on(jacob)

      melissa |> element("[data-role=propose-overrule]") |> render_click()
      assert has_element?(jacob, "[data-role=decline-overrule]")

      jacob |> element("[data-role=decline-overrule]") |> render_click()

      refute render(melissa) =~ "proposed an overrule"
      refute render(jacob) =~ "proposed an overrule"
      assert has_element?(melissa, "[data-role=closeness]", "0")
      assert has_element?(melissa, "[data-role=again]")
    end
  end

  describe "the reveal performance (Ticket 10)" do
    setup do
      slug = open_room()
      melissa_conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, melissa, _} = live(melissa_conn)
      {:ok, jacob, _} = live(phone(slug))

      join(melissa, "Melissa")
      join(jacob, "Jacob")
      play_to_bridging(melissa, jacob, slug)

      %{
        slug: slug,
        melissa: melissa,
        jacob: jacob,
        screens: [melissa, jacob]
      }
    end

    test "the 2.5s beat is visibly a beat, not a spinner, on both phones and the stage", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")
      beat(500)

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- [ctx.melissa, ctx.jacob, stage] do
        assert has_element?(view, "[data-role=beat-meter]")
        refute render(view) =~ "loading-spinner"
        refute render(view) =~ "spinner"
      end

      await_reveal_on(stage)
    end

    test "reveal lands: side-by-side comparison first, climbing number, quip punchline, and phone vs stage split",
         ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairns")

      for view <- ctx.screens do
        await_reveal_on(view)
        html = render(view)
        assert has_element?(view, "[data-role=comparison]")
        assert has_element?(view, "[data-role=closeness]", "91")
        assert has_element?(view, "[data-role=band]", "meld")
        assert html =~ "ClimbNumber"
        refute has_element?(view, "[data-role=reasoning]")
        refute html =~ "reasoning"
        assert has_element?(view, "[data-role=quip]")
        assert has_element?(view, "[data-arrival=meld]")
        refute html =~ "One mind"
        refute has_element?(view, "[data-role=furthest]")

        # Order within reveal: comparison -> closeness -> quip
        assert_order(html, [
          ~s(data-role="comparison"),
          ~s(data-role="closeness-display"),
          ~s(data-role="quip")
        ])
      end

      # Phone distinguishes your bridge with (you)
      assert has_element?(ctx.melissa, "[data-bridge][data-you=true]", "Melissa")
      assert has_element?(ctx.melissa, "[data-bridge][data-you=false]", "Jacob")

      # Code card renders after reveal and controls, before In the Room and footer
      phone_html = render(ctx.melissa)

      assert_order(phone_html, [
        ~s(data-role="reveal"),
        ~s(data-role="speaker-bar"),
        ~s(data-role="room-code"),
        "In the Room",
        "<footer"
      ])

      assert has_element?(ctx.melissa, "footer [data-role=you]", "Melissa")
      assert has_element?(ctx.melissa, "footer h1", "Thereish")
      assert has_element?(ctx.melissa, "footer a", "The Chronicle")

      # Stage has public stage mode and no private (you) attribution
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")
      assert has_element?(stage, "header h1", "Thereish")
      assert has_element?(stage, "[data-mode=stage]")
      refute has_element?(stage, "[data-bridge][data-you=true]")
    end

    test "an almost grade lands in the almost band and next attempt is offered", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- ctx.screens do
        await_reveal_on(view)
        assert has_element?(view, "[data-role=comparison]")
        assert has_element?(view, "[data-role=closeness]", "80")
        assert has_element?(view, "[data-role=band]", "almost")
        assert has_element?(view, "[data-arrival=almost]")
        refute has_element?(view, "[data-role=ending-line]")
      end

      for phone <- [ctx.melissa, ctx.jacob] do
        assert has_element?(phone, "[data-role=again]")
      end
    end

    test "a miss is staged as a shared comedy deadpan joke, not an error sting", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "beacon")

      for view <- ctx.screens do
        await_reveal_on(view)
        assert has_element?(view, "[data-arrival=miss]")
        assert has_element?(view, "[data-role=closeness]", "0")
        assert has_element?(view, "[data-role=band]", "miss")
        refute render(view) =~ "alert-error"
        refute render(view) =~ "text-error"
      end
    end

    test "the 10-second no-verdict path is staged as deliberate handover rather than broken",
         ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")
      steward(mode: :unavailable)

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      await_reveal_on(stage)

      assert has_element?(stage, "[data-role=no-verdict]")
      assert render(stage) =~ "The Assayer steps aside"
      assert render(stage) =~ "No verdict. This one is yours to call."
      assert has_element?(ctx.melissa, "[data-role=propose-overrule]")
    end
  end

  describe "the fairness tap at the reveal (ticket 11)" do
    setup do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      play_to_bridging(melissa, jacob, slug)

      commit(melissa, "cairn")
      commit(jacob, "cairns")

      await_reveal_on(melissa)
      await_reveal_on(jacob)
      await_reveal_on(stage)

      %{slug: slug, melissa: melissa, jacob: jacob, stage: stage}
    end

    test "three taps appear on each phone at the reveal, but not on the stage", ctx do
      for phone <- [ctx.melissa, ctx.jacob] do
        assert has_element?(phone, "[data-role=fairness-controls]")
        assert has_element?(phone, "[data-role=tap-fair]", "Fair")
        assert has_element?(phone, "[data-role=tap-too-kind]", "Too kind")
        assert has_element?(phone, "[data-role=tap-too-harsh]", "Too harsh")
      end

      # Stage holds no seat so it renders no fairness buttons
      refute has_element?(ctx.stage, "[data-role=fairness-controls]")
    end

    test "tapping persists the label and highlights the selection per Seat", ctx do
      # Melissa taps fair
      ctx.melissa |> element("[data-role=tap-fair]") |> render_click()

      assert has_element?(ctx.melissa, "[data-role=tap-fair].btn-primary")
      assert has_element?(ctx.melissa, "[data-role=your-tap]")
      assert has_element?(ctx.melissa, "[data-role=seat-tap]", "fair")
      refute has_element?(ctx.jacob, "[data-role=tap-fair].btn-primary")
      refute has_element?(ctx.jacob, "[data-role=your-tap]")

      # Jacob disagrees and taps too_harsh
      ctx.jacob |> element("[data-role=tap-too-harsh]") |> render_click()

      assert has_element?(ctx.jacob, "[data-role=tap-too-harsh].btn-warning")
      assert has_element?(ctx.jacob, "[data-role=your-tap]")
      assert has_element?(ctx.jacob, "[data-role=seat-tap]", "too harsh")
      assert has_element?(ctx.melissa, "[data-role=tap-fair].btn-primary")
      assert has_element?(ctx.melissa, "[data-role=your-tap]")

      # Both rows persisted in Chronicle
      room = Thereish.Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)
      taps = Thereish.Chronicle.fairness_taps(room.id)
      assert length(taps) == 2
      assert Enum.map(taps, & &1.label) |> Enum.sort() == ["fair", "too_harsh"]
    end

    test "tapping never blocks or delays the next attempt", ctx do
      ctx.melissa |> element("[data-role=tap-fair]") |> render_click()

      # Next page / again button is present and usable immediately
      assert has_element?(ctx.melissa, "[data-role=one-more]")
      ctx.melissa |> element("[data-role=one-more]") |> render_click()

      await_phase(ctx.slug, :giving)
      eventually(fn -> has_element?(ctx.melissa, "[data-role=setting-form]") end)
    end
  end

  describe "tapping bookends at closed (ticket 08)" do
    setup do
      slug = open_room()

      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      play_to_bridging(melissa, jacob, slug)

      commit(melissa, "cairn")
      commit(jacob, "cairn")
      await_reveal_on(melissa)
      await_reveal_on(jacob)
      await_phase(slug, :closed)

      %{slug: slug, melissa: melissa, jacob: jacob, stage: stage}
    end

    test "each seat can tap flat, fine, or great on phone at closed, and it is replaceable",
         ctx do
      # Stage does NOT show bookends tap controls
      refute has_element?(ctx.stage, "[data-role=bookends-controls]")

      # Phones show bookends tap controls at closed
      assert has_element?(ctx.melissa, "[data-role=bookends-controls]")
      assert has_element?(ctx.melissa, "[data-role=tap-flat]")
      assert has_element?(ctx.melissa, "[data-role=tap-fine]")
      assert has_element?(ctx.melissa, "[data-role=tap-great]")

      # Melissa taps great
      ctx.melissa |> element("[data-role=tap-great]") |> render_click()

      assert has_element?(ctx.melissa, "[data-role=tap-great].btn-success")
      assert has_element?(ctx.melissa, "[data-role=your-bookends-tap]")
      assert has_element?(ctx.melissa, "[data-role=seat-bookends-tap]", "great")
      refute has_element?(ctx.jacob, "[data-role=your-bookends-tap]")

      # Melissa replaces tap with fine
      ctx.melissa |> element("[data-role=tap-fine]") |> render_click()

      assert has_element?(ctx.melissa, "[data-role=tap-fine].btn-primary")
      assert has_element?(ctx.melissa, "[data-role=seat-bookends-tap]", "fine")

      # Jacob taps flat
      ctx.jacob |> element("[data-role=tap-flat]") |> render_click()

      assert has_element?(ctx.jacob, "[data-role=tap-flat].btn-warning")
      assert has_element?(ctx.jacob, "[data-role=seat-bookends-tap]", "flat")

      # Both taps recorded in Chronicle
      room = Thereish.Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)
      taps = Thereish.Chronicle.bookends_taps(room.id)
      assert length(taps) == 3

      [outcome] = Thereish.Chronicle.experiment_outcomes(room.id, "author_model")
      assert Map.values(outcome.taps) |> Enum.sort() == ["fine", "flat"]

      seats = Thereish.Repo.preload(room, :seats).seats
      melissa_seat = Enum.find(seats, &(&1.name == "Melissa"))
      jacob_seat = Enum.find(seats, &(&1.name == "Jacob"))
      assert outcome.taps[melissa_seat.id] == "fine"
      assert outcome.taps[jacob_seat.id] == "flat"
    end
  end

  describe "giving settings and writing the page (ticket 02)" do
    setup do
      slug = open_room()

      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      steward = Application.fetch_env!(:thereish, :steward)
      on_exit(fn -> Application.put_env(:thereish, :steward, steward) end)

      %{slug: slug, melissa: melissa, jacob: jacob, stage: stage, steward: steward}
    end

    test "each seat gives a setting, stage shows count, second give triggers author writing",
         ctx do
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_delay_ms: 30, author_mode: :ok)
        )
      )

      # Both phones show Give form, stage shows giving count
      assert has_element?(ctx.melissa, "[data-role=setting-form]")
      assert has_element?(ctx.jacob, "[data-role=setting-form]")
      assert has_element?(ctx.stage, "[data-role=giving-stage]")
      assert render(ctx.stage) =~ "0 of 2"

      # Code card and speaker bar are above setting form during giving phase
      melissa_giving_html = render(ctx.melissa)

      assert_order(melissa_giving_html, [
        ~s(data-role="speaker-bar"),
        ~s(data-role="room-code"),
        ~s(data-role="setting-form")
      ])

      # Melissa gives a setting
      give_setting(ctx.melissa, "candlelit cathedral")

      assert has_element?(ctx.melissa, "[data-role=your-give]", "candlelit cathedral")
      refute has_element?(ctx.melissa, "[data-role=setting-form]")

      # Jacob still sees setting form and cannot see Melissa's give
      assert has_element?(ctx.jacob, "[data-role=setting-form]")
      refute render(ctx.jacob) =~ "candlelit cathedral"

      # Stage shows updated count without revealing setting text
      eventually(fn -> render(ctx.stage) =~ "1 of 2" end)
      refute render(ctx.stage) =~ "candlelit cathedral"

      # Jacob gives a setting, triggering author writing
      give_setting(ctx.jacob, "misty harbor")

      # Beat meter pulses during writing phase
      eventually(fn -> has_element?(ctx.stage, "[data-role=writing-stage]") end)
      assert has_element?(ctx.melissa, "[data-role=writing-phase]")

      # From :writing on, speaker bar and Code card render after writing phase and before In the Room
      writing_html = render(ctx.melissa)

      assert_order(writing_html, [
        ~s(data-role="writing-phase"),
        ~s(data-role="speaker-bar"),
        ~s(data-role="room-code"),
        "In the Room"
      ])

      # Transitions to bridging with bookends and no setting line
      await_phase(ctx.slug, :bridging)
      eventually(fn -> has_element?(ctx.melissa, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.stage, "[data-role=bookends]") end)

      refute render(ctx.melissa) =~ "Setting:"
      refute render(ctx.stage) =~ "Setting:"
    end

    test "next_page returns to giving phase prefilled with the previous give", ctx do
      play_to_bridging(ctx.melissa, ctx.jacob, ctx.slug, "candlelit cathedral", "misty harbor")

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairns")
      await_reveal_on(ctx.melissa)

      assert has_element?(ctx.melissa, "[data-role=one-more]")
      ctx.melissa |> element("[data-role=one-more]") |> render_click()

      await_phase(ctx.slug, :giving)
      eventually(fn -> has_element?(ctx.melissa, "[data-role=setting-form]") end)

      assert render(ctx.melissa) =~ "value=\"candlelit cathedral\""
      assert render(ctx.jacob) =~ "value=\"misty harbor\""
    end

    test "stage shows waiting count with no give text, then writing animation, then still writing, then failure state",
         ctx do
      author_escalation(still_writing: 30, deadline: 100)

      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_delay_ms: 250, author_mode: :ok)
        )
      )

      # 1. Stage shows waiting count with no give text
      give_setting(ctx.melissa, "secret cathedral")
      eventually(fn -> render(ctx.stage) =~ "Waiting for settings: 1 of 2" end)
      refute render(ctx.stage) =~ "secret cathedral"

      # 2. Last give in: writing animation on stage and phones
      give_setting(ctx.jacob, "secret harbour")
      eventually(fn -> has_element?(ctx.stage, "[data-role=writing-stage]") end)
      assert has_element?(ctx.melissa, "[data-role=writing-phase]")
      assert has_element?(ctx.jacob, "[data-role=writing-phase]")
      assert render(ctx.stage) =~ "The Author is reading your settings..."
      assert render(ctx.melissa) =~ "The Author is reading your settings..."

      # 3. At five seconds (30ms test time): every screen says the Author is still writing
      eventually(fn -> render(ctx.stage) =~ "The Author is still writing..." end)
      assert render(ctx.melissa) =~ "The Author is still writing..."
      assert render(ctx.jacob) =~ "The Author is still writing..."

      # 4. At deadline: stage and phones show failure state, writing animation gone
      eventually(fn -> has_element?(ctx.stage, "[data-role=author-failure]") end)
      assert has_element?(ctx.melissa, "[data-role=author-failure]")
      assert has_element?(ctx.jacob, "[data-role=author-failure]")

      refute has_element?(ctx.stage, "[data-role=writing-stage]")
      refute has_element?(ctx.melissa, "[data-role=writing-phase]")
      refute has_element?(ctx.jacob, "[data-role=writing-phase]")

      assert has_element?(
               ctx.stage,
               "[data-role=author-failure]",
               "The Author couldn't write from these settings: timed out"
             )

      assert has_element?(
               ctx.melissa,
               "[data-role=author-failure]",
               "The Author couldn't write from these settings: timed out"
             )

      assert has_element?(
               ctx.jacob,
               "[data-role=author-failure]",
               "The Author couldn't write from these settings: timed out"
             )
    end

    test "an Author failure shows Try again and New settings on both phones, and either may retry",
         ctx do
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

      give_setting(ctx.melissa, "setting one")
      give_setting(ctx.jacob, "setting two")

      eventually(fn -> has_element?(ctx.melissa, "[data-role=author-failure]") end)
      assert has_element?(ctx.jacob, "[data-role=author-failure]")

      # Both phones see Try again and New settings
      for phone <- [ctx.melissa, ctx.jacob] do
        assert has_element?(phone, "[data-role=retry-author]", "Try again")
        assert has_element?(phone, "[data-role=reset-gives]", "New settings")

        assert has_element?(
                 phone,
                 "[data-role=author-failure]",
                 "The Author couldn't write from these settings"
               )
      end

      # Configure author to succeed on retry
      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_mode: :ok)
        )
      )

      # Either Seat may tap Try again (e.g. Jacob taps)
      ctx.jacob |> element("[data-role=retry-author]", "Try again") |> render_click()

      # Both phones and stage transition to bridging
      await_phase(ctx.slug, :bridging)
      eventually(fn -> has_element?(ctx.melissa, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.jacob, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.stage, "[data-role=bookends]") end)
    end

    test "New settings clears every Give and returns both phones to giving prefilled with last give",
         ctx do
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_mode: :refused)
        )
      )

      give_setting(ctx.melissa, "setting melissa")
      give_setting(ctx.jacob, "setting jacob")

      eventually(fn -> has_element?(ctx.melissa, "[data-role=author-failure]") end)
      assert has_element?(ctx.jacob, "[data-role=author-failure]")

      # Melissa clicks New settings
      ctx.melissa |> element("[data-role=reset-gives]", "New settings") |> render_click()

      # Both phones return to giving form
      eventually(fn -> has_element?(ctx.melissa, "[data-role=setting-form]") end)
      assert has_element?(ctx.jacob, "[data-role=setting-form]")

      # Each phone is prefilled with its own last give
      assert render(ctx.melissa) =~ "value=\"setting melissa\""
      assert render(ctx.jacob) =~ "value=\"setting jacob\""

      # Stage returns to giving count 0 of 2
      eventually(fn -> render(ctx.stage) =~ "Waiting for settings: 0 of 2" end)
    end

    test "submitting an empty Give shows an error", ctx do
      give_setting(ctx.melissa, "   ")
      assert has_element?(ctx.melissa, "[data-role=give-error]", "Type a setting first.")
    end
  end

  describe "blinding in rendered views (ticket 13)" do
    setup do
      slug = open_room()

      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      play_to_bridging(melissa, jacob, slug)

      %{slug: slug, melissa: melissa, jacob: jacob, stage: stage}
    end

    test "arm labels are blinded on stage and on phones during play", ctx do
      # During bridging phase:
      melissa_html = render(ctx.melissa)
      jacob_html = render(ctx.jacob)
      stage_html = render(ctx.stage)

      for html <- [melissa_html, jacob_html, stage_html] do
        refute html =~ ~r/\barm\s*=\s*["'](bait|plain)["']/i
        refute html =~ ~r/\barm:\s*(bait|plain)\b/i
        refute html =~ "data-arm"
      end

      # Commit bridges and reveal
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")
      await_reveal_on(ctx.melissa)
      await_reveal_on(ctx.stage)

      # During reveal phase:
      melissa_reveal = render(ctx.melissa)
      jacob_reveal = render(ctx.jacob)
      stage_reveal = render(ctx.stage)

      for html <- [melissa_reveal, jacob_reveal, stage_reveal] do
        refute html =~ ~r/\barm\s*=\s*["'](bait|plain)["']/i
        refute html =~ ~r/\barm:\s*(bait|plain)\b/i
        refute html =~ "data-arm"
        refute html =~ "bait-scored"
        refute html =~ "plain-scored"
      end
    end
  end

  describe "the stage door and the quiet phones (ticket 07)" do
    test "Room page shows 'Make this device the Stage' button whether or not the device holds a Seat" do
      slug = open_room()

      # Before joining: no seat held
      {:ok, visitor, _} = live(phone(slug))
      assert has_element?(visitor, "[data-role=make-stage]", "Make this device the Stage")
      assert render(element(visitor, "[data-role=make-stage]")) =~ ~p"/r/#{slug}/stage"

      # Clicking button navigates to stage route
      assert {:error, {:live_redirect, %{to: to}}} =
               visitor |> element("[data-role=make-stage]") |> render_click()

      assert to == ~p"/r/#{slug}/stage"

      # After joining: holds a seat
      {:ok, player, _} = live(phone(slug))
      join(player, "Melissa")
      assert has_element?(player, "[data-role=make-stage]", "Make this device the Stage")

      assert {:error, {:live_redirect, %{to: to}}} =
               player |> element("[data-role=make-stage]") |> render_click()

      assert to == ~p"/r/#{slug}/stage"
    end

    test "two phones and a stage: giving state and bookends on stage, quiet reveal on both phones, full reveal on stage, and return when stage exits" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      # Stage giving state while phones give
      assert has_element?(stage, "[data-role=giving-stage]")
      assert render(stage) =~ "Waiting for settings: 0 of 2"

      give_setting(melissa, "lanterns on the quay")
      eventually(fn -> render(stage) =~ "Waiting for settings: 1 of 2" end)

      give_setting(jacob, "fog over the harbour")
      await_phase(slug, :bridging)

      # Stage renders Bookends while phones bridge
      eventually(fn -> has_element?(stage, "[data-role=bookends]") end)
      assert has_element?(stage, "[data-role=bookends]", "lantern")
      assert has_element?(stage, "[data-role=bookends]", "harbour")
      assert has_element?(melissa, "[data-role=bookends]", "lantern")
      assert has_element?(jacob, "[data-role=bookends]", "lantern")

      # Both phones commit bridges
      commit(melissa, "cairn")
      commit(jacob, "cairo")

      await_reveal_on(stage)
      await_reveal_on(melissa)
      await_reveal_on(jacob)

      # Stage renders full reveal
      assert has_element?(stage, "[data-role=comparison]")
      assert has_element?(stage, "[data-role=closeness]", "80")
      assert has_element?(stage, "[data-role=band]", "almost")
      assert has_element?(stage, "[data-role=quip]")
      refute has_element?(stage, "[data-role=fairness-controls]")

      # Both phones render quiet reveal: comparison, controls only; NO closeness, band, or quip
      for phone <- [melissa, jacob] do
        assert has_element?(phone, "[data-role=reveal][data-mode=quiet]")
        assert has_element?(phone, "[data-role=comparison]")
        assert has_element?(phone, "[data-role=fairness-controls]")
        assert has_element?(phone, "[data-role=propose-overrule]")
        assert has_element?(phone, "[data-role=again]")
        refute has_element?(phone, "[data-role=closeness]")
        refute has_element?(phone, "[data-role=closeness-display]")
        refute has_element?(phone, "[data-role=band]")
        refute has_element?(phone, "[data-role=quip]")
      end

      # Stage view exits
      Process.flag(:trap_exit, true)
      ref = Process.monitor(stage.pid)
      Process.exit(stage.pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _pid, :killed}

      # Both phones return to full reveal
      eventually(fn -> has_element?(melissa, "[data-role=closeness]", "80") end)
      eventually(fn -> has_element?(jacob, "[data-role=closeness]", "80") end)

      assert has_element?(melissa, "[data-role=band]", "almost")
      assert has_element?(melissa, "[data-role=quip]")
      assert has_element?(jacob, "[data-role=band]", "almost")
      assert has_element?(jacob, "[data-role=quip]")
    end

    test "a stage connecting mid-reveal makes phones go quiet, and disconnecting returns them to full reveal" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))

      join(melissa, "Melissa")
      join(jacob, "Jacob")
      play_to_bridging(melissa, jacob, slug)

      commit(melissa, "cairn")
      commit(jacob, "cairo")

      await_reveal_on(melissa)
      await_reveal_on(jacob)

      # Initially no stage: both phones show full reveal
      assert has_element?(melissa, "[data-role=closeness]", "80")
      assert has_element?(jacob, "[data-role=closeness]", "80")

      # Stage connects
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      await_reveal_on(stage)

      # Both phones go quiet
      eventually(fn -> !has_element?(melissa, "[data-role=closeness]") end)
      eventually(fn -> !has_element?(jacob, "[data-role=closeness]") end)

      refute has_element?(melissa, "[data-role=band]")
      refute has_element?(melissa, "[data-role=quip]")
      assert has_element?(melissa, "[data-role=fairness-controls]")

      # Stage exits
      Process.flag(:trap_exit, true)
      ref = Process.monitor(stage.pid)
      Process.exit(stage.pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _pid, :killed}

      # Both phones return to full reveal
      eventually(fn -> has_element?(melissa, "[data-role=closeness]", "80") end)
      eventually(fn -> has_element?(jacob, "[data-role=closeness]", "80") end)
      assert has_element?(melissa, "[data-role=band]", "almost")
      assert has_element?(melissa, "[data-role=quip]")
    end
  end

  describe "four phones in a Room (ticket 05)" do
    test "the whole four-phone path from front page to one more Page" do
      # 1. Front page -> New Room for four
      conn1 = build_conn()
      {:ok, front1, _} = live(conn1, ~p"/")
      assert has_element?(front1, "[data-role=new-room]")

      {:ok, new_room_view, _} = live(conn1, ~p"/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               new_room_view |> form("form") |> render_submit()

      "/r/" <> code = to
      on_exit(fn -> stop_room(code) end)

      # Phone 1 is the creator, sees the Code and joins
      {:ok, phone1, _} = live(conn1, to)
      assert has_element?(phone1, "[data-role=code]", String.upcase(code))
      join(phone1, "Melissa")

      # 2. Three phones join by Code from front page
      conn2 = build_conn()
      {:ok, front2, _} = live(conn2, ~p"/")

      assert {:error, {:live_redirect, %{to: ^to}}} =
               front2 |> form("form", %{"code" => String.downcase(code)}) |> render_submit()

      {:ok, phone2, _} = live(conn2, to)
      join(phone2, "Jacob")

      conn3 = build_conn()
      {:ok, front3, _} = live(conn3, ~p"/")

      assert {:error, {:live_redirect, %{to: ^to}}} =
               front3 |> form("form", %{"code" => code}) |> render_submit()

      {:ok, phone3, _} = live(conn3, to)
      join(phone3, "Ada")

      conn4 = build_conn()
      {:ok, front4, _} = live(conn4, ~p"/")

      assert {:error, {:live_redirect, %{to: ^to}}} =
               front4 |> form("form", %{"code" => String.upcase(code)}) |> render_submit()

      {:ok, phone4, _} = live(conn4, to)
      join(phone4, "Sam")

      # Roster fills
      for phone <- [phone1, phone2, phone3, phone4] do
        assert has_element?(phone, "[data-seat]", "Melissa")
        assert has_element?(phone, "[data-seat]", "Jacob")
        assert has_element?(phone, "[data-seat]", "Ada")
        assert has_element?(phone, "[data-seat]", "Sam")
      end

      # 3. Four Gives go in, each private to its giver
      give_setting(phone1, "coastal lighthouse in storm")
      assert has_element?(phone1, "[data-role=your-give]", "coastal lighthouse in storm")
      refute render(phone2) =~ "coastal lighthouse in storm"
      refute render(phone3) =~ "coastal lighthouse in storm"
      refute render(phone4) =~ "coastal lighthouse in storm"

      give_setting(phone2, "old library with rolling ladders")
      assert has_element?(phone2, "[data-role=your-give]", "old library with rolling ladders")
      refute render(phone1) =~ "old library with rolling ladders"
      refute render(phone3) =~ "old library with rolling ladders"
      refute render(phone4) =~ "old library with rolling ladders"

      give_setting(phone3, "artisan glassblowing workshop")
      give_setting(phone4, "mountain observatory at dusk")

      phone1 |> element("[data-role=start-page]") |> render_click()

      await_phase(code, :bridging)

      # 4. Bookends on every phone
      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=bookends]") end)
        assert has_element?(phone, "[data-role=bookends]", "lantern")
        assert has_element?(phone, "[data-role=bookends]", "harbour")
      end

      # 5. Four commits
      commit(phone1, "beacon")
      commit(phone2, "cairn")
      commit(phone3, "lamp")
      commit(phone4, "seagull")

      # 6. One reveal on all four phones with no reasoning shown
      for phone <- [phone1, phone2, phone3, phone4] do
        await_reveal_on(phone)

        # Every phone reveals every Bridge
        assert has_element?(phone, "[data-role=comparison]")
        assert render(phone) =~ "beacon"
        assert render(phone) =~ "cairn"
        assert render(phone) =~ "lamp"
        assert render(phone) =~ "seagull"

        # One number in its band
        assert has_element?(phone, "[data-role=closeness]")
        assert has_element?(phone, "[data-role=band]")

        # One quip after the beat
        assert has_element?(phone, "[data-role=quip]")

        # No reasoning card
        refute has_element?(phone, "[data-role=reasoning]")
        refute render(phone) =~ "Reasoning:"
      end

      # 7. Carry into the next Attempt
      snapshot = Rooms.snapshot(code, nil)
      [carry1, carry2] = snapshot.next_bookends

      for phone <- [phone1, phone2, phone3, phone4] do
        # Again button names the two words that open the next Attempt
        assert has_element?(phone, "[data-role=again]")
        assert render(element(phone, "[data-role=again]")) =~ "Again — #{carry1} and #{carry2}"
        # Carry-forward text names the two words
        assert has_element?(phone, "[data-role=carry-forward]")
        assert render(element(phone, "[data-role=carry-forward]")) =~ carry1
        assert render(element(phone, "[data-role=carry-forward]")) =~ carry2
      end

      # Tap Again to start Attempt 2 with the carried Bookends
      phone1 |> element("[data-role=again]") |> render_click()

      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=attempt]", "Attempt 2") end)
        assert has_element?(phone, "[data-role=bookends]", carry1)
        assert has_element?(phone, "[data-role=bookends]", carry2)
      end

      # Commit on Attempt 2
      commit(phone1, "signal")
      commit(phone2, "tower")
      commit(phone3, "flare")
      commit(phone4, "spark")

      for phone <- [phone1, phone2, phone3, phone4] do
        await_reveal_on(phone)
      end

      # 8. Unanimous overrule writing 90
      phone1 |> element("[data-role=propose-overrule]") |> render_click()

      # Proposer sees waiting
      assert has_element?(phone1, "[data-role=overrule-banner]")
      assert render(phone1) =~ "Waiting for everyone to agree"

      # Other phones see Agree / Decline
      for phone <- [phone2, phone3, phone4] do
        assert has_element?(phone, "[data-role=agree-overrule]")
      end

      # Vote sequentially: 2 agrees, 3 agrees, then 4 agrees
      phone2 |> element("[data-role=agree-overrule]") |> render_click()
      refute Rooms.snapshot(code, nil).reveal.melded?
      assert Rooms.snapshot(code, nil).phase == :reveal

      phone3 |> element("[data-role=agree-overrule]") |> render_click()
      refute Rooms.snapshot(code, nil).reveal.melded?
      assert Rooms.snapshot(code, nil).phase == :reveal

      phone4 |> element("[data-role=agree-overrule]") |> render_click()
      assert Rooms.snapshot(code, nil).phase == :closed

      # Overrule resolves: writes the meld floor (90) on all phones
      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=closeness]", "90") end)
        assert has_element?(phone, "[data-role=band]", "meld")
        assert has_element?(phone, "[data-role=overruled-notice]")
        assert has_element?(phone, "[data-role=one-more]")
      end

      # 9. One more Page asks for fresh Gives again
      phone1 |> element("[data-role=one-more]") |> render_click()

      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=setting-form]") end)
      end
    end

    test "the stage view renders the full reveal for a Room of four that has a screen, and the four phones show Bridges and controls only while it does" do
      code = open_room(seat_limit: 4)

      # Stage connects
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{code}/stage")

      # Four phones connect and join
      phones =
        for name <- ["Melissa", "Jacob", "Ada", "Sam"] do
          {:ok, phone, _} = live(phone(code))
          join(phone, name)
          phone
        end

      assert has_element?(stage, "[data-role=giving-stage]")
      assert render(stage) =~ "Waiting for settings: 0 of 4"

      [p1, p2, p3, p4] = phones
      give_setting(p1, "setting one")
      eventually(fn -> render(stage) =~ "Waiting for settings: 1 of 4" end)
      give_setting(p2, "setting two")
      give_setting(p3, "setting three")
      give_setting(p4, "setting four")

      await_phase(code, :bridging)

      # Stage renders Bookends while phones bridge
      eventually(fn -> has_element?(stage, "[data-role=bookends]") end)

      for phone <- phones do
        assert has_element?(phone, "[data-role=bookends]")
      end

      # All four commit bridges
      commit(p1, "beacon")
      commit(p2, "cairn")
      commit(p3, "lamp")
      commit(p4, "seagull")

      await_reveal_on(stage)

      for phone <- phones do
        await_reveal_on(phone)
      end

      # Stage renders full reveal
      assert has_element?(stage, "[data-role=comparison]")
      assert has_element?(stage, "[data-role=closeness]")
      assert has_element?(stage, "[data-role=band]")
      assert has_element?(stage, "[data-role=quip]")
      refute has_element?(stage, "[data-role=fairness-controls]")

      # All four phones show Bridges and controls only while stage is present
      for phone <- phones do
        assert has_element?(phone, "[data-role=reveal][data-mode=quiet]")
        assert has_element?(phone, "[data-role=comparison]")
        assert has_element?(phone, "[data-role=fairness-controls]")
        assert has_element?(phone, "[data-role=propose-overrule]")
        assert has_element?(phone, "[data-role=again]")
        refute has_element?(phone, "[data-role=closeness]")
        refute has_element?(phone, "[data-role=closeness-display]")
        refute has_element?(phone, "[data-role=band]")
        refute has_element?(phone, "[data-role=quip]")
      end
    end
  end

  describe "Foley speaker and audio pushes" do
    setup do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      # The Stage starts wait music while waiting; later tests look at Page events.
      assert_push_event(stage, "foley:page", %{kind: "repertoire"})

      %{slug: slug, melissa: melissa, jacob: jacob, stage: stage}
    end

    test "waiting Stage: Repertoire draw then tap-for-sound has a foley:page to play" do
      slug = open_room(seat_limit: 6)
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      assert has_element?(stage, "[data-role=tap-for-sound]")
      assert has_element?(stage, "[data-role=music-house]")

      assert_push_event(stage, "foley:page", %{kind: "repertoire", path: path})
      assert String.starts_with?(path, "/audio/house-loop")

      stage |> element("[data-role=music-off]") |> render_click()
      assert_push_event(stage, "foley:page", %{path: nil})

      stage |> element("[data-role=music-house]") |> render_click()
      assert Rooms.get_room(slug).music == "house"
      assert_push_event(stage, "foley:page", %{kind: "repertoire", path: house_path})
      assert String.starts_with?(house_path, "/audio/house-loop")
    end

    test "stage claims speaker on mount; phone claims take it from stage and silence it", ctx do
      assert has_element?(ctx.stage, "[data-role=tap-for-sound]")
      assert has_element?(ctx.melissa, "[data-role=speaker-toggle][data-speaker=other]")
      assert has_element?(ctx.jacob, "[data-role=speaker-toggle][data-speaker=other]")

      assert has_element?(ctx.stage, "[data-role=voice-switch]")
      assert has_element?(ctx.stage, "[data-role=music-control]")
      assert has_element?(ctx.melissa, "[data-role=voice-switch]")
      assert has_element?(ctx.melissa, "[data-role=music-control]")
      assert has_element?(ctx.melissa, "[data-role=local-sound-toggle]")

      assert has_element?(
               ctx.melissa,
               "[data-role=local-sound-toggle][title=\"Commit sound plays from the Stage while connected\"]"
             )

      assert has_element?(ctx.jacob, "[data-role=voice-switch]")
      assert has_element?(ctx.jacob, "[data-role=music-control]")
      assert has_element?(ctx.jacob, "[data-role=local-sound-toggle]")
      refute has_element?(ctx.stage, "[data-role=local-sound-toggle]")

      assert has_element?(ctx.stage, "[data-role=voice-switch][data-active=false]")
      assert has_element?(ctx.stage, "[data-role=music-page][data-active=true]")
      assert has_element?(ctx.melissa, "[data-role=music-page][data-active=true]")
      assert has_element?(ctx.jacob, "[data-role=music-page][data-active=true]")

      ctx.melissa |> element("[data-role=speaker-toggle]") |> render_click()

      assert_push_event(ctx.stage, "foley:stop", %{})
      refute has_element?(ctx.stage, "[data-role=tap-for-sound]")

      assert has_element?(ctx.stage, "[data-role=voice-switch]")
      assert has_element?(ctx.stage, "[data-role=music-control]")
      assert has_element?(ctx.melissa, "[data-role=speaker-toggle][data-speaker=self]")
      assert has_element?(ctx.jacob, "[data-role=speaker-toggle][data-speaker=other]")

      assert has_element?(ctx.melissa, "[data-role=voice-switch]")
      assert has_element?(ctx.melissa, "[data-role=music-control]")

      ctx.melissa |> element("[data-role=voice-switch]") |> render_click()
      assert Rooms.get_room(ctx.slug).voice == true
      assert has_element?(ctx.melissa, "[data-role=voice-switch][data-active=true]")
      assert has_element?(ctx.stage, "[data-role=voice-switch][data-active=true]")
      assert has_element?(ctx.jacob, "[data-role=voice-switch][data-active=true]")

      ctx.jacob |> element("[data-role=music-off]") |> render_click()
      assert Rooms.get_room(ctx.slug).music == "off"
      assert has_element?(ctx.melissa, "[data-role=music-off][data-active=true]")
      assert has_element?(ctx.stage, "[data-role=music-off][data-active=true]")
      assert has_element?(ctx.jacob, "[data-role=music-off][data-active=true]")
    end

    test "foley events push to the speaking view alone across a Page arc", ctx do
      give_setting(ctx.melissa, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{kind: "track", path: track_path})
      assert String.starts_with?(track_path, "/media/tracks/fake-")
      refute_push_event(ctx.melissa, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      assert_push_event(ctx.stage, "foley:beat", %{})
      refute_push_event(ctx.melissa, "foley:beat", %{})
      refute_push_event(ctx.jacob, "foley:beat", %{})

      await_reveal_on(ctx.stage)
      assert_push_event(ctx.stage, "foley:sting", %{band: _})
      refute_push_event(ctx.melissa, "foley:sting", %{})
      refute_push_event(ctx.jacob, "foley:sting", %{})

      ctx.melissa |> element("[data-role=speaker-toggle]") |> render_click()
      assert_push_event(ctx.stage, "foley:stop", %{})
      assert_push_event(ctx.melissa, "foley:page", %{path: melissa_track_path})
      assert melissa_track_path == track_path

      ctx.melissa |> element("[data-role=again]") |> render_click()
      await_phase(ctx.slug, :bridging)
      eventually(fn -> has_element?(ctx.melissa, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.jacob, "[data-role=bridge-form]") end)

      commit(ctx.melissa, "stone")
      commit(ctx.jacob, "stone")

      assert_push_event(ctx.melissa, "foley:beat", %{})
      refute_push_event(ctx.stage, "foley:beat", %{})

      await_reveal_on(ctx.melissa)
      assert_push_event(ctx.melissa, "foley:sting", %{band: _})
      assert_push_event(ctx.melissa, "foley:ending", %{kind: :deep_meld})
      refute_push_event(ctx.stage, "foley:sting", %{})
      refute_push_event(ctx.stage, "foley:ending", %{})
    end

    test "foley:ending pushes :meld when closing on a meld band", ctx do
      give_setting(ctx.melissa, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{path: _})

      # cairns and cairn has shared prefix 5/11 -> closeness 91, which is in :meld band
      commit(ctx.melissa, "cairns")
      commit(ctx.jacob, "cairn")

      assert_push_event(ctx.stage, "foley:beat", %{})
      await_reveal_on(ctx.stage)

      assert_push_event(ctx.stage, "foley:sting", %{band: :meld})
      assert_push_event(ctx.stage, "foley:ending", %{kind: :meld})
      refute_push_event(ctx.melissa, "foley:ending", %{})
      refute_push_event(ctx.jacob, "foley:ending", %{})
    end

    test "foley:ending pushes :unmelded when closing without a meld", ctx do
      attempt_cap(1)

      give_setting(ctx.melissa, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{path: _})

      # cairn and beacon share 0 prefix -> closeness 0, miss
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "beacon")

      assert_push_event(ctx.stage, "foley:beat", %{})
      await_reveal_on(ctx.stage)

      assert_push_event(ctx.stage, "foley:sting", %{band: :miss})
      assert_push_event(ctx.stage, "foley:ending", %{kind: :unmelded})
      refute_push_event(ctx.melissa, "foley:ending", %{})
      refute_push_event(ctx.jacob, "foley:ending", %{})
    end

    test "music control pushes off, house, and page to speaker alone", ctx do
      give_setting(ctx.melissa, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{kind: "track", path: track_path})
      assert String.starts_with?(track_path, "/media/tracks/fake-")
      refute_push_event(ctx.melissa, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})

      # Setting off (e.g. from Melissa's phone) pushes path: nil to speaker alone
      ctx.melissa |> element("[data-role=music-off]") |> render_click()

      assert_push_event(ctx.stage, "foley:page", %{path: nil})
      refute_push_event(ctx.melissa, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})

      # Setting house (e.g. from Jacob's phone) pushes the Page's loop to speaker alone
      ctx.jacob |> element("[data-role=music-house]") |> render_click()

      expected_loop = Rooms.snapshot(ctx.slug, nil).loop

      expected_path = expected_loop.path
      expected_title = expected_loop.name

      assert_push_event(ctx.stage, "foley:page", %{
        path: ^expected_path,
        title: ^expected_title,
        kind: "repertoire"
      })

      refute_push_event(ctx.melissa, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})

      # Setting back to page (from stage) pushes track_path to speaker alone
      ctx.stage |> element("[data-role=music-page]") |> render_click()

      assert_push_event(ctx.stage, "foley:page", %{path: ^track_path})
      refute_push_event(ctx.melissa, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})
    end

    test "starting a page under off pushes nil path to speaker", ctx do
      ctx.melissa |> element("[data-role=music-off]") |> render_click()
      assert Rooms.get_room(ctx.slug).music == "off"

      give_setting(ctx.melissa, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{path: nil})
      refute_push_event(ctx.melissa, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})
    end

    test "leaving stage releases speaker", ctx do
      assert Rooms.get_room(ctx.slug).speaker != nil

      GenServer.stop(ctx.stage.pid)

      eventually(fn ->
        is_nil(Rooms.get_room(ctx.slug).speaker)
      end)
    end

    test "foley:beat, foley:sting, and foley:voice push in order to speaking view alone", ctx do
      give_setting(ctx.melissa, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{path: _})
      refute_push_event(ctx.melissa, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})

      # Stage is speaker; enable voice switch
      ctx.stage |> element("[data-role=voice-switch]") |> render_click()
      assert Rooms.get_room(ctx.slug).voice == true

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      # Ordered push sequence: beat -> sting -> voice
      assert_push_event(ctx.stage, "foley:beat", %{})
      refute_push_event(ctx.melissa, "foley:beat", %{})
      refute_push_event(ctx.jacob, "foley:beat", %{})

      await_reveal_on(ctx.stage)

      assert_push_event(ctx.stage, "foley:sting", %{band: _})
      refute_push_event(ctx.melissa, "foley:sting", %{})
      refute_push_event(ctx.jacob, "foley:sting", %{})

      expected_stage_url = "/r/#{ctx.slug}/voice/1"
      assert_push_event(ctx.stage, "foley:voice", %{attempt: 1, url: ^expected_stage_url})
      refute_push_event(ctx.melissa, "foley:voice", %{})
      refute_push_event(ctx.jacob, "foley:voice", %{})

      # Phone claims speaker; voice switch persists
      ctx.melissa |> element("[data-role=speaker-toggle]") |> render_click()
      assert Rooms.get_room(ctx.slug).voice == true

      ctx.melissa |> element("[data-role=again]") |> render_click()
      await_phase(ctx.slug, :bridging)
      eventually(fn -> has_element?(ctx.melissa, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.jacob, "[data-role=bridge-form]") end)

      commit(ctx.melissa, "stone")
      commit(ctx.jacob, "stone")

      assert_push_event(ctx.melissa, "foley:beat", %{})
      refute_push_event(ctx.stage, "foley:beat", %{})

      await_reveal_on(ctx.melissa)

      assert_push_event(ctx.melissa, "foley:sting", %{band: _})
      expected_melissa_url = "/r/#{ctx.slug}/voice/2"
      assert_push_event(ctx.melissa, "foley:voice", %{attempt: 2, url: ^expected_melissa_url})
      refute_push_event(ctx.stage, "foley:sting", %{})
      refute_push_event(ctx.stage, "foley:voice", %{})
      refute_push_event(ctx.jacob, "foley:voice", %{})
    end

    test "ticket 03: foley:page carries title and kind: house before track lands, and Now playing line renders below the fold",
         ctx do
      # Set score_delay_ms so Track does not land immediately
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.put(fake_config, :music_delay_ms, 500)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      give_setting(ctx.melissa, "mountain cabin")
      give_setting(ctx.jacob, "misty forest")
      await_phase(ctx.slug, :bridging)

      room_snapshot = Rooms.snapshot(ctx.slug, nil)
      expected_loop = room_snapshot.loop
      assert expected_loop != nil

      # Stage is speaker: foley:page carries loop's path, title, and kind: "repertoire"
      assert_push_event(ctx.stage, "foley:page", %{
        path: loop_path,
        title: loop_title,
        kind: "repertoire"
      })

      assert loop_path == expected_loop.path
      assert loop_title == expected_loop.name

      # "Now playing" line renders below the fold on Stage and on Speaker's phone
      # Since Stage is speaker, Stage shows the line, and non-speaker phones do not
      assert has_element?(ctx.stage, "[data-role=now-playing]", expected_loop.name)
      assert has_element?(ctx.stage, "[data-role=now-playing]", "the Repertoire")
      refute has_element?(ctx.melissa, "[data-role=now-playing]")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")

      # Check position on stage: now-playing is below the fold (after bookends)
      stage_html = render(ctx.stage)

      assert_order(stage_html, [
        ~s(data-role="bookends"),
        ~s(data-role="now-playing")
      ])

      # Melissa claims speaker: Melissa's phone now shows the Now playing line below the fold
      ctx.melissa |> element("[data-role=speaker-toggle]") |> render_click()
      assert has_element?(ctx.melissa, "[data-role=now-playing]", expected_loop.name)
      assert has_element?(ctx.melissa, "[data-role=now-playing]", "the Repertoire")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")

      # Check position on Melissa's phone: now-playing is below the fold (after bridge-form, before In the Room)
      melissa_html = render(ctx.melissa)

      assert_order(melissa_html, [
        ~s(data-role="bridge-form"),
        ~s(data-role="now-playing"),
        "In the Room"
      ])

      # Setting off: pushes nil path to speaker, and Now playing says "Music is off"
      ctx.melissa |> element("[data-role=music-off]") |> render_click()
      assert_push_event(ctx.melissa, "foley:page", %{path: nil})
      assert has_element?(ctx.stage, "[data-role=now-playing]", "Music is off")
      assert has_element?(ctx.melissa, "[data-role=now-playing]", "Music is off")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")

      # Setting house: pushes loop with title and kind: "repertoire" to speaker
      ctx.melissa |> element("[data-role=music-house]") |> render_click()

      assert_push_event(ctx.melissa, "foley:page", %{
        path: ^loop_path,
        title: ^loop_title,
        kind: "repertoire"
      })

      assert has_element?(ctx.stage, "[data-role=now-playing]", expected_loop.name)
      assert has_element?(ctx.stage, "[data-role=now-playing]", "the Repertoire")
      assert has_element?(ctx.melissa, "[data-role=now-playing]", expected_loop.name)
      assert has_element?(ctx.melissa, "[data-role=now-playing]", "the Repertoire")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")
    end

    test "foley:page pushes track with title and kind: track when track lands, and Now playing line updates",
         ctx do
      # Set delay so we can observe house loop first, then track lands
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config, music_delay_ms: 100, title_delay_ms: 0)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      give_setting(ctx.melissa, "summer camp")
      give_setting(ctx.jacob, "viking beaches")
      await_phase(ctx.slug, :bridging)

      # Initially, wait music is pushed to speaker (Stage)
      assert_push_event(ctx.stage, "foley:page", %{kind: "repertoire"})
      assert has_element?(ctx.stage, "[data-role=now-playing]", "the Repertoire")

      # When track lands, foley:page pushes track with title and kind: "track"
      assert_push_event(
        ctx.stage,
        "foley:page",
        %{
          path: track_path,
          title: "Summer Camp · Viking Beaches",
          kind: "track"
        },
        1000
      )

      assert String.starts_with?(track_path, "/media/tracks/")

      # Now playing line updates from house loop to written for this Page
      eventually(fn ->
        has_element?(
          ctx.stage,
          "[data-role=now-playing]",
          "Now playing: Summer Camp · Viking Beaches (written for this Page)"
        )
      end)
    end

    test "foley:page pushes playable-early stream, speaker plays it and updates Now playing, then transitions to completed track",
         ctx do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config,
            music_mode: :stream,
            music_stream_delay_ms: 0,
            music_delay_ms: 150,
            title_delay_ms: 0
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

      give_setting(ctx.melissa, "alpine forest")
      give_setting(ctx.jacob, "snowy peaks")
      await_phase(ctx.slug, :bridging)

      # 1. Playable stream arrives early with stream: true
      assert_push_event(
        ctx.stage,
        "foley:page",
        %{
          path: stream_path,
          kind: "track",
          stream: true
        },
        1000
      )

      assert String.starts_with?(stream_path, "https://stream.mureka.ai/live/fake-")

      # "Now playing" line updates on speaker
      eventually(fn ->
        has_element?(
          ctx.stage,
          "[data-role=now-playing]",
          "Alpine Forest · Snowy Peaks (written for this Page)"
        )
      end)

      # 2. Later, completed MP3 track lands and pushes updated foley:page
      assert_push_event(
        ctx.stage,
        "foley:page",
        %{
          path: final_path,
          kind: "track"
        },
        1500
      )

      assert String.starts_with?(final_path, "/media/tracks/fake-")
      assert String.ends_with?(final_path, ".mp3")
    end

    test "foley:page reverts to Repertoire when score fails, Room does not stall", ctx do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config,
            music_mode: :stream,
            music_stream_delay_ms: 0,
            music_fail_after_stream: true,
            music_delay_ms: 100,
            title_delay_ms: 0
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

      give_setting(ctx.melissa, "alpine forest")
      give_setting(ctx.jacob, "snowy peaks")
      await_phase(ctx.slug, :bridging)

      # 1. Playable stream lands first
      assert_push_event(
        ctx.stage,
        "foley:page",
        %{
          path: _stream_path,
          kind: "track",
          stream: true
        },
        1000
      )

      # 2. Score failure lands, foley:page falls back to Repertoire wait music
      assert_push_event(
        ctx.stage,
        "foley:page",
        %{
          path: rep_path,
          kind: "repertoire"
        },
        1500
      )

      assert is_binary(rep_path)

      # Room advances and does not stall; reverts to Repertoire
      eventually(fn ->
        snapshot = Rooms.snapshot(ctx.slug, nil)
        snapshot.phase == :bridging and snapshot.playing.kind == "repertoire"
      end)
    end

    test "ticket 01: wait music plays during giving, pushed to speaker with kind repertoire, and Now playing names it on speaker",
         ctx do
      # In giving phase (setup joins Melissa & Jacob)
      snapshot = Rooms.snapshot(ctx.slug, nil)
      assert snapshot.playing.kind == "repertoire"
      title = snapshot.playing.title
      path = snapshot.playing.path
      assert is_binary(path) and is_binary(title)

      # Now playing line renders below the fold on speaking Stage
      assert has_element?(ctx.stage, "[data-role=now-playing]", title)
      assert has_element?(ctx.stage, "[data-role=now-playing]", "the Repertoire")

      # Non-speaking phones do not show Now playing
      refute has_element?(ctx.melissa, "[data-role=now-playing]")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")

      # Melissa claims speaker during giving: Melissa gets foley:page and shows Now playing
      ctx.melissa |> element("[data-role=speaker-toggle]") |> render_click()

      assert_push_event(ctx.melissa, "foley:page", %{
        path: ^path,
        title: ^title,
        kind: "repertoire"
      })

      assert has_element?(ctx.melissa, "[data-role=now-playing]", title)
      assert has_element?(ctx.melissa, "[data-role=now-playing]", "the Repertoire")
    end

    test "ticket 02: holdover across close and next_page, giving/writing keep track, and new track seizes speaker during writing",
         ctx do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config, music_delay_ms: 50, title_delay_ms: 0)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      # Play Page 1 through to closed
      give_setting(ctx.melissa, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{
        path: p1_path,
        title: p1_title,
        kind: "track"
      })

      eventually(fn ->
        has_element?(
          ctx.stage,
          "[data-role=now-playing]",
          "Now playing: #{p1_title} (written for this Page)"
        )
      end)

      eventually(fn -> has_element?(ctx.melissa, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.jacob, "[data-role=bridge-form]") end)

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # After page closes: snapshot kind is holdover and Now playing keeps that title
      eventually(fn ->
        has_element?(
          ctx.stage,
          "[data-role=now-playing]",
          "Now playing: #{p1_title} (last Page's Track)"
        )
      end)

      # Move to next page (Page 2)
      eventually(fn -> has_element?(ctx.melissa, "[data-role=one-more]") end)
      ctx.melissa |> element("[data-role=one-more]") |> render_click()
      await_phase(ctx.slug, :giving)

      # Giving keeps Page 1's track: Now playing still shows holdover
      assert has_element?(
               ctx.stage,
               "[data-role=now-playing]",
               "Now playing: #{p1_title} (last Page's Track)"
             )

      refute has_element?(ctx.melissa, "[data-role=now-playing]")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")

      # Melissa claims speaker during giving: Melissa gets foley:page with holdover
      ctx.melissa |> element("[data-role=speaker-toggle]") |> render_click()

      assert_push_event(ctx.melissa, "foley:page", %{
        path: ^p1_path,
        title: ^p1_title,
        kind: "holdover"
      })

      assert has_element?(
               ctx.melissa,
               "[data-role=now-playing]",
               "Now playing: #{p1_title} (last Page's Track)"
             )

      # Add delay to author so we can observe music land during writing phase
      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config, author_delay_ms: 300, music_delay_ms: 50, title_delay_ms: 0)
        )
      )

      # Submit gives for Page 2
      give_setting(ctx.melissa, "whispering pines")
      give_setting(ctx.jacob, "winding river")

      # Writing keeps Page 1's track as holdover
      assert has_element?(ctx.melissa, "[data-role=writing-phase]")

      assert has_element?(
               ctx.melissa,
               "[data-role=now-playing]",
               "Now playing: #{p1_title} (last Page's Track)"
             )

      # When Page 2 track lands, it seizes the speaker during writing
      assert_push_event(ctx.melissa, "foley:page", %{
        path: p2_path,
        title: p2_title,
        kind: "track"
      })

      assert p2_path != p1_path

      eventually(fn ->
        has_element?(
          ctx.melissa,
          "[data-role=now-playing]",
          "Now playing: #{p2_title} (written for this Page)"
        )
      end)
    end

    test "ticket 03: Next renders only on the speaking screen, below the fold with the music control, and pushes new foley:page on tap",
         ctx do
      initial_path = Rooms.snapshot(ctx.slug, ctx.melissa.id).playing.path

      # Melissa claims speaker
      ctx.melissa |> element("[data-role=speaker-toggle]") |> render_click()
      assert_push_event(ctx.melissa, "foley:page", %{kind: "repertoire", path: ^initial_path})

      # Melissa is now speaker; Jacob and Stage are not
      assert has_element?(ctx.melissa, "[data-role=music-control]")
      assert has_element?(ctx.melissa, "[data-role=music-next]")

      refute has_element?(ctx.jacob, "[data-role=music-next]")
      refute has_element?(ctx.stage, "[data-role=music-next]")

      # Tap Next on Melissa (speaking screen)
      ctx.melissa |> element("[data-role=music-next]") |> render_click()

      # foley:page is pushed with new path
      assert_push_event(ctx.melissa, "foley:page", %{
        kind: "repertoire",
        path: new_path,
        title: new_title
      })

      assert new_path != initial_path

      assert has_element?(
               ctx.melissa,
               "[data-role=now-playing]",
               "Now playing: #{new_title} (the Repertoire)"
             )

      # Jacob and Stage do not get foley:page
      refute_push_event(ctx.jacob, "foley:page", %{})
      refute_push_event(ctx.stage, "foley:page", %{})

      # Now progress page until this Page's Track lands
      give_setting(ctx.melissa, "mountain ridge")
      give_setting(ctx.jacob, "silent valley")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.melissa, "foley:page", %{kind: "track", path: p1_track_path, title: _})

      # Once this Page's Track is playing: Next is hidden on the speaking screen
      eventually(fn ->
        not has_element?(ctx.melissa, "[data-role=music-next]")
      end)

      # Finish Page 1 to closed
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Advance to Page 2 (holdover)
      eventually(fn -> has_element?(ctx.melissa, "[data-role=one-more]") end)
      ctx.melissa |> element("[data-role=one-more]") |> render_click()
      await_phase(ctx.slug, :giving)

      # During holdover on Page 2: Next is visible again on speaking screen
      eventually(fn ->
        has_element?(ctx.melissa, "[data-role=music-next]")
      end)

      # Tap Next to skip holdover
      ctx.melissa |> element("[data-role=music-next]") |> render_click()

      # Pushes foley:page with repertoire draw
      assert_push_event(ctx.melissa, "foley:page", %{
        kind: "repertoire",
        path: skipped_path,
        title: skipped_title
      })

      refute skipped_path == p1_track_path

      assert has_element?(
               ctx.melissa,
               "[data-role=now-playing]",
               "Now playing: #{skipped_title} (the Repertoire)"
             )
    end

    test "ticket 03: Next on Stage as speaker advances the wait music deal", ctx do
      assert has_element?(ctx.stage, "[data-role=music-next]")

      initial_snapshot = Rooms.snapshot(ctx.slug, nil)
      initial_path = initial_snapshot.playing.path

      ctx.stage |> element("[data-role=music-next]") |> render_click()

      assert_push_event(ctx.stage, "foley:page", %{
        kind: "repertoire",
        path: new_path,
        title: new_title
      })

      assert new_path != initial_path

      assert has_element?(
               ctx.stage,
               "[data-role=now-playing]",
               "Now playing: #{new_title} (the Repertoire)"
             )
    end

    test "ticket 04: Never renders only on the speaking screen, including while this Page's Track is playing (when Next is hidden), and pushes new foley:page on tap",
         ctx do
      initial_path = Rooms.snapshot(ctx.slug, ctx.melissa.id).playing.path

      # Melissa claims speaker
      ctx.melissa |> element("[data-role=speaker-toggle]") |> render_click()
      assert_push_event(ctx.melissa, "foley:page", %{kind: "repertoire", path: ^initial_path})

      # Melissa is speaker; Jacob and Stage are not
      assert has_element?(ctx.melissa, "[data-role=music-never]")
      refute has_element?(ctx.jacob, "[data-role=music-never]")
      refute has_element?(ctx.stage, "[data-role=music-never]")

      # Tap Never on wait music
      ctx.melissa |> element("[data-role=music-never]") |> render_click()

      assert_push_event(ctx.melissa, "foley:page", %{
        kind: "repertoire",
        path: new_path,
        title: _new_title
      })

      assert new_path != initial_path
      assert initial_path in Thereish.Rooms.Store.list_nevers(Rooms.Store.get_room(ctx.slug).id)

      # Progress page until this Page's Track lands
      give_setting(ctx.melissa, "mountain ridge")
      give_setting(ctx.jacob, "silent valley")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.melissa, "foley:page", %{kind: "track", path: p1_track_path, title: _})

      # While Page's Track is playing: Next is hidden, but Never is still rendered!
      eventually(fn ->
        not has_element?(ctx.melissa, "[data-role=music-next]") and
          has_element?(ctx.melissa, "[data-role=music-never]")
      end)

      # Tap Never on this Page's Track
      ctx.melissa |> element("[data-role=music-never]") |> render_click()

      # Track is refused: pushes foley:page for Repertoire draw
      assert_push_event(ctx.melissa, "foley:page", %{
        kind: "repertoire",
        path: next_rep_path,
        title: next_rep_title
      })

      refute next_rep_path == p1_track_path
      assert p1_track_path in Thereish.Rooms.Store.list_nevers(Rooms.Store.get_room(ctx.slug).id)

      assert has_element?(
               ctx.melissa,
               "[data-role=now-playing]",
               "Now playing: #{next_rep_title} (the Repertoire)"
             )
    end

    test "ticket 04: Never on Stage as speaker refuses the member and pushes new foley:page",
         ctx do
      assert has_element?(ctx.stage, "[data-role=music-never]")

      initial_snapshot = Rooms.snapshot(ctx.slug, nil)
      initial_path = initial_snapshot.playing.path

      ctx.stage |> element("[data-role=music-never]") |> render_click()

      assert_push_event(ctx.stage, "foley:page", %{
        kind: "repertoire",
        path: new_path,
        title: new_title
      })

      assert new_path != initial_path
      assert initial_path in Thereish.Rooms.Store.list_nevers(Rooms.Store.get_room(ctx.slug).id)

      assert has_element?(
               ctx.stage,
               "[data-role=now-playing]",
               "Now playing: #{new_title} (the Repertoire)"
             )
    end

    test "ticket 05: with a Stage, the chain holds across pages, transitions, Next/Never, and crossfades",
         ctx do
      # Night opens on a named Repertoire draw on Stage
      assert has_element?(ctx.stage, "[data-role=now-playing]")
      stage_snapshot = Rooms.snapshot(ctx.slug, nil)
      assert stage_snapshot.playing.kind == "repertoire"
      assert is_binary(stage_snapshot.playing.title)
      assert is_binary(stage_snapshot.playing.path)

      # Next and Never live on the Stage; absent on non-speaking phones
      assert has_element?(ctx.stage, "[data-role=music-next]")
      assert has_element?(ctx.stage, "[data-role=music-never]")
      refute has_element?(ctx.melissa, "[data-role=music-next]")
      refute has_element?(ctx.melissa, "[data-role=music-never]")
      refute has_element?(ctx.jacob, "[data-role=music-next]")
      refute has_element?(ctx.jacob, "[data-role=music-never]")

      # Gives submitted for Page 1
      give_setting(ctx.melissa, "mountain ridge")
      give_setting(ctx.jacob, "silent valley")
      await_phase(ctx.slug, :bridging)

      # Track fades in when it lands
      assert_push_event(ctx.stage, "foley:page", %{
        kind: "track",
        path: p1_track_path,
        title: _p1_track_title
      })

      # Once this Page's Track is playing: Next is hidden, Never remains visible
      eventually(fn ->
        not has_element?(ctx.stage, "[data-role=music-next]") and
          has_element?(ctx.stage, "[data-role=music-never]")
      end)

      # Meld Page 1
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Page closes: landed Track still playing as holdover
      closed_snapshot = Rooms.snapshot(ctx.slug, nil)
      assert closed_snapshot.playing.kind == "holdover"
      assert closed_snapshot.playing.path == p1_track_path

      # "One more?" keeps that Track through giving
      eventually(fn -> has_element?(ctx.melissa, "[data-role=one-more]") end)
      ctx.melissa |> element("[data-role=one-more]") |> render_click()
      await_phase(ctx.slug, :giving)

      giving_snapshot = Rooms.snapshot(ctx.slug, nil)
      assert giving_snapshot.playing.kind == "holdover"
      assert giving_snapshot.playing.path == p1_track_path

      eventually(fn ->
        has_element?(
          ctx.stage,
          "[data-role=now-playing]",
          "last Page's Track"
        )
      end)

      # Next is available again during holdover
      eventually(fn -> has_element?(ctx.stage, "[data-role=music-next]") end)

      # Gives submitted for Page 2
      give_setting(ctx.melissa, "deep woods")
      give_setting(ctx.jacob, "high peak")
      await_phase(ctx.slug, :bridging)

      # Next Track crossfades when it lands
      assert_push_event(ctx.stage, "foley:page", %{
        kind: "track",
        path: "/media/tracks/fake-deep woods-high peak.mp3"
      })

      # Next is hidden again on Page 2's Track
      eventually(fn -> not has_element?(ctx.stage, "[data-role=music-next]") end)
    end

    test "ticket 05: Next skips wait music only; Next is absent on this Page's Track; Never on a Repertoire member leaves it out in this Room only",
         ctx do
      # Initial wait music playing on Stage
      initial_snapshot = Rooms.snapshot(ctx.slug, nil)
      initial_path = initial_snapshot.playing.path

      # Tap Next on wait music: advances to a new Repertoire member; mode stays page
      ctx.stage |> element("[data-role=music-next]") |> render_click()

      assert_push_event(ctx.stage, "foley:page", %{
        kind: "repertoire",
        path: next_path,
        title: _next_title
      })

      refute next_path == initial_path
      assert Rooms.snapshot(ctx.slug, nil).music == "page"

      # Tap Never on this wait member: leaves it out of this Room's nevers and later draws
      ctx.stage |> element("[data-role=music-never]") |> render_click()
      assert_push_event(ctx.stage, "foley:page", %{kind: "repertoire", path: after_never_path})
      refute after_never_path == next_path

      room_id = Thereish.Rooms.Store.get_room(ctx.slug).id
      assert next_path in Thereish.Rooms.Store.list_nevers(room_id)
      # Refused member is excluded from later draws in this Room
      refute Enum.any?(Thereish.Foley.Repertoire.members(room_id), fn m -> m.path == next_path end)

      # In another Room: that same member remains eligible in draws
      other_slug = open_room()
      {:ok, _other_stage, _} = live(build_conn(), ~p"/r/#{other_slug}/stage")
      other_room_id = Rooms.Store.get_room(other_slug).id
      refute next_path in Thereish.Rooms.Store.list_nevers(other_room_id)

      assert Enum.any?(Thereish.Foley.Repertoire.members(other_room_id), fn m ->
               m.path == next_path
             end)

      # Now progress Page in ctx to bridging: this Page's Track lands
      give_setting(ctx.melissa, "setting alpha")
      give_setting(ctx.jacob, "setting beta")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{
        kind: "track",
        path: "/media/tracks/fake-setting alpha-setting beta.mp3"
      })

      # Next is absent on this Page's Track; Calling Next via API returns error
      eventually(fn -> not has_element?(ctx.stage, "[data-role=music-next]") end)
      speaker_token = Thereish.Rooms.Store.get_room(ctx.slug).speaker
      assert {:error, :refused} = Rooms.next(ctx.slug, speaker_token)
    end

    test "ticket 05: House plays Repertoire without score; flipping back to Written returns landed Track; Off silences music only",
         ctx do
      # 1. Flip to House: plays Repertoire
      ctx.stage |> element("[data-role=music-house]") |> render_click()
      eventually(fn -> Rooms.snapshot(ctx.slug, nil).music == "house" end)
      house_snapshot = Rooms.snapshot(ctx.slug, nil)
      assert house_snapshot.playing.kind == "repertoire"

      # In House mode: giving does not start a score
      give_setting(ctx.melissa, "cozy fireplace")
      give_setting(ctx.jacob, "warm blanket")
      await_phase(ctx.slug, :bridging)
      refute Rooms.snapshot(ctx.slug, nil).track

      # 2. Switch to Written for this Page: now starts score and lands track
      ctx.stage |> element("[data-role=music-page]") |> render_click()
      eventually(fn -> Rooms.snapshot(ctx.slug, nil).music == "page" end)

      assert_push_event(ctx.stage, "foley:page", %{
        kind: "track",
        path: landed_path
      })

      assert Rooms.snapshot(ctx.slug, nil).playing.kind == "track"

      # 3. Flip to House after Track landed: plays Repertoire, Track is kept
      ctx.stage |> element("[data-role=music-house]") |> render_click()
      eventually(fn -> Rooms.snapshot(ctx.slug, nil).music == "house" end)
      assert Rooms.snapshot(ctx.slug, nil).playing.kind == "repertoire"

      # Flip back to Written for this Page: returns the Track that already landed immediately
      ctx.stage |> element("[data-role=music-page]") |> render_click()
      eventually(fn -> Rooms.snapshot(ctx.slug, nil).music == "page" end)
      assert Rooms.snapshot(ctx.slug, nil).playing.kind == "track"
      assert Rooms.snapshot(ctx.slug, nil).playing.path == landed_path

      # 4. Off silences music only: playing becomes nil, foley:page pushes path: nil
      ctx.stage |> element("[data-role=music-off]") |> render_click()
      eventually(fn -> Rooms.snapshot(ctx.slug, nil).music == "off" end)
      assert Rooms.snapshot(ctx.slug, nil).playing == nil
      assert_push_event(ctx.stage, "foley:page", %{path: nil})

      # Stings still work under Off
      commit(ctx.melissa, "cozy")
      commit(ctx.jacob, "cozy")
      await_reveal(ctx.slug)
      assert_push_event(ctx.stage, "foley:sting", %{})
    end

    test "ticket 05: without a Stage, the claiming phone is the only one that plays the chain; Next and Never live there" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      join(melissa, "Melissa")
      join(jacob, "Jacob")

      # Before claiming: neither phone plays sound or shows Next/Never
      refute has_element?(melissa, "[data-role=music-next]")
      refute has_element?(melissa, "[data-role=music-never]")
      refute has_element?(jacob, "[data-role=music-next]")
      refute has_element?(jacob, "[data-role=music-never]")
      refute_push_event(melissa, "foley:page", %{})
      refute_push_event(jacob, "foley:page", %{})

      # Melissa claims speaker
      melissa |> element("[data-role=speaker-toggle]") |> render_click()

      # Only Melissa gets foley:page; Next and Never live on Melissa
      assert_push_event(melissa, "foley:page", %{kind: "repertoire"})
      refute_push_event(jacob, "foley:page", %{})
      assert has_element?(melissa, "[data-role=music-next]")
      assert has_element?(melissa, "[data-role=music-never]")
      refute has_element?(jacob, "[data-role=music-next]")
      refute has_element?(jacob, "[data-role=music-never]")

      # Jacob claims speaker: transfers to Jacob, Melissa is silenced
      jacob |> element("[data-role=speaker-toggle]") |> render_click()

      assert_push_event(jacob, "foley:page", %{kind: "repertoire"})
      assert_push_event(melissa, "foley:stop", %{})
      assert has_element?(jacob, "[data-role=music-next]")
      assert has_element?(jacob, "[data-role=music-never]")
      refute has_element?(melissa, "[data-role=music-next]")
      refute has_element?(melissa, "[data-role=music-never]")
    end

    test "ticket 05: Foley track generation records charges visible on /spend", ctx do
      give_setting(ctx.melissa, "setting emerald")
      give_setting(ctx.jacob, "setting sapphire")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{kind: "track", path: _})

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      {:ok, _view, html} = live(build_conn(), ~p"/spend")
      assert html =~ "Foley"
    end

    test "commit pushes foley:commit to stage and foley:own-commit to nobody when stage is present",
         ctx do
      give_setting(ctx.melissa, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)
      eventually(fn -> has_element?(ctx.melissa, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.jacob, "[data-role=bridge-form]") end)

      commit(ctx.melissa, "cairn")

      assert_push_event(ctx.stage, "foley:commit", %{})
      refute_push_event(ctx.melissa, "foley:own-commit", %{})
      refute_push_event(ctx.jacob, "foley:commit", %{})
      refute_push_event(ctx.jacob, "foley:own-commit", %{})
      refute_push_event(ctx.melissa, "foley:commit", %{})
      refute_push_event(ctx.stage, "foley:own-commit", %{})

      commit(ctx.jacob, "cairo")

      assert_push_event(ctx.stage, "foley:commit", %{})
      refute_push_event(ctx.jacob, "foley:own-commit", %{})
      refute_push_event(ctx.melissa, "foley:commit", %{})
      refute_push_event(ctx.melissa, "foley:own-commit", %{})
      refute_push_event(ctx.jacob, "foley:commit", %{})
      refute_push_event(ctx.stage, "foley:own-commit", %{})
    end

    test "with no Stage and one phone holding Speaker, commit pushes foley:own-commit to committer and foley:commit to nobody" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      join(melissa, "Melissa")
      join(jacob, "Jacob")

      melissa |> element("[data-role=speaker-toggle]") |> render_click()
      assert has_element?(melissa, "[data-role=speaker-toggle][data-speaker=self]")

      assert has_element?(
               melissa,
               "[data-role=local-sound-toggle][title=\"Toggle commit sound on this device\"]"
             )

      give_setting(melissa, "setting one")
      give_setting(jacob, "setting two")
      await_phase(slug, :bridging)
      eventually(fn -> has_element?(melissa, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(jacob, "[data-role=bridge-form]") end)

      commit(melissa, "cairn")

      assert_push_event(melissa, "foley:own-commit", %{})
      refute_push_event(melissa, "foley:commit", %{})
      refute_push_event(jacob, "foley:commit", %{})
      refute_push_event(jacob, "foley:own-commit", %{})

      commit(jacob, "cairo")

      assert_push_event(jacob, "foley:own-commit", %{})
      refute_push_event(jacob, "foley:commit", %{})
      refute_push_event(melissa, "foley:commit", %{})
      refute_push_event(melissa, "foley:own-commit", %{})
    end

    test "stage leaving mid-Page moves commit sound to committer phone on next commit" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      join(melissa, "Melissa")
      join(jacob, "Jacob")

      give_setting(melissa, "setting one")
      give_setting(jacob, "setting two")
      await_phase(slug, :bridging)
      eventually(fn -> has_element?(melissa, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(jacob, "[data-role=bridge-form]") end)

      # First commit with Stage present: Stage sounds, phones are quiet
      commit(melissa, "cairn")
      assert_push_event(stage, "foley:commit", %{})
      refute_push_event(melissa, "foley:own-commit", %{})
      refute_push_event(jacob, "foley:own-commit", %{})

      # Stage leaves mid-Page
      GenServer.stop(stage.pid)
      eventually(fn -> not ThereishWeb.Presence.stage_present?(slug) end)

      # Second commit with Stage gone: committer phone sounds
      commit(jacob, "cairo")
      assert_push_event(jacob, "foley:own-commit", %{})
      refute_push_event(melissa, "foley:own-commit", %{})
    end

    test "stage joining mid-Page moves commit sound to Stage on next commit" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      join(melissa, "Melissa")
      join(jacob, "Jacob")

      give_setting(melissa, "setting one")
      give_setting(jacob, "setting two")
      await_phase(slug, :bridging)
      eventually(fn -> has_element?(melissa, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(jacob, "[data-role=bridge-form]") end)

      # First commit with no Stage: committer phone sounds
      commit(melissa, "cairn")
      assert_push_event(melissa, "foley:own-commit", %{})
      refute_push_event(jacob, "foley:own-commit", %{})

      # Stage joins mid-Page
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      eventually(fn -> ThereishWeb.Presence.stage_present?(slug) end)

      # Second commit with Stage now present: Stage sounds, phones are quiet
      commit(jacob, "cairo")
      assert_push_event(stage, "foley:commit", %{})
      refute_push_event(jacob, "foley:own-commit", %{})
      refute_push_event(melissa, "foley:own-commit", %{})
    end
  end

  describe "Sides: couple versus couple on phone and stage" do
    setup do
      beat(0)
      steward(delay_ms: 0)
      :ok
    end

    test "four players pair into Sides, see side-by-side reveal cards, and meld together" do
      code = open_room(seat_limit: 4)

      conn1 = build_conn()
      {:ok, phone1, _} = live(conn1, ~p"/r/#{code}")
      join(phone1, "Melissa")

      conn2 = build_conn()
      {:ok, phone2, _} = live(conn2, ~p"/r/#{code}")
      join(phone2, "Jacob")

      conn3 = build_conn()
      {:ok, phone3, _} = live(conn3, ~p"/r/#{code}")
      join(phone3, "Ada")

      conn4 = build_conn()
      {:ok, phone4, _} = live(conn4, ~p"/r/#{code}")
      join(phone4, "Sam")

      # Partner picker appears on all phones
      for phone <- [phone1, phone2, phone3, phone4] do
        assert has_element?(phone, "[data-role=partner-picker]")
      end

      # Melissa picks Jacob -> 4-seat room automatically completes both Sides
      phone1 |> element("button", "I'm with Jacob") |> render_click()

      eventually(fn ->
        Rooms.snapshot(code, nil).sides_mode?
      end)

      # All phones see paired notice and Sides roster
      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=sides-roster]") end)
        assert has_element?(phone, "[data-role=paired-notice]")
        assert has_element?(phone, "[data-side=a]")
        assert has_element?(phone, "[data-side=b]")
      end

      # Test unpairing: Ada clicks Change pairs
      phone3 |> element("[data-role=unpair-partner]") |> render_click()
      eventually(fn -> not Rooms.snapshot(code, nil).sides_mode? end)

      # Now Ada picks Sam -> both Sides active again
      phone3 |> element("button", "I'm with Sam") |> render_click()
      eventually(fn -> Rooms.snapshot(code, nil).sides_mode? end)

      # Submit 4 settings
      give_setting(phone1, "coastal lighthouse in storm")
      give_setting(phone2, "old library with rolling ladders")
      give_setting(phone3, "artisan glassblowing workshop")
      give_setting(phone4, "mountain observatory at dusk")

      await_phase(code, :bridging)

      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=bridge-form]") end)
      end

      # Melissa and Jacob write matching prefixes ("cairn" and "cairns" -> score 91, meld)
      commit(phone1, "cairn")
      commit(phone2, "cairns")
      commit(phone3, "beacon")
      commit(phone4, "seagull")

      # Reveal lands and Page melds
      await_phase(code, :closed)

      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=sides-comparison]") end)
        assert has_element?(phone, "[data-role=side-card][data-side=a]")
        assert has_element?(phone, "[data-role=side-card][data-side=b]")
        assert has_element?(phone, "[data-role=closeness]", "91")
        assert has_element?(phone, "[data-role=melded-badge]")
        assert has_element?(phone, "[data-role=one-more]")
      end

      # Melissa taps fairness
      phone1 |> element("[data-role=tap-fair]") |> render_click()
      eventually(fn -> has_element?(phone1, "[data-role=seat-tap]", "fair") end)
    end

    test "an overrule in Sides mode requires only the proposing Side's partner to agree" do
      code = open_room(seat_limit: 4)

      conn1 = build_conn()
      {:ok, phone1, _} = live(conn1, ~p"/r/#{code}")
      join(phone1, "Melissa")

      conn2 = build_conn()
      {:ok, phone2, _} = live(conn2, ~p"/r/#{code}")
      join(phone2, "Jacob")

      conn3 = build_conn()
      {:ok, phone3, _} = live(conn3, ~p"/r/#{code}")
      join(phone3, "Ada")

      conn4 = build_conn()
      {:ok, phone4, _} = live(conn4, ~p"/r/#{code}")
      join(phone4, "Sam")

      # Pair into Sides: Melissa picks Jacob
      phone1 |> element("button", "I'm with Jacob") |> render_click()
      eventually(fn -> Rooms.snapshot(code, nil).sides_mode? end)

      give_setting(phone1, "setting one")
      give_setting(phone2, "setting two")
      give_setting(phone3, "setting three")
      give_setting(phone4, "setting four")

      await_phase(code, :bridging)

      # Bridges that do NOT meld
      commit(phone1, "beacon")
      commit(phone2, "pier")
      commit(phone3, "beacon")
      commit(phone4, "seagull")

      await_reveal(code)

      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=propose-overrule]") end)
      end

      # Melissa proposes overrule
      phone1 |> element("[data-role=propose-overrule]") |> render_click()

      # Melissa sees waiting for partner
      assert render(phone1) =~ "Waiting for your partner to agree"

      # Jacob (partner) sees Agree / Decline buttons
      eventually(fn -> has_element?(phone2, "[data-role=agree-overrule]") end)

      # Ada and Sam (other side) do NOT see Agree / Decline buttons
      refute has_element?(phone3, "[data-role=agree-overrule]")
      refute has_element?(phone4, "[data-role=agree-overrule]")
      assert render(phone3) =~ "Waiting for their partner to agree"
      assert render(phone4) =~ "Waiting for their partner to agree"

      # Jacob agrees
      phone2 |> element("[data-role=agree-overrule]") |> render_click()

      # Overrule succeeds: page closes as Meld
      await_phase(code, :closed)

      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=overruled-notice]") end)
        assert has_element?(phone, "[data-role=one-more]")
      end
    end
  end

  describe "couples on the meld map (ticket 07)" do
    test "joining with a partner marks couple in roster and offers partner dropdown in join form" do
      slug = open_room(seat_limit: 4)

      {:ok, melissa, _} = live(phone(slug))
      join(melissa, "Melissa")

      # Jacob arrives and sees partner dropdown listing Melissa
      {:ok, jacob, html} = live(phone(slug))
      assert html =~ ~s(data-role="partner-select")
      assert html =~ "With Melissa"

      # Melissa's seat ID
      [melissa_seat] = Rooms.snapshot(slug, nil).seats

      # Jacob joins with Melissa as partner
      jacob
      |> form("form", %{"name" => "Jacob", "partner_id" => melissa_seat.id})
      |> render_submit()

      # Both phones and stage show the couple in the roster
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      for view <- [melissa, jacob, stage] do
        assert has_element?(view, "[data-role=partner]", "(with Melissa)") or
                 has_element?(view, "[data-role=partner]", "(with Jacob)")
      end
    end

    test "reveal on phone highlights own couple score and marks cross-couple melds; stage draws meld map" do
      slug = open_room(seat_limit: 4)

      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, bryan, _} = live(phone(slug))
      {:ok, evelyn, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      [melissa_seat] = Rooms.snapshot(slug, nil).seats

      jacob
      |> form("form", %{"name" => "Jacob", "partner_id" => melissa_seat.id})
      |> render_submit()

      join(bryan, "Bryan")
      [_, _, bryan_seat] = Rooms.snapshot(slug, nil).seats

      evelyn
      |> form("form", %{"name" => "Evelyn", "partner_id" => bryan_seat.id})
      |> render_submit()

      # Submit settings for all 4 seats
      for {v, name} <- [
            {melissa, "setting 1"},
            {jacob, "setting 2"},
            {bryan, "setting 3"},
            {evelyn, "setting 4"}
          ] do
        give_setting(v, name)
      end

      await_phase(slug, :bridging)

      for v <- [melissa, jacob, bryan, evelyn] do
        eventually(fn -> has_element?(v, "[data-role=bridge-form]") end)
      end

      # Melissa and Jacob meld ("cairn" and "cairn" -> 100)
      # Bryan commits "dock"
      # Evelyn commits "cairn" (Evelyn melds with Melissa & Jacob -> cross-couple meld!)
      commit(melissa, "cairn")
      commit(jacob, "cairn")
      commit(bryan, "dock")
      commit(evelyn, "cairn")

      await_reveal_on(melissa)
      await_reveal_on(stage)

      # Melissa's phone shows her couple closeness
      assert has_element?(melissa, "[data-role=own-couple-pair]")
      assert has_element?(melissa, "[data-role=couple-closeness]", "100")

      # Melissa's phone shows surprise cross-couple meld alert
      assert has_element?(melissa, "[data-role=cross-couple-meld]")

      # Stage draws meld map with couple badges and cross-couple meld
      assert has_element?(stage, "[data-role=meld-map]")
      assert has_element?(stage, "[data-role=couple-badge]")
      assert has_element?(stage, "[data-role=cross-couple-meld]")
    end
  end

  describe "the Room starts when everyone is here (ticket 08)" do
    test "count-free start with Start Page button and late seat joins next page" do
      # 1. Front page -> New Room (no player count chosen, opens at seat cap 6)
      conn1 = build_conn()
      {:ok, front, _} = live(conn1, ~p"/")
      assert has_element?(front, "[data-role=new-room]")

      {:ok, new_room_view, _} = live(conn1, ~p"/new")
      refute has_element?(new_room_view, "select[name=players]")

      assert {:error, {:live_redirect, %{to: to}}} =
               new_room_view |> form("form") |> render_submit()

      "/r/" <> code = to
      on_exit(fn -> stop_room(code) end)

      assert Rooms.snapshot(code, nil).seat_limit == 6

      # Phone 1 connects and joins
      {:ok, phone1, _} = live(conn1, to)
      join(phone1, "Melissa")

      # Phone 2 connects and joins
      conn2 = build_conn()
      {:ok, phone2, _} = live(conn2, to)
      join(phone2, "Jacob")

      # Both phones see setting form, no start page button yet (< 2 gives)
      assert has_element?(phone1, "[data-role=setting-form]")
      assert has_element?(phone2, "[data-role=setting-form]")
      refute has_element?(phone1, "[data-role=start-page]")
      refute has_element?(phone2, "[data-role=start-page]")

      # Phone 1 sets give
      give_setting(phone1, "coastal lighthouse in storm")
      refute has_element?(phone1, "[data-role=start-page]")
      refute has_element?(phone2, "[data-role=start-page]")

      # Phone 2 sets give -> gives_in is 2, so both see Start Page button!
      give_setting(phone2, "old library with rolling ladders")
      eventually(fn -> has_element?(phone1, "[data-role=start-page]") end)
      eventually(fn -> has_element?(phone2, "[data-role=start-page]") end)

      # Phone 3 joins before start
      conn3 = build_conn()
      {:ok, phone3, _} = live(conn3, to)
      join(phone3, "Ada")
      assert has_element?(phone3, "[data-role=setting-form]")
      refute has_element?(phone3, "[data-role=start-page]")

      # Phone 3 gives setting too
      give_setting(phone3, "artisan glassblowing workshop")
      assert has_element?(phone3, "[data-role=start-page]")

      # Phone 1 taps Start Page
      phone1 |> element("[data-role=start-page]") |> render_click()
      await_phase(code, :bridging)

      # Phones 1, 2, 3 are in bridging phase with bookends and bridge forms
      for phone <- [phone1, phone2, phone3] do
        eventually(fn -> has_element?(phone, "[data-role=bookends]") end)
        assert has_element?(phone, "[data-role=bridge-form]")
        refute has_element?(phone, "[data-role=late-seat]")
      end

      # Phone 4 connects and joins late (mid-Page)
      conn4 = build_conn()
      {:ok, phone4, _} = live(conn4, to)
      join(phone4, "Sam")

      # Phone 4 sees late-seat notice and no bridge form
      eventually(fn -> has_element?(phone4, "[data-role=late-seat]") end)
      assert render(phone4) =~ "You joined mid-Page. Watching this Page"
      refute has_element?(phone4, "[data-role=bridge-form]")

      # Roster shows Sam is watching
      assert has_element?(phone4, "[data-role=roster]", "Sam")
      assert render(phone4) =~ "(watching)"

      # Phones 1, 2, 3 commit their bridges
      commit(phone1, "beacon")
      commit(phone2, "cairn")
      commit(phone3, "lamp")

      # Reveal arrives on all phones
      for phone <- [phone1, phone2, phone3, phone4] do
        await_reveal_on(phone)
      end

      # Late seat (phone4) does NOT see propose overrule or fairness controls or again
      refute has_element?(phone4, "[data-role=propose-overrule]")
      refute has_element?(phone4, "[data-role=fairness-controls]")
      refute has_element?(phone4, "[data-role=again]")

      # Participating seat sees overrule button and fairness controls and again
      assert has_element?(phone1, "[data-role=propose-overrule]")
      assert has_element?(phone1, "[data-role=fairness-controls]")
      assert has_element?(phone1, "[data-role=again]")

      # Propose overrule: Phone 1 proposes
      phone1 |> element("[data-role=propose-overrule]") |> render_click()

      # Late seat does NOT see agree/decline buttons
      refute has_element?(phone4, "[data-role=agree-overrule]")
      refute has_element?(phone4, "[data-role=decline-overrule]")
      assert render(phone4) =~ "proposed an overrule. Waiting for the Room to agree."

      # Only phones 2 and 3 need to agree (unanimity among participating seats!)
      phone2 |> element("[data-role=agree-overrule]") |> render_click()
      refute Rooms.snapshot(code, nil).reveal.melded?

      phone3 |> element("[data-role=agree-overrule]") |> render_click()
      assert Rooms.snapshot(code, nil).phase == :closed

      # Room is closed. Phone 4 (late seat) sees One more?
      eventually(fn -> has_element?(phone4, "[data-role=one-more]") end)

      # Phone 4 taps One more?
      phone4 |> element("[data-role=one-more]") |> render_click()

      # Now all four phones have fresh setting-forms for the new Page!
      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=setting-form]") end)
        refute has_element?(phone, "[data-role=late-seat]")
      end
    end
  end
end
