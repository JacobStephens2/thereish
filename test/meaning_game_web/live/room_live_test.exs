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
    view |> form("[data-role=setting-form]", %{"give" => give}) |> render_submit()
  end

  defp play_to_bridging(mara, jacob, slug, give1 \\ "setting one", give2 \\ "setting two") do
    give_setting(mara, give1)
    give_setting(jacob, give2)
    await_phase(slug, :bridging)
    eventually(fn -> has_element?(mara, "[data-role=bridge-form]") end)
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

  describe "joining" do
    test "a phone types a name and is in the Room" do
      slug = open_room()
      {:ok, mara, html} = live(phone(slug))

      assert html =~ "Nobody yet"

      html = join(mara, "Mara")

      assert html =~ "You are"
      assert has_element?(mara, "[data-seat]", "Mara")
      refute has_element?(mara, "form")
    end

    test "two phones and a stage all show the same roster" do
      slug = open_room()

      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")

      for view <- [mara, jacob, stage] do
        assert has_element?(view, "[data-seat]", "Mara")
        assert has_element?(view, "[data-seat]", "Jacob")
      end

      assert render(stage) =~ "All 2 seats taken"
    end

    test "each phone is told which Seat is its own, and the stage holds none" do
      slug = open_room()

      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")

      assert render(mara) =~ "You are <span class=\"font-semibold\">Mara</span>"
      assert render(jacob) =~ "You are <span class=\"font-semibold\">Jacob</span>"
      refute render(stage) =~ "You are"
    end

    test "a phone with no name typed is told to type one" do
      slug = open_room()

      {:ok, mara, _} = live(phone(slug))

      assert join(mara, "  ") =~ "Type a name first."
      assert has_element?(mara, "form")
    end

    test "a phone arriving at a full Room is told so" do
      slug = open_room(seat_limit: 2)
      {:ok, _} = Rooms.join(slug, "Mara", device_token())
      {:ok, _} = Rooms.join(slug, "Jacob", device_token())

      {:ok, ada, _} = live(phone(slug))

      assert join(ada, "Ada") =~ "Every seat is taken"
    end
  end

  describe "coming back" do
    test "a browser that already holds a Seat is back in it without typing" do
      slug = open_room()
      conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, mara, _} = live(conn)
      join(mara, "Mara")

      # Reload: same cookie, no form, name already up.
      {:ok, again, _} = live(get(conn, ~p"/r/#{slug}"))

      assert render(again) =~ "You are <span class=\"font-semibold\">Mara</span>"
      refute has_element?(again, "form")
    end

    test "a device token that belongs to another Room cannot claim a Seat" do
      room_a = open_room()
      room_b = open_room()

      conn = get(build_conn(), ~p"/r/#{room_a}")
      {:ok, view, _} = live(conn)
      join(view, "Mara")

      # Same browser visits Room B. It does not own a Seat there, so it is
      # asked for a name like anyone else.
      {:ok, in_b, _} = live(get(conn, ~p"/r/#{room_b}"))

      assert has_element?(in_b, "form")
      refute render(in_b) =~ "You are"
    end

    test "a phone whose socket dies mid-Room comes back to the identical view" do
      slug = open_room()
      conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, mara, _} = live(conn)
      join(mara, "Mara")
      {:ok, _} = Rooms.join(slug, "Jacob", device_token())
      before = rendered_room(mara)

      # The phone locks and the socket dies, taking the view process with it.
      Process.flag(:trap_exit, true)
      ref = Process.monitor(mara.pid)
      Process.exit(mara.pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _pid, :killed}

      # It wakes: same URL, same cookie, same view, nothing retyped.
      {:ok, again, _} = live(get(conn, ~p"/r/#{slug}"))

      assert rendered_room(again) == before
    end

    test "a phone waking from lock asks for the whole view again" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      join(mara, "Mara")

      {:ok, _} = Rooms.join(slug, "Jacob", device_token())

      html = render_hook(mara, "resync", %{})

      assert html =~ "Mara"
      assert html =~ "Jacob"
    end
  end

  describe "playing a Page" do
    setup do
      slug = open_room()
      mara_conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, mara, _} = live(mara_conn)
      {:ok, jacob, _} = live(phone(slug))

      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      %{slug: slug, mara: mara, mara_conn: mara_conn, jacob: jacob}
    end

    test "the Bookends are up on both phones and the stage", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")

      for view <- [ctx.mara, ctx.jacob, stage] do
        assert has_element?(view, "[data-role=bookends]", "lantern")
        assert has_element?(view, "[data-role=bookends]", "harbour")
      end
    end

    test "an illegal bridge is caught on the phone before commit and on commit", ctx do
      ctx.mara
      |> form("[data-role=bridge-form]", %{"bridge" => "lanterns"})
      |> render_change()

      assert has_element?(
               ctx.mara,
               "[data-role=bridge-error]",
               "\"lanterns\" shares a root with \"lantern\"."
             )

      commit(ctx.mara, "lanterns")

      assert has_element?(
               ctx.mara,
               "[data-role=bridge-error]",
               "\"lanterns\" shares a root with \"lantern\"."
             )

      assert has_element?(ctx.mara, "[data-role=bridge-form]")
      refute has_element?(ctx.mara, "[data-role=your-bridge]")

      commit(ctx.mara, "beacon")
      assert has_element?(ctx.mara, "[data-role=your-bridge]", "beacon")
      refute has_element?(ctx.mara, "[data-role=bridge-form]")
    end

    test "a Bridge is written on one phone and seen on none of the others", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")

      commit(ctx.mara, "cairn")

      assert has_element?(ctx.mara, "[data-role=your-bridge]", "cairn")
      refute has_element?(ctx.mara, "[data-role=bridge-form]")

      refute render(ctx.jacob) =~ "cairn"
      refute render(stage) =~ "cairn"

      # What the other phone and the stage are told is that she is done, and
      # nothing else.
      for view <- [ctx.jacob, stage] do
        assert has_element?(view, "[data-seat][data-committed=true]", "Mara")
        assert has_element?(view, "[data-seat][data-committed=false]", "Jacob")
      end

      assert has_element?(ctx.jacob, "[data-role=bridge-form]")
    end

    test "the last commit reveals both Bridges, graded, on both phones", ctx do
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- [ctx.mara, ctx.jacob] do
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

      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- [ctx.mara, ctx.jacob, stage] do
        assert eventually(fn -> has_element?(view, "[data-role=phase][data-step=slow]") end)
      end

      # And when it never answers, the game says so and the call is theirs.
      html = await_reveal_on(stage)

      assert html =~ "No verdict"
      assert html =~ "yours to call"
    end

    test "a miss is graded and said out loud, same as a Meld", ctx do
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "beacon")

      html = await_reveal_on(ctx.mara)

      assert html =~ "cairn"
      assert html =~ "beacon"
      assert has_element?(ctx.mara, "[data-role=closeness]", "0")
      assert has_element?(ctx.mara, "[data-role=band]", "miss")
    end

    test "a phone that locked through the reveal wakes into it", ctx do
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairo")
      await_reveal_on(ctx.jacob)

      Process.flag(:trap_exit, true)
      ref = Process.monitor(ctx.mara.pid)
      Process.exit(ctx.mara.pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _pid, :killed}

      {:ok, again, html} = live(get(ctx.mara_conn, ~p"/r/#{ctx.slug}"))

      assert html =~ "cairn"
      assert has_element?(again, "[data-role=closeness]", "80")
    end

    test "an empty Bridge is a nudge rather than a commit", ctx do
      assert commit(ctx.mara, "   ") =~ "Write a word first."
      assert has_element?(ctx.mara, "[data-role=bridge-form]")
    end

    test "the Assayer having no verdict is said plainly", ctx do
      steward(mode: :unavailable)

      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairo")

      html = await_reveal_on(ctx.mara)

      assert html =~ "cairn"
      assert html =~ "No verdict"
      refute has_element?(ctx.mara, "[data-role=closeness]")
    end
  end

  describe "a Page that misses, and a Page that ends" do
    setup do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))

      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      %{
        slug: slug,
        mara: mara,
        jacob: jacob,
        screens: [mara, jacob]
      }
    end

    defp press(view, role), do: view |> element("[data-role=#{role}]") |> render_click()

    defp miss(ctx, mara_bridge \\ "cairn", jacob_bridge \\ "beacon") do
      commit(ctx.mara, mara_bridge)
      commit(ctx.jacob, jacob_bridge)

      await_reveal_on(ctx.mara)
    end

    test "the failed Bridges become the next attempt's Bookends, on every screen", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")

      miss(ctx)

      # The tap says what it is going to do before it does it.
      assert has_element?(ctx.mara, "[data-role=again]", "cairn and beacon")
      assert has_element?(stage, "[data-role=carry-forward]")
      refute has_element?(stage, "[data-role=again]")

      press(ctx.mara, "again")

      for view <- [ctx.mara, ctx.jacob, stage] do
        assert has_element?(view, "[data-role=bookends]", "cairn")
        assert has_element?(view, "[data-role=bookends]", "beacon")
        assert has_element?(view, "[data-role=attempt]", "Attempt 2 of 5")
        refute has_element?(view, "[data-role=reveal]")
      end

      assert has_element?(ctx.jacob, "[data-role=bridge-form]")
    end

    test "a Meld is the end of the Page and says so", ctx do
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairns")
      await_reveal_on(ctx.mara)

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=ending-line]", "melded first try")
        # The grade the reveal landed on is still up under it.
        assert has_element?(view, "[data-role=closeness]", "91")
        refute has_element?(view, "[data-role=again]")
        refute has_element?(view, "[data-role=attempt]")
      end

      assert has_element?(ctx.mara, "[data-role=one-more]")
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
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairns")
      await_reveal_on(ctx.mara)

      press(ctx.mara, "one-more")

      assert has_element?(ctx.mara, "[data-role=setting-form]")
      assert has_element?(ctx.jacob, "[data-role=setting-form]")

      # Prefill shows last give
      assert render(ctx.mara) =~ "value=\"setting one\""
      assert render(ctx.jacob) =~ "value=\"setting two\""

      # Submitting new settings begins bridging again
      play_to_bridging(ctx.mara, ctx.jacob, ctx.slug, "fresh one", "fresh two")

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=attempt]", "Attempt 1 of 5")
        refute has_element?(view, "[data-role=ending]")
        refute has_element?(view, "[data-role=reveal]")
      end

      assert has_element?(ctx.jacob, "[data-role=bridge-form]")
      assert has_element?(ctx.jacob, "[data-seat]", "Mara")
    end

    test "both of them tapping at once is one next attempt, not two", ctx do
      miss(ctx)

      press(ctx.mara, "again")

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

      # Mara and Jacob land on the same word. Ada is somewhere else. Nobody
      # writes anything until the third of them is in the Room.
      phones =
        for {name, bridge} <- [{"Mara", "cairn"}, {"Jacob", "cairo"}, {"Ada", "beacon"}] do
          {:ok, view, _} = live(phone(slug))
          join(view, name)
          {view, bridge}
        end

      for {view, name} <- Enum.zip(Enum.map(phones, &elem(&1, 0)), ~w(Mara Jacob Ada)) do
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
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      # "cairn" and "beacon" share no prefix -> fake assayer grades 0
      commit(mara, "cairn")
      commit(jacob, "beacon")

      await_reveal_on(mara)
      await_reveal_on(jacob)
      await_reveal_on(stage)

      refute has_element?(mara, "[data-role=closeness]")
      assert has_element?(stage, "[data-role=closeness]", "0")

      # Mara proposes an overrule
      mara |> element("[data-role=propose-overrule]") |> render_click()

      # Visible on all three views while pending
      assert render(mara) =~ "You proposed an overrule"

      assert has_element?(
               jacob,
               "[data-role=overrule-pending]",
               "Mara proposed overruling this grade to a Meld"
             )

      assert has_element?(stage, "[data-role=overrule-pending]", "Mara proposed an overrule")
      assert has_element?(jacob, "[data-role=agree-overrule]")
      assert has_element?(jacob, "[data-role=decline-overrule]")

      # Grade remains 0 on stage; phones remain quiet
      refute has_element?(mara, "[data-role=closeness]")
      refute has_element?(jacob, "[data-role=closeness]")
      assert has_element?(stage, "[data-role=closeness]", "0")

      # Jacob agrees
      jacob |> element("[data-role=agree-overrule]") |> render_click()

      # Overrule takes effect: stage shows 90 (meld floor), all three show banner, phones quiet
      assert has_element?(stage, "[data-role=closeness]", "90")
      assert has_element?(stage, "[data-role=band]", "meld")

      for view <- [mara, jacob, stage] do
        assert render(view) =~ "Overruled jointly"
      end

      refute has_element?(mara, "[data-role=closeness]")
      refute has_element?(jacob, "[data-role=closeness]")

      # Ending shows it melded
      assert has_element?(stage, "[data-role=ending-line]", "melded first try")

      # "One more?" starts the next page cleanly
      assert has_element?(mara, "[data-role=one-more]")
      mara |> element("[data-role=one-more]") |> render_click()

      assert has_element?(mara, "[data-role=setting-form]")
      assert has_element?(jacob, "[data-role=setting-form]")
      refute render(mara) =~ "Overruled"
    end

    test "declining an overrule leaves the grade untouched" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))

      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      commit(mara, "cairn")
      commit(jacob, "beacon")

      await_reveal_on(mara)
      await_reveal_on(jacob)

      mara |> element("[data-role=propose-overrule]") |> render_click()
      assert has_element?(jacob, "[data-role=decline-overrule]")

      jacob |> element("[data-role=decline-overrule]") |> render_click()

      refute render(mara) =~ "proposed an overrule"
      refute render(jacob) =~ "proposed an overrule"
      assert has_element?(mara, "[data-role=closeness]", "0")
      assert has_element?(mara, "[data-role=again]")
    end
  end

  describe "the reveal performance (Ticket 10)" do
    setup do
      slug = open_room()
      mara_conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, mara, _} = live(mara_conn)
      {:ok, jacob, _} = live(phone(slug))

      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      %{
        slug: slug,
        mara: mara,
        jacob: jacob,
        screens: [mara, jacob]
      }
    end

    test "the 2.5s beat is visibly a beat, not a spinner, on both phones and the stage", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")
      beat(500)

      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- [ctx.mara, ctx.jacob, stage] do
        assert has_element?(view, "[data-role=beat-meter]")
        refute render(view) =~ "loading-spinner"
        refute render(view) =~ "spinner"
      end

      await_reveal_on(stage)
    end

    test "reveal lands: side-by-side comparison first, climbing number, quip punchline, and phone vs stage split",
         ctx do
      commit(ctx.mara, "cairn")
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
        {comp_idx, _} = :binary.match(html, ~s(data-role="comparison"))
        {close_idx, _} = :binary.match(html, ~s(data-role="closeness-display"))
        {quip_idx, _} = :binary.match(html, ~s(data-role="quip"))
        assert comp_idx < close_idx
        assert close_idx < quip_idx
      end

      # Phone distinguishes your bridge with (you)
      assert has_element?(ctx.mara, "[data-bridge][data-you=true]", "Mara")
      assert has_element?(ctx.mara, "[data-bridge][data-you=false]", "Jacob")

      # Code card renders in every phase, full Room included
      assert has_element?(ctx.mara, "[data-role=room-code]")
      assert has_element?(ctx.jacob, "[data-role=room-code]")

      # Header and "You are …" render below reveal as a footer on phone
      phone_html = render(ctx.mara)
      {reveal_idx, _} = :binary.match(phone_html, ~s(data-role="reveal"))
      {footer_idx, _} = :binary.match(phone_html, "<footer")
      assert reveal_idx < footer_idx
      assert has_element?(ctx.mara, "footer [data-role=you]", "Mara")
      assert has_element?(ctx.mara, "footer h1", "Meaning Game")
      assert has_element?(ctx.mara, "footer a", "The Chronicle")

      # Stage has public stage mode and no private (you) attribution
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")
      assert has_element?(stage, "[data-mode=stage]")
      refute has_element?(stage, "[data-bridge][data-you=true]")
    end

    test "an almost grade lands in the almost band and next attempt is offered", ctx do
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairo")

      for view <- ctx.screens do
        await_reveal_on(view)
        assert has_element?(view, "[data-role=comparison]")
        assert has_element?(view, "[data-role=closeness]", "80")
        assert has_element?(view, "[data-role=band]", "almost")
        assert has_element?(view, "[data-arrival=almost]")
        refute has_element?(view, "[data-role=ending-line]")
      end

      for phone <- [ctx.mara, ctx.jacob] do
        assert has_element?(phone, "[data-role=again]")
      end
    end

    test "a miss is staged as a shared comedy deadpan joke, not an error sting", ctx do
      commit(ctx.mara, "cairn")
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

      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairo")

      await_reveal_on(stage)

      assert has_element?(stage, "[data-role=no-verdict]")
      assert render(stage) =~ "The Assayer steps aside"
      assert render(stage) =~ "No verdict. This one is yours to call."
      assert has_element?(ctx.mara, "[data-role=propose-overrule]")
    end
  end

  describe "the fairness tap at the reveal (ticket 11)" do
    setup do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")

      play_to_bridging(mara, jacob, slug)

      commit(mara, "cairn")
      commit(jacob, "cairns")

      await_reveal_on(mara)
      await_reveal_on(jacob)
      await_reveal_on(stage)

      %{slug: slug, mara: mara, jacob: jacob, stage: stage}
    end

    test "three taps appear on each phone at the reveal, but not on the stage", ctx do
      for phone <- [ctx.mara, ctx.jacob] do
        assert has_element?(phone, "[data-role=fairness-controls]")
        assert has_element?(phone, "[data-role=tap-fair]", "Fair")
        assert has_element?(phone, "[data-role=tap-too-kind]", "Too kind")
        assert has_element?(phone, "[data-role=tap-too-harsh]", "Too harsh")
      end

      # Stage holds no seat so it renders no fairness buttons
      refute has_element?(ctx.stage, "[data-role=fairness-controls]")
    end

    test "tapping persists the label and highlights the selection per Seat", ctx do
      # Mara taps fair
      ctx.mara |> element("[data-role=tap-fair]") |> render_click()

      assert has_element?(ctx.mara, "[data-role=tap-fair].btn-primary")
      assert has_element?(ctx.mara, "[data-role=your-tap]")
      assert has_element?(ctx.mara, "[data-role=seat-tap]", "fair")
      refute has_element?(ctx.jacob, "[data-role=tap-fair].btn-primary")
      refute has_element?(ctx.jacob, "[data-role=your-tap]")

      # Jacob disagrees and taps too_harsh
      ctx.jacob |> element("[data-role=tap-too-harsh]") |> render_click()

      assert has_element?(ctx.jacob, "[data-role=tap-too-harsh].btn-warning")
      assert has_element?(ctx.jacob, "[data-role=your-tap]")
      assert has_element?(ctx.jacob, "[data-role=seat-tap]", "too harsh")
      assert has_element?(ctx.mara, "[data-role=tap-fair].btn-primary")
      assert has_element?(ctx.mara, "[data-role=your-tap]")

      # Both rows persisted in Chronicle
      room = MeaningGame.Repo.get_by!(MeaningGame.Rooms.Room, slug: ctx.slug)
      taps = MeaningGame.Chronicle.fairness_taps(room.id)
      assert length(taps) == 2
      assert Enum.map(taps, & &1.label) |> Enum.sort() == ["fair", "too_harsh"]
    end

    test "tapping never blocks or delays the next attempt", ctx do
      ctx.mara |> element("[data-role=tap-fair]") |> render_click()

      # Next page / again button is present and usable immediately
      assert has_element?(ctx.mara, "[data-role=one-more]")
      ctx.mara |> element("[data-role=one-more]") |> render_click()

      await_phase(ctx.slug, :giving)
      eventually(fn -> has_element?(ctx.mara, "[data-role=setting-form]") end)
    end
  end

  describe "giving settings and writing the page (ticket 02)" do
    setup do
      slug = open_room()

      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")

      steward = Application.fetch_env!(:meaning_game, :steward)
      on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

      %{slug: slug, mara: mara, jacob: jacob, stage: stage, steward: steward}
    end

    test "each seat gives a setting, stage shows count, second give triggers author writing",
         ctx do
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_delay_ms: 30, author_mode: :ok)
        )
      )

      # Both phones show Give form, stage shows giving count
      assert has_element?(ctx.mara, "[data-role=setting-form]")
      assert has_element?(ctx.jacob, "[data-role=setting-form]")
      assert has_element?(ctx.stage, "[data-role=giving-stage]")
      assert render(ctx.stage) =~ "0 of 2"

      # Mara gives a setting
      give_setting(ctx.mara, "candlelit cathedral")

      assert has_element?(ctx.mara, "[data-role=your-give]", "candlelit cathedral")
      refute has_element?(ctx.mara, "[data-role=setting-form]")

      # Jacob still sees setting form and cannot see Mara's give
      assert has_element?(ctx.jacob, "[data-role=setting-form]")
      refute render(ctx.jacob) =~ "candlelit cathedral"

      # Stage shows updated count without revealing setting text
      eventually(fn -> render(ctx.stage) =~ "1 of 2" end)
      refute render(ctx.stage) =~ "candlelit cathedral"

      # Jacob gives a setting, triggering author writing
      give_setting(ctx.jacob, "misty harbor")

      # Beat meter pulses during writing phase
      eventually(fn -> has_element?(ctx.stage, "[data-role=writing-stage]") end)
      assert has_element?(ctx.mara, "[data-role=writing-phase]")

      # Transitions to bridging with bookends and no setting line
      await_phase(ctx.slug, :bridging)
      eventually(fn -> has_element?(ctx.mara, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.stage, "[data-role=bookends]") end)

      refute render(ctx.mara) =~ "Setting:"
      refute render(ctx.stage) =~ "Setting:"
    end

    test "next_page returns to giving phase prefilled with the previous give", ctx do
      play_to_bridging(ctx.mara, ctx.jacob, ctx.slug, "candlelit cathedral", "misty harbor")

      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairns")
      await_reveal_on(ctx.mara)

      assert has_element?(ctx.mara, "[data-role=one-more]")
      ctx.mara |> element("[data-role=one-more]") |> render_click()

      await_phase(ctx.slug, :giving)
      eventually(fn -> has_element?(ctx.mara, "[data-role=setting-form]") end)

      assert render(ctx.mara) =~ "value=\"candlelit cathedral\""
      assert render(ctx.jacob) =~ "value=\"misty harbor\""
    end

    test "a failed or refused Author run surfaces on phone with retry and reset options", ctx do
      fake_config = Keyword.get(ctx.steward, :fake, [])

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(
          ctx.steward,
          :fake,
          Keyword.merge(fake_config, author_mode: :refused)
        )
      )

      give_setting(ctx.mara, "forbidden cathedral")
      give_setting(ctx.jacob, "forbidden harbour")

      eventually(fn -> has_element?(ctx.mara, "[data-role=author-failure]") end)
      assert has_element?(ctx.mara, "[data-role=retry-author]")
      assert has_element?(ctx.mara, "[data-role=reset-gives]")

      # Clicking reset-gives returns both players to giving form
      ctx.mara |> element("[data-role=reset-gives]") |> render_click()

      eventually(fn -> has_element?(ctx.mara, "[data-role=setting-form]") end)
      assert has_element?(ctx.jacob, "[data-role=setting-form]")
    end

    test "submitting an empty Give shows an error", ctx do
      give_setting(ctx.mara, "   ")
      assert has_element?(ctx.mara, "[data-role=give-error]", "Type a setting first.")
    end
  end

  describe "blinding in rendered views (ticket 13)" do
    setup do
      slug = open_room()

      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")

      play_to_bridging(mara, jacob, slug)

      %{slug: slug, mara: mara, jacob: jacob, stage: stage}
    end

    test "arm labels are blinded on stage and on phones during play", ctx do
      # During bridging phase:
      mara_html = render(ctx.mara)
      jacob_html = render(ctx.jacob)
      stage_html = render(ctx.stage)

      for html <- [mara_html, jacob_html, stage_html] do
        refute html =~ ~r/\barm\s*=\s*["'](bait|plain)["']/i
        refute html =~ ~r/\barm:\s*(bait|plain)\b/i
        refute html =~ "data-arm"
      end

      # Commit bridges and reveal
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairo")
      await_reveal_on(ctx.mara)
      await_reveal_on(ctx.stage)

      # During reveal phase:
      mara_reveal = render(ctx.mara)
      jacob_reveal = render(ctx.jacob)
      stage_reveal = render(ctx.stage)

      for html <- [mara_reveal, jacob_reveal, stage_reveal] do
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
      join(player, "Mara")
      assert has_element?(player, "[data-role=make-stage]", "Make this device the Stage")

      assert {:error, {:live_redirect, %{to: to}}} =
               player |> element("[data-role=make-stage]") |> render_click()

      assert to == ~p"/r/#{slug}/stage"
    end

    test "two phones and a stage: giving state and bookends on stage, quiet reveal on both phones, full reveal on stage, and return when stage exits" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")

      # Stage giving state while phones give
      assert has_element?(stage, "[data-role=giving-stage]")
      assert render(stage) =~ "Waiting for settings: 0 of 2"

      give_setting(mara, "lanterns on the quay")
      eventually(fn -> render(stage) =~ "Waiting for settings: 1 of 2" end)

      give_setting(jacob, "fog over the harbour")
      await_phase(slug, :bridging)

      # Stage renders Bookends while phones bridge
      eventually(fn -> has_element?(stage, "[data-role=bookends]") end)
      assert has_element?(stage, "[data-role=bookends]", "lantern")
      assert has_element?(stage, "[data-role=bookends]", "harbour")
      assert has_element?(mara, "[data-role=bookends]", "lantern")
      assert has_element?(jacob, "[data-role=bookends]", "lantern")

      # Both phones commit bridges
      commit(mara, "cairn")
      commit(jacob, "cairo")

      await_reveal_on(stage)
      await_reveal_on(mara)
      await_reveal_on(jacob)

      # Stage renders full reveal
      assert has_element?(stage, "[data-role=comparison]")
      assert has_element?(stage, "[data-role=closeness]", "80")
      assert has_element?(stage, "[data-role=band]", "almost")
      assert has_element?(stage, "[data-role=quip]")
      refute has_element?(stage, "[data-role=fairness-controls]")

      # Both phones render quiet reveal: comparison, controls only; NO closeness, band, or quip
      for phone <- [mara, jacob] do
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
      eventually(fn -> has_element?(mara, "[data-role=closeness]", "80") end)
      eventually(fn -> has_element?(jacob, "[data-role=closeness]", "80") end)

      assert has_element?(mara, "[data-role=band]", "almost")
      assert has_element?(mara, "[data-role=quip]")
      assert has_element?(jacob, "[data-role=band]", "almost")
      assert has_element?(jacob, "[data-role=quip]")
    end

    test "a stage connecting mid-reveal makes phones go quiet, and disconnecting returns them to full reveal" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))

      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      commit(mara, "cairn")
      commit(jacob, "cairo")

      await_reveal_on(mara)
      await_reveal_on(jacob)

      # Initially no stage: both phones show full reveal
      assert has_element?(mara, "[data-role=closeness]", "80")
      assert has_element?(jacob, "[data-role=closeness]", "80")

      # Stage connects
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      await_reveal_on(stage)

      # Both phones go quiet
      eventually(fn -> !has_element?(mara, "[data-role=closeness]") end)
      eventually(fn -> !has_element?(jacob, "[data-role=closeness]") end)

      refute has_element?(mara, "[data-role=band]")
      refute has_element?(mara, "[data-role=quip]")
      assert has_element?(mara, "[data-role=fairness-controls]")

      # Stage exits
      Process.flag(:trap_exit, true)
      ref = Process.monitor(stage.pid)
      Process.exit(stage.pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _pid, :killed}

      # Both phones return to full reveal
      eventually(fn -> has_element?(mara, "[data-role=closeness]", "80") end)
      eventually(fn -> has_element?(jacob, "[data-role=closeness]", "80") end)
      assert has_element?(mara, "[data-role=band]", "almost")
      assert has_element?(mara, "[data-role=quip]")
    end
  end
end
