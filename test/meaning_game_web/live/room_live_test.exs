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

  defp commit(view, bridge) do
    view |> form("[data-role=bridge-form]", %{"bridge" => bridge}) |> render_submit()
  end

  defp give_setting(view, give) do
    view |> form("[data-role=give-form]", %{"give" => give}) |> render_submit()
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

  describe "playing a Page" do
    setup do
      slug = open_room()
      melissa_conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, melissa, _} = live(melissa_conn)
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      %{slug: slug, melissa: melissa, melissa_conn: melissa_conn, jacob: jacob, stage: stage}
    end

    test "the Bookends are up on both phones and the stage", ctx do
      for view <- [ctx.melissa, ctx.jacob, ctx.stage] do
        assert has_element?(view, "[data-role=bookends]", "lantern")
        assert has_element?(view, "[data-role=bookends]", "harbour")
      end
    end

    test "an illegal bridge is caught on the phone before commit and on commit", ctx do
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
      assert has_element?(ctx.melissa, "[data-role=your-bridge]", "beacon")
      refute has_element?(ctx.melissa, "[data-role=bridge-form]")
    end

    test "a Bridge is written on one phone and seen on none of the others", ctx do
      commit(ctx.melissa, "cairn")

      assert has_element?(ctx.melissa, "[data-role=your-bridge]", "cairn")
      refute has_element?(ctx.melissa, "[data-role=bridge-form]")

      refute render(ctx.jacob) =~ "cairn"
      refute render(ctx.stage) =~ "cairn"

      # What the other phone and the stage are told is that she is done, and
      # nothing else.
      for view <- [ctx.jacob, ctx.stage] do
        assert has_element?(view, "[data-seat][data-committed=true]", "Melissa")
        assert has_element?(view, "[data-seat][data-committed=false]", "Jacob")
      end

      assert has_element?(ctx.jacob, "[data-role=bridge-form]")
    end

    test "the last commit reveals both Bridges, graded, on all three screens", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- [ctx.melissa, ctx.jacob, ctx.stage] do
        html = await_reveal_on(view)

        assert html =~ "cairn"
        assert html =~ "cairo"
        assert has_element?(view, "[data-role=closeness]", "80")
        assert has_element?(view, "[data-role=band]", "meld")
        assert has_element?(view, "[data-role=reasoning]", "share 4 letters")
        # The joke is about the two words they actually wrote, and it is on
        # every screen the number is on (ADR-0005).
        assert has_element?(view, "[data-role=quip]", "\"cairn\" and \"cairo\"")
      end
    end

    test "a slow Assayer is narrated on every screen rather than left as a hang", ctx do
      escalation(slow: 50, provisional: 400, unavailable: 700)
      steward(delay_ms: 5_000)

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- [ctx.melissa, ctx.jacob, ctx.stage] do
        assert eventually(fn -> has_element?(view, "[data-role=phase][data-step=slow]") end)
      end

      assert eventually(fn ->
               has_element?(ctx.stage, "[data-role=phase][data-step=provisional]")
             end)

      # And when it never answers, the game says so and the call is theirs.
      html = await_reveal_on(ctx.stage)

      assert html =~ "No verdict"
      assert html =~ "yours to call"
    end

    test "tapping next_page when pool is exhausted displays a friendly message", ctx do
      # Insert 1 page into pool
      {:ok, _page} =
        MeaningGame.Pages.insert_page(%{
          id: "P-LV-POOL",
          chapter: "pool test",
          theme: "pool test",
          give: nil,
          bookends: ["sun", "sand"],
          bait: "beach",
          deep_bridges: ["dune", "tide"],
          likely_bridges: ["beach", "dune", "tide"],
          why_these: "Sun and sand invite beach.",
          band_scripts: %{
            "miss" => "Away from water.",
            "adjacent" => "Near the shore.",
            "close" => "Passable. On the sand.",
            "meld" => "At the beach.",
            "deep_meld" => "In the dunes."
          },
          meta: %{model: "fake", attempts: 1, cost_usd: 0.0}
        })

      # Mark this page as already played so pool has pages in table but none unplayed
      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: ctx.slug)
      {:ok, _} = MeaningGame.Pages.draw(room.id)

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")
      await_reveal_on(ctx.stage)

      # Room is closed because cairn and cairo meld
      assert has_element?(ctx.melissa, "[data-role=one-more]")

      # Tapping "one-more" calls next_page; pool is exhausted
      render_click(element(ctx.melissa, "[data-role=one-more]"))

      assert has_element?(ctx.melissa, "[data-role=page-error]", "That's every Page for tonight.")
    end

    test "a miss is graded and said out loud, same as a Meld", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "beacon")

      html = await_reveal_on(ctx.stage)

      assert html =~ "cairn"
      assert html =~ "beacon"
      assert has_element?(ctx.stage, "[data-role=closeness]", "0")
      assert has_element?(ctx.stage, "[data-role=band]", "miss")
    end

    test "a phone that locked through the reveal wakes into it", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")
      await_reveal_on(ctx.stage)

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

      html = await_reveal_on(ctx.stage)

      assert html =~ "cairn"
      assert html =~ "No verdict"
      refute has_element?(ctx.stage, "[data-role=closeness]")
    end
  end

  describe "a Page that misses, and a Page that ends" do
    setup do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      %{
        slug: slug,
        melissa: melissa,
        jacob: jacob,
        stage: stage,
        screens: [melissa, jacob, stage]
      }
    end

    defp press(view, role), do: view |> element("[data-role=#{role}]") |> render_click()

    defp miss(ctx, melissa_bridge \\ "cairn", jacob_bridge \\ "beacon") do
      commit(ctx.melissa, melissa_bridge)
      commit(ctx.jacob, jacob_bridge)

      await_reveal_on(ctx.stage)
    end

    test "the failed Bridges become the next attempt's Bookends, on every screen", ctx do
      miss(ctx)

      # The tap says what it is going to do before it does it.
      assert has_element?(ctx.melissa, "[data-role=again]", "cairn and beacon")
      assert has_element?(ctx.stage, "[data-role=carry-forward]")
      refute has_element?(ctx.stage, "[data-role=again]")

      press(ctx.melissa, "again")

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=bookends]", "cairn")
        assert has_element?(view, "[data-role=bookends]", "beacon")
        assert has_element?(view, "[data-role=attempt]", "Attempt 2 of 5")
        refute has_element?(view, "[data-role=reveal]")
      end

      assert has_element?(ctx.jacob, "[data-role=bridge-form]")
    end

    test "a Meld is the end of the Page and says so", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")
      await_reveal_on(ctx.stage)

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=ending-line]", "melded first try")
        # The grade the reveal landed on is still up under it.
        assert has_element?(view, "[data-role=closeness]", "80")
        refute has_element?(view, "[data-role=again]")
        refute has_element?(view, "[data-role=attempt]")
      end

      assert has_element?(ctx.melissa, "[data-role=one-more]")
      refute has_element?(ctx.stage, "[data-role=one-more]")
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

    test "one more? is one tap, and the next Page is up for both of them", ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")
      await_reveal_on(ctx.stage)

      press(ctx.melissa, "one-more")

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=bookends]", "desert")
        assert has_element?(view, "[data-role=attempt]", "Attempt 1 of 5")
        refute has_element?(view, "[data-role=ending]")
        refute has_element?(view, "[data-role=reveal]")
      end

      # Same Seats, no name retyped, straight into the next Page.
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
      refute MeaningGame.Repo.get_by(MeaningGame.Rooms.Room, slug: "nobodyshome")
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

      for {view, bridge} <- phones, do: commit(view, bridge)

      await_reveal_on(stage)

      # Every Bridge, one number in one band, one quip, one line of reasoning,
      # and the two words the table is sent to next (ADR-0010).
      for bridge <- ~w(cairn cairo beacon) do
        assert has_element?(stage, "[data-bridge]", bridge)
      end

      assert has_element?(stage, "[data-role=closeness]")
      assert has_element?(stage, "[data-role=quip]")
      assert has_element?(stage, "[data-role=reasoning]")
      assert has_element?(stage, "[data-role=furthest]", "beacon (Ada)")
      refute has_element?(stage, "[data-role=pair]")

      # Two of three landing on one word is not the table being of one mind.
      assert has_element?(stage, "[data-role=band]", "miss")
    end

    test "shows the URL a phone should open" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      assert has_element?(stage, "[data-role=join-url]", "/r/#{slug}")
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

      # "cairn" and "beacon" share no prefix -> fake assayer grades 0
      commit(melissa, "cairn")
      commit(jacob, "beacon")

      await_reveal_on(melissa)
      await_reveal_on(jacob)
      await_reveal_on(stage)

      assert has_element?(melissa, "[data-role=closeness]", "0")
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

      # Grade remains 0 while pending
      assert has_element?(melissa, "[data-role=closeness]", "0")
      assert has_element?(jacob, "[data-role=closeness]", "0")

      # Jacob agrees
      jacob |> element("[data-role=agree-overrule]") |> render_click()

      # Overrule takes effect on all three views: grade 100, melded!
      for view <- [melissa, jacob, stage] do
        assert has_element?(view, "[data-role=closeness]", "100")
        assert has_element?(view, "[data-role=band]", "deep meld")
        assert render(view) =~ "Overruled jointly"
      end

      # Ending shows it melded
      assert has_element?(stage, "[data-role=ending-line]", "melded first try")

      # "One more?" starts the next page cleanly
      assert has_element?(melissa, "[data-role=one-more]")
      melissa |> element("[data-role=one-more]") |> render_click()

      for view <- [melissa, jacob, stage] do
        assert has_element?(view, "[data-role=attempt]", "Attempt 1 of")
        refute render(view) =~ "Overruled"
      end
    end

    test "declining an overrule leaves the grade untouched" do
      slug = open_room()
      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))

      join(melissa, "Melissa")
      join(jacob, "Jacob")

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
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      %{
        slug: slug,
        melissa: melissa,
        jacob: jacob,
        stage: stage,
        screens: [melissa, jacob, stage]
      }
    end

    test "the 2.5s beat is visibly a beat, not a spinner, on both phones and the stage", ctx do
      beat(500)

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=beat-meter]")
        refute render(view) =~ "loading-spinner"
        refute render(view) =~ "spinner"
      end

      await_reveal_on(ctx.stage)
    end

    test "reveal lands: side-by-side comparison first, climbing number, quip punchline, and phone vs stage split",
         ctx do
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- ctx.screens do
        await_reveal_on(view)
        assert has_element?(view, "[data-role=comparison]")
        assert has_element?(view, "[data-role=closeness]", "80")
        assert has_element?(view, "[data-role=band]", "meld")
        assert render(view) =~ "ClimbNumber"
        assert has_element?(view, "[data-role=reasoning]")
        assert render(view) =~ "reasoning"
        assert has_element?(view, "[data-role=quip]")
        assert has_element?(view, "[data-arrival=meld]")
        assert render(view) =~ "One mind, two heads"
      end

      # Phone distinguishes your bridge with (you)
      assert has_element?(ctx.melissa, "[data-bridge][data-you=true]", "Melissa")
      assert has_element?(ctx.melissa, "[data-bridge][data-you=false]", "Jacob")

      # Stage has public stage mode and no private (you) attribution
      assert has_element?(ctx.stage, "[data-mode=stage]")
      refute has_element?(ctx.stage, "[data-bridge][data-you=true]")
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
      steward(mode: :unavailable)

      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")

      await_reveal_on(ctx.stage)

      assert has_element?(ctx.stage, "[data-role=no-verdict]")
      assert render(ctx.stage) =~ "The Assayer steps aside"
      assert render(ctx.stage) =~ "No verdict. This one is yours to call."
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

      commit(melissa, "cairn")
      commit(jacob, "cairo")

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
      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: ctx.slug)
      taps = MeaningGame.Chronicle.fairness_taps(room.id)
      assert length(taps) == 2
      assert Enum.map(taps, & &1.label) |> Enum.sort() == ["fair", "too_harsh"]
    end

    test "tapping never blocks or delays the next attempt", ctx do
      ctx.melissa |> element("[data-role=tap-fair]") |> render_click()

      # Next page / again button is present and usable immediately
      assert has_element?(ctx.melissa, "[data-role=one-more]")
      ctx.melissa |> element("[data-role=one-more]") |> render_click()

      assert render(ctx.melissa) =~ "The word between them"
    end
  end

  describe "naming a setting on the phone (ticket 12)" do
    setup do
      slug = open_room()

      {:ok, melissa, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(melissa, "Melissa")
      join(jacob, "Jacob")

      steward = Application.fetch_env!(:meaning_game, :steward)
      on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

      %{slug: slug, melissa: melissa, jacob: jacob, stage: stage, steward: steward}
    end

    test "a Give can be typed from a phone in free language, announced on stage, and moves the game there",
         ctx do
      # Configure fake author to take 20ms per page
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_delay_ms: 20, author_mode: :ok)
        )
      )

      # Give form is visible on phones
      assert has_element?(ctx.melissa, "[data-role=give-form]")
      assert has_element?(ctx.jacob, "[data-role=give-form]")

      give = "the world St. Thérèse grew up in"
      give_setting(ctx.melissa, give)

      # Immediate status feedback on phone
      assert has_element?(
               ctx.melissa,
               "[data-role=give-status]",
               "The Author is writing Pages for"
             )

      # Play continues meanwhile!
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")
      await_reveal_on(ctx.melissa)

      # Stage announces when Pages land
      eventually(
        fn ->
          has_element?(ctx.stage, "[data-role=give-announcement]") &&
            render(ctx.stage) =~ "The Author heard you"
        end,
        "the stage never announced the Give arrival"
      )

      assert has_element?(ctx.stage, "[data-role=give-announcement]", give)

      assert has_element?(
               ctx.melissa,
               "[data-role=give-status]",
               "Pages for \"#{give}\" have arrived."
             )

      # Tap 'One more?' to move to the new setting
      assert has_element?(ctx.melissa, "[data-role=one-more]")
      ctx.melissa |> element("[data-role=one-more]") |> render_click()

      # Both phones and stage now show the Setting tag!
      eventually(
        fn ->
          has_element?(ctx.melissa, "[data-role=page-give]") &&
            has_element?(ctx.stage, "[data-role=page-give]")
        end,
        "the page never showed the Setting tag"
      )

      assert has_element?(ctx.melissa, "[data-role=page-give]", "Setting: #{give}")
      assert has_element?(ctx.stage, "[data-role=page-give]", "Setting: #{give}")
    end

    test "a failed or refused Author run is surfaced honestly on stage and phone and leaves play intact",
         ctx do
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

      give = "forbidden territory"
      give_setting(ctx.melissa, give)

      # Stage announces failure honestly
      eventually(
        fn ->
          has_element?(ctx.stage, "[data-role=give-failure]", "The Author couldn't write")
        end,
        "the stage never showed the Give failure notice"
      )

      assert has_element?(ctx.stage, "[data-role=give-failure]", give)
      assert has_element?(ctx.melissa, "[data-role=give-status]", "Playing on.")

      # The evening remains playable:
      commit(ctx.melissa, "cairn")
      commit(ctx.jacob, "cairo")
      await_reveal_on(ctx.melissa)
      assert has_element?(ctx.melissa, "[data-role=reveal]")
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
end
