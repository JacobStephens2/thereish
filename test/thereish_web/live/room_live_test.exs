defmodule ThereishWeb.RoomLiveTest do
  @moduledoc """
  Two phones and a stage, the way they sit on the couch.

  Each phone is its own `conn`, because a `conn` is a browser here: the device
  token that finds a Seat lives in its session cookie.
  """
  use ThereishWeb.ConnCase, async: false

  import Thereish.RoomFixtures
  import Phoenix.LiveViewTest

  alias Thereish.ExperimentFixtures
  alias Thereish.Rooms

  defp join(view, name),
    do: view |> form("form[phx-submit=join]", %{"name" => name}) |> render_submit()

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

  defp assert_all_markers_dim(stage, slug) do
    for seat <- Rooms.snapshot(slug, nil).seats do
      assert has_element?(
               stage,
               "[data-role=bridge-marker][data-seat='#{seat.id}'][data-state=dim]",
               seat.name
             )
    end
  end

  # A Stage claims nothing and plays nothing until someone taps it (ticket 12),
  # so a test that wants a speaking Stage taps it the way a person would.
  defp tap_for_sound(stage), do: stage |> element("[data-role=tap-for-sound]") |> render_click()

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
      {:ok, mara, html} = live(phone(slug))

      assert html =~ "Nobody yet"

      # In :waiting, speaker bar and Code card render above the join form
      assert_order(html, [
        ~s(data-role="speaker-bar"),
        ~s(data-role="room-code"),
        ~s(phx-submit="join")
      ])

      html = join(mara, "Mara")

      assert html =~ "You are"
      assert has_element?(mara, "[data-seat]", "Mara")
      refute has_element?(mara, "form[phx-submit=join]")

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

    test "ticket 02: bar controls wrap at phone widths and wrapper carries the wrap class" do
      code = open_room()
      {:ok, view, _html} = live(phone(code))

      assert has_element?(view, "[data-role=speaker-bar] [data-role=bar-controls].flex-wrap")
    end

    test "ticket 02: music switch labels are Off, House, This Page on phone and Stage" do
      code = open_room()
      {:ok, phone_view, _html} = live(phone(code))
      {:ok, stage, _html} = live(build_conn(), ~p"/r/#{code}/stage")

      for view <- [phone_view, stage] do
        assert has_element?(view, "[data-role=music-off]", "Off")
        assert has_element?(view, "[data-role=music-house]", "House")
        assert has_element?(view, "[data-role=music-page]", "This Page")
        refute has_element?(view, "[data-role=music-house]", "House loop")
        refute has_element?(view, "[data-role=music-page]", "Written for this Page")
      end
    end

    test "ticket 02: Code card copy is the Code, the address, and the Stage button only" do
      code = open_room(quip: nil)
      {:ok, view, _html} = live(phone(code))

      assert has_element?(view, "[data-role=room-code] [data-role=code]")
      assert has_element?(view, "[data-role=room-code] [data-role=join-url]")
      assert has_element?(view, "[data-role=room-code] [data-role=make-stage]")
      refute element(view, "[data-role=room-code]") |> render() =~ "Read it aloud, or send"
    end

    test "a quiet credit names who made Thereish" do
      code = open_room()
      {:ok, view, _html} = live(phone(code))

      assert has_element?(
               view,
               "[data-role=made-by] a[href='https://stephens.page']",
               "Made by Jacob Stephens"
             )
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

      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")

      for view <- [mara, jacob, stage] do
        assert has_element?(view, "[data-seat]", "Mara")
        assert has_element?(view, "[data-seat]", "Jacob")
        refute has_element?(view, "[data-role=open-seats]")
      end

      refute render(stage) =~ "All 2 seats taken"
    end

    test "fill line renders 'Waiting for 1 more' at one Seat, and no fill line at two or more before and during play" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      {:ok, mara, _} = live(phone(slug))

      # Before anyone joins, no fill line
      refute has_element?(stage, "[data-role=open-seats]")

      # One Seat joined: "Waiting for 1 more" on phone and stage
      join(mara, "Mara")
      assert has_element?(mara, "[data-role=open-seats]", "Waiting for 1 more")
      assert has_element?(stage, "[data-role=open-seats]", "Waiting for 1 more")

      # Two Seats joined: no fill line on either phone or stage
      {:ok, jacob, _} = live(phone(slug))
      join(jacob, "Jacob")
      refute has_element?(mara, "[data-role=open-seats]")
      refute has_element?(jacob, "[data-role=open-seats]")
      refute has_element?(stage, "[data-role=open-seats]")
    end

    test "'Start another Room' link is present at the bottom of the phone view below the Seat list, and absent on the Stage" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      {:ok, mara, _} = live(phone(slug))

      # On phone, link is present below roster
      assert has_element?(mara, "[data-role=start-another-room]", "Start another Room")
      assert has_element?(mara, "a[href='/new']", "Start another Room")
      html = render(mara)
      assert_order(html, [~s(data-role="roster"), ~s(data-role="start-another-room")])

      # Even after joining, it stays present at the bottom below the Seat list
      join(mara, "Mara")
      assert has_element?(mara, "[data-role=start-another-room]", "Start another Room")
      assert_order(render(mara), [~s(data-role="roster"), ~s(data-role="start-another-room")])

      # On Stage, it is absent
      refute has_element?(stage, "[data-role=start-another-room]")
      refute has_element?(stage, "a[href='/new']")
      refute render(stage) =~ "Start another Room"
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
      assert has_element?(mara, "form[phx-submit=join]")
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
      refute has_element?(again, "form[phx-submit=join]")
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

      assert has_element?(in_b, "form[phx-submit=join]")
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
    setup ctx do
      if rungs = ctx[:escalation], do: escalation(rungs)

      slug = open_room()
      mara_conn = get(build_conn(), ~p"/r/#{slug}")
      {:ok, mara, _} = live(mara_conn)
      {:ok, jacob, _} = live(phone(slug))

      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      %{slug: slug, mara: mara, mara_conn: mara_conn, jacob: jacob}
    end

    test "the Bookends are up on both phones and the stage, under the Bookends caption", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")

      for view <- [ctx.mara, ctx.jacob, stage] do
        assert has_element?(view, "[data-role=bookends-caption]", "Bookends")
        assert has_element?(view, "[data-role=bookends]", "lantern")
        assert has_element?(view, "[data-role=bookends]", "harbour")
      end
    end

    test "during bridging, the Attempt line, Bookends and Bridge form come first and speaker bar and Code card are below",
         ctx do
      html = render(ctx.mara)

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
      assert has_element?(ctx.mara, "label", "Your bridge")

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
      assert has_element?(ctx.mara, "[data-role=your-bridge]", "Your bridge: beacon")
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

    @tag escalation: [slow: 50, unavailable: 700]
    test "a slow Assayer is narrated on every screen rather than left as a hang", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")
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

  describe "Stage Bridge markers" do
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

    test "one dim marker per Seat appears only on the Stage while bridging", ctx do
      assert has_element?(ctx.stage, "[data-role=bridge-markers]")
      assert_all_markers_dim(ctx.stage, ctx.slug)

      refute has_element?(ctx.mara, "[data-role=bridge-marker]")
      refute has_element?(ctx.jacob, "[data-role=bridge-marker]")
    end

    test "a Seat marker lights in the same Stage update as the commit sting", ctx do
      mara = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Mara"))
      jacob = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Jacob"))
      tap_for_sound(ctx.stage)

      commit(ctx.mara, "cairn")

      assert_push_event(ctx.stage, "foley:commit", %{})

      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{mara.id}'][data-state=lit]",
               "Mara"
             )

      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{jacob.id}'][data-state=dim]",
               "Jacob"
             )
    end

    test "all markers reset for the next Attempt", ctx do
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "beacon")
      await_reveal_on(ctx.stage)

      ctx.mara |> element("[data-role=again]") |> render_click()

      assert has_element?(ctx.stage, "[data-role=attempt]", "Attempt 2 of 5")
      assert_all_markers_dim(ctx.stage, ctx.slug)
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

    test "carried Bookends show the Seat's Mask from the second Attempt, never on the first",
         ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")

      for view <- [ctx.mara, ctx.jacob, stage] do
        refute has_element?(view, "[data-role=bookend-mask]")
      end

      miss(ctx)

      for view <- [ctx.mara, ctx.jacob, stage] do
        refute has_element?(view, "[data-role=bookend-mask]")
      end

      press(ctx.mara, "again")

      eventually(fn -> has_element?(ctx.mara, "[data-role=bookend-mask]") end)

      for view <- [ctx.mara, ctx.jacob, stage] do
        assert has_element?(view, "[data-role=bookend-mask]")
      end
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

  describe "the reveal hold on every screen" do
    setup do
      reveal_hold(60_000)
      slug = open_room()
      mara_conn = phone(slug)
      {:ok, mara, _} = live(mara_conn)
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      %{
        slug: slug,
        mara: mara,
        jacob: jacob,
        stage: stage,
        mara_conn: mara_conn,
        screens: [mara, jacob, stage]
      }
    end

    test "phones and the Stage hold until the deadline, and a click cannot bypass it", ctx do
      miss(ctx)

      for view <- [ctx.mara, ctx.jacob] do
        assert has_element?(view, "[data-role=reveal-hold]")
        assert has_element?(view, "[data-role=again][disabled]")
      end

      assert has_element?(ctx.stage, "[data-role=reveal-hold]")
      refute has_element?(ctx.stage, "[data-role=again]")

      render_click(ctx.mara, "next_attempt", %{})
      render_click(ctx.jacob, "next_attempt", %{})

      for view <- ctx.screens do
        assert has_element?(view, "[data-role=reveal]")
        refute has_element?(view, "[data-role=attempt]", "Attempt 2 of 5")
      end
    end

    test "an early Meld holds One more? the same way", ctx do
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairns")
      await_reveal_on(ctx.mara)

      assert has_element?(ctx.mara, "[data-role=reveal-hold]")
      assert has_element?(ctx.mara, "[data-role=one-more][disabled]")
      assert has_element?(ctx.stage, "[data-role=reveal-hold]")

      render_click(ctx.mara, "next_page", %{})

      assert has_element?(ctx.mara, "[data-role=ending]")
      refute has_element?(ctx.mara, "[data-role=setting-form]")
    end

    test "exhausted Attempts hold One more? after the last reveal", ctx do
      attempt_cap(2)
      clock = freeze_clock(0)
      miss(ctx)

      # The Room read its hold when it opened, so the first one is waited out
      # on its clock rather than shortened. Nothing broadcasts when a frozen
      # clock moves, so the phone reconnects to read the unlocked button.
      travel(clock, 60_000)
      {:ok, mara, _} = live(ctx.mara_conn)
      ctx = %{ctx | mara: mara}
      assert has_element?(ctx.mara, "[data-role=again]:not([disabled])")
      press(ctx.mara, "again")
      await_phase(ctx.slug, :bridging)

      miss(ctx, "wharf", "gantry")

      assert has_element?(ctx.mara, "[data-role=one-more][disabled]")
      assert has_element?(ctx.stage, "[data-role=reveal-hold]")
      render_click(ctx.mara, "next_page", %{})
      assert has_element?(ctx.mara, "[data-role=ending]")
      refute has_element?(ctx.mara, "[data-role=setting-form]")
    end

    test "a late Stage and a reconnecting phone see the Room's deadline, not a fresh one",
         ctx do
      miss(ctx)

      {:ok, late_stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")
      {:ok, reconnected, _} = live(ctx.mara_conn)
      mara_id = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Mara")).id

      assert has_element?(late_stage, "[data-role=reveal-hold]")
      assert has_element?(reconnected, "[data-role=again][disabled]")
      assert {:error, :reveal_held} = Rooms.next_attempt(ctx.slug, mara_id)
    end
  end

  describe "the reveal hold unlocking" do
    test "controls unlock when the deadline passes, and one eligible tap advances" do
      reveal_hold(30)
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      commit(mara, "cairn")
      commit(jacob, "beacon")
      await_reveal_on(mara)

      eventually(fn -> has_element?(mara, "[data-role=again]:not([disabled])") end)
      refute has_element?(mara, "[data-role=reveal-hold]")
      refute has_element?(stage, "[data-role=reveal-hold]")

      press(mara, "again")

      for view <- [mara, jacob, stage] do
        assert has_element?(view, "[data-role=attempt]", "Attempt 2 of 5")
      end
    end

    test "One more? unlocks when the deadline passes, and one tap opens the next Page" do
      reveal_hold(30)
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

      eventually(fn -> has_element?(mara, "[data-role=one-more]:not([disabled])") end)
      refute has_element?(mara, "[data-role=reveal-hold]")
      refute has_element?(stage, "[data-role=reveal-hold]")

      press(mara, "one-more")

      assert has_element?(mara, "[data-role=setting-form]")
      assert has_element?(jacob, "[data-role=setting-form]")
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

    test "shows thereish.app and keeps a useful Room link" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      assert has_element?(stage, "[data-role=join-url]", "thereish.app")
      assert has_element?(stage, ~s(a[data-role=join-url][href*="/r/#{slug}"]))
      refute has_element?(stage, "[data-role=join-url]", "/r/#{slug}")
    end

    test "the joining screen has a small credit that play does not" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      assert has_element?(stage, "[data-role=stage-foot] [data-role=made-by][data-size=stage]")

      assert has_element?(
               stage,
               "[data-role=stage-foot] [data-role=made-by] a[href='https://stephens.page']",
               "Made by Jacob Stephens"
             )

      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      refute has_element?(stage, "[data-role=made-by]")
    end

    test "heading, controls, and chronicle link share the header; join URL and roster share the foot" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")

      html = render(stage)

      # Header has Thereish heading, controls, and Chronicle link, but no join URL
      assert has_element?(stage, "header h1", "Thereish")
      assert has_element?(stage, "header a[href*='chronicle']", "The Chronicle")
      refute has_element?(stage, "header [data-role=join-url]")

      # Footer strip has join address and roster together; no separate "In the Room" heading
      assert has_element?(stage, "footer [data-role=join-url]", "thereish.app")
      assert has_element?(stage, "[data-role=stage-foot] [data-role=join-url]", "thereish.app")
      assert has_element?(stage, "footer [data-role=roster]")
      assert has_element?(stage, "footer [data-seat]", "Mara")
      assert has_element?(stage, "footer [data-seat]", "Jacob")

      refute has_element?(stage, "[data-role=stage-foot] [data-role=open-seats]")
      refute html =~ "All 2 seats taken"

      refute has_element?(stage, "h2", "In the Room")
      refute html =~ "In the Room"

      # Play column scrolls; header and foot stay put. Now-playing lives in the foot
      # so a tall closed Page cannot cover the chrome.
      assert html =~ ~s(data-role="stage-body")

      if html =~ ~s(data-role="now-playing") do
        assert has_element?(stage, "[data-role=stage-foot] [data-role=now-playing]")
      end

      # Order: header -> play content -> stage-foot
      assert_order(html, ["<header", ~s(data-role="stage-body"), ~s(data-role="stage-foot")])
    end

    test "the Code is large while the Room fills and small in the header once a Page is in play" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      code = String.upcase(slug)

      assert has_element?(stage, "[data-role=stage-code][data-size=large]", code)
      refute has_element?(stage, "header [data-role=stage-code]")

      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      assert has_element?(stage, "header [data-role=stage-code][data-size=small]", code)
      refute has_element?(stage, "[data-role=stage-code][data-size=large]")
    end

    test "the opening tap claims the Speaker and starts the Repertoire, and nothing sounds before it" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      # A Stage that nobody has tapped holds no Speaker and is sent nothing to
      # play: the browser's autoplay rule is met on purpose, not discovered.
      assert is_nil(Rooms.get_room(slug).speaker)
      refute_push_event(stage, "foley:page", %{})
      assert has_element?(stage, "[data-role=tap-for-sound]")

      tap_for_sound(stage)

      refute is_nil(Rooms.get_room(slug).speaker)
      assert_push_event(stage, "foley:page", %{kind: "repertoire", path: path})
      assert String.starts_with?(path, "/audio/house-loop")

      # The tap has done its one job, so it stops asking.
      refute has_element?(stage, "[data-role=tap-for-sound]")
    end

    test "a Stage opened mid-night still offers the tap and joins the music already playing" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      join(mara, "Mara")
      join(jacob, "Jacob")
      play_to_bridging(mara, jacob, slug)

      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      # Mid-night the Code has moved to the header, but the tap is still offered,
      # and until it is taken the Stage is sent nothing to play.
      assert has_element?(stage, "header [data-role=tap-for-sound]")
      refute has_element?(stage, "[data-role=stage-code][data-size=large]")
      assert is_nil(Rooms.get_room(slug).speaker)
      refute_push_event(stage, "foley:page", %{})

      tap_for_sound(stage)

      assert_push_event(stage, "foley:page", %{path: path})
      assert is_binary(path)
      refute has_element?(stage, "[data-role=tap-for-sound]")
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
    setup ctx do
      if ms = ctx[:beat], do: beat(ms)

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

    @tag beat: 500
    test "the 2.5s beat is visibly a beat, not a spinner, on both phones and the stage", ctx do
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")

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
        assert_order(html, [
          ~s(data-role="comparison"),
          ~s(data-role="closeness-display"),
          ~s(data-role="quip")
        ])
      end

      # Phone distinguishes your bridge with (you)
      assert has_element?(ctx.mara, "[data-bridge][data-you=true]", "Mara")
      assert has_element?(ctx.mara, "[data-bridge][data-you=false]", "Jacob")

      # Code card renders after reveal and controls, before In the Room and footer
      phone_html = render(ctx.mara)

      assert_order(phone_html, [
        ~s(data-role="reveal"),
        ~s(data-role="speaker-bar"),
        ~s(data-role="room-code"),
        "In the Room",
        "<footer"
      ])

      assert has_element?(ctx.mara, "footer [data-role=you]", "Mara")
      assert has_element?(ctx.mara, "footer h1", "Thereish")
      refute has_element?(ctx.mara, "footer h1 a")
      refute has_element?(ctx.mara, "footer a[href='/']", "Thereish")
      assert has_element?(ctx.mara, "footer a", "The Chronicle")

      # Stage has public stage mode and no private (you) attribution; wordmark links home
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{ctx.slug}/stage")
      assert has_element?(stage, "header h1", "Thereish")
      assert has_element?(stage, "header h1 a[href='/']", "Thereish")
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
      room = Thereish.Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)
      taps = Thereish.Chronicle.fairness_taps(room.id)
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

  describe "tapping bookends at closed (ticket 08)" do
    setup do
      slug = open_room()

      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")

      play_to_bridging(mara, jacob, slug)

      commit(mara, "cairn")
      commit(jacob, "cairn")
      await_reveal_on(mara)
      await_reveal_on(jacob)
      await_phase(slug, :closed)

      %{slug: slug, mara: mara, jacob: jacob, stage: stage}
    end

    test "each seat can tap flat, fine, or great on phone at closed, and it is replaceable",
         ctx do
      # Stage does NOT show bookends tap controls
      refute has_element?(ctx.stage, "[data-role=bookends-controls]")

      # Phones show bookends tap controls at closed
      assert has_element?(ctx.mara, "[data-role=bookends-controls]")
      assert has_element?(ctx.mara, "[data-role=tap-flat]")
      assert has_element?(ctx.mara, "[data-role=tap-fine]")
      assert has_element?(ctx.mara, "[data-role=tap-great]")

      # Mara taps great
      ctx.mara |> element("[data-role=tap-great]") |> render_click()

      assert has_element?(ctx.mara, "[data-role=tap-great].btn-success")
      assert has_element?(ctx.mara, "[data-role=your-bookends-tap]")
      assert has_element?(ctx.mara, "[data-role=seat-bookends-tap]", "great")
      refute has_element?(ctx.jacob, "[data-role=your-bookends-tap]")

      # Mara replaces tap with fine
      ctx.mara |> element("[data-role=tap-fine]") |> render_click()

      assert has_element?(ctx.mara, "[data-role=tap-fine].btn-primary")
      assert has_element?(ctx.mara, "[data-role=seat-bookends-tap]", "fine")

      # Jacob taps flat
      ctx.jacob |> element("[data-role=tap-flat]") |> render_click()

      assert has_element?(ctx.jacob, "[data-role=tap-flat].btn-warning")
      assert has_element?(ctx.jacob, "[data-role=seat-bookends-tap]", "flat")

      # Both taps recorded in Chronicle
      room = Thereish.Repo.get_by!(Thereish.Rooms.Room, slug: ctx.slug)
      taps = ExperimentFixtures.bookends_taps(room.id)
      assert length(taps) == 3

      [outcome] = ExperimentFixtures.outcomes(room.id, "author_model")
      assert Map.values(outcome.taps) |> Enum.sort() == ["fine", "flat"]

      seats = Thereish.Repo.preload(room, :seats).seats
      mara_seat = Enum.find(seats, &(&1.name == "Mara"))
      jacob_seat = Enum.find(seats, &(&1.name == "Jacob"))
      assert outcome.taps[mara_seat.id] == "fine"
      assert outcome.taps[jacob_seat.id] == "flat"
    end
  end

  describe "giving settings and writing the page (ticket 02)" do
    setup ctx do
      if rungs = ctx[:author_escalation], do: author_escalation(rungs)

      slug = open_room()

      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      join(mara, "Mara")
      join(jacob, "Jacob")

      steward = Application.fetch_env!(:thereish, :steward)
      on_exit(fn -> Application.put_env(:thereish, :steward, steward) end)

      %{slug: slug, mara: mara, jacob: jacob, stage: stage, steward: steward}
    end

    test "player-facing theme language says Give and invites more than places", ctx do
      mara = render(ctx.mara)
      assert mara =~ "Your Give"
      refute mara =~ "Your setting"
      assert has_element?(ctx.mara, "[data-role=give-examples]")

      examples = element(ctx.mara, "[data-role=give-examples]") |> render()
      assert examples =~ "restless"
      assert examples =~ "can of worms"
      assert examples =~ "first snow"
      assert examples =~ "Kiss Heavy Metal"

      stage = render(ctx.stage)
      assert stage =~ "Waiting for Gives"
      refute stage =~ "Waiting for settings"

      give_setting(ctx.mara, "   ")
      assert has_element?(ctx.mara, "[data-role=give-error]", "Type a Give first.")
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
      assert has_element?(ctx.mara, "[data-role=setting-form]")
      assert has_element?(ctx.jacob, "[data-role=setting-form]")
      assert has_element?(ctx.stage, "[data-role=giving-stage]")
      assert render(ctx.stage) =~ "0 of 2"

      # Code card and speaker bar are above setting form during giving phase
      mara_giving_html = render(ctx.mara)

      assert_order(mara_giving_html, [
        ~s(data-role="speaker-bar"),
        ~s(data-role="room-code"),
        ~s(data-role="setting-form")
      ])

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

      # From :writing on, speaker bar and Code card render after writing phase and before In the Room
      writing_html = render(ctx.mara)

      assert_order(writing_html, [
        ~s(data-role="writing-phase"),
        ~s(data-role="speaker-bar"),
        ~s(data-role="room-code"),
        "In the Room"
      ])

      # Transitions to bridging with bookends and no setting line
      await_phase(ctx.slug, :bridging)
      eventually(fn -> has_element?(ctx.mara, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.stage, "[data-role=bookends]") end)

      refute render(ctx.mara) =~ "Setting:"
      refute render(ctx.stage) =~ "Setting:"
    end

    test "giving a setting renders Mask on giver's view and face-down on stage", ctx do
      give_setting(ctx.mara, "candlelit cathedral")

      eventually(fn ->
        has_element?(ctx.mara, "[data-role=your-mask]")
      end)

      # Giver's roster also shows mask thumbnail
      assert has_element?(ctx.mara, "[data-role=seat-mask]")

      # Stage shows face-down mask for Mara
      assert has_element?(ctx.stage, "[data-role=mask-face-down]")

      # Jacob's phone does not see Mara's mask
      refute has_element?(ctx.jacob, "[data-role=your-mask]")
    end

    test "owner sees their Mask at once; other phone and Stage wait until the first reveal",
         ctx do
      give_setting(ctx.mara, "candlelit cathedral")
      mara = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Mara"))

      eventually(fn -> has_element?(ctx.mara, "[data-role=your-mask]") end)

      assert has_element?(
               ctx.mara,
               "[data-seat='#{mara.id}'] [data-role=seat-mask]"
             )

      refute has_element?(
               ctx.jacob,
               "[data-seat='#{mara.id}'] [data-role=seat-mask]"
             )

      assert has_element?(
               ctx.jacob,
               "[data-seat='#{mara.id}'] [data-role=mask-face-down]"
             )

      assert has_element?(
               ctx.stage,
               "[data-role=mask-face-down][data-seat='#{mara.id}']"
             )

      refute has_element?(
               ctx.stage,
               "[data-seat='#{mara.id}'] [data-role=seat-mask]"
             )

      give_setting(ctx.jacob, "misty harbor")
      await_phase(ctx.slug, :bridging)
      jacob = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Jacob"))

      refute has_element?(
               ctx.jacob,
               "[data-seat='#{mara.id}'] [data-role=seat-mask]"
             )

      assert has_element?(
               ctx.jacob,
               "[data-seat='#{mara.id}'] [data-role=mask-face-down]"
             )

      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "tallow")
      await_reveal_on(ctx.mara)
      await_reveal_on(ctx.jacob)
      await_reveal_on(ctx.stage)

      refute has_element?(ctx.mara, "[data-role=mask-face-down]")
      refute has_element?(ctx.jacob, "[data-role=mask-face-down]")
      refute has_element?(ctx.stage, "[data-role=mask-face-down]")

      assert has_element?(
               ctx.mara,
               "[data-seat='#{mara.id}'] [data-role=seat-mask]"
             )

      assert has_element?(
               ctx.jacob,
               "[data-seat='#{mara.id}'] [data-role=seat-mask]"
             )

      assert has_element?(
               ctx.stage,
               "[data-role=stage-mask][data-seat='#{mara.id}'] [data-role=seat-mask]"
             )

      assert has_element?(
               ctx.stage,
               "[data-role=stage-mask][data-seat='#{jacob.id}'] [data-role=seat-mask]"
             )
    end

    test "a Meld's final reveal pairs each written Give with its Mask on phones and Stage", ctx do
      play_to_bridging(ctx.mara, ctx.jacob, ctx.slug, "candlelit cathedral", "misty harbor")
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairns")
      await_reveal_on(ctx.mara)
      await_phase(ctx.slug, :closed)

      for view <- [ctx.mara, ctx.jacob, ctx.stage] do
        assert has_element?(view, "[data-role=gives]")
        assert has_element?(view, "[data-role=give]", "candlelit cathedral")
        assert has_element?(view, "[data-role=give]", "misty harbor")
        assert has_element?(view, "[data-role=give-mask]")
      end
    end

    test "an exhausted Page's final reveal pairs Gives with Masks on phones and Stage", ctx do
      attempt_cap(1)
      play_to_bridging(ctx.mara, ctx.jacob, ctx.slug, "candlelit cathedral", "misty harbor")
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "beacon")
      await_reveal_on(ctx.mara)
      await_phase(ctx.slug, :closed)

      for view <- [ctx.mara, ctx.jacob, ctx.stage] do
        assert has_element?(view, "[data-role=gives]")
        assert has_element?(view, "[data-role=give]", "candlelit cathedral")
        assert has_element?(view, "[data-role=give-mask]")
      end
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

    @tag author_escalation: [still_writing: 30, deadline: 100]
    test "stage shows waiting count with no give text, then writing animation, then still writing, then failure state",
         ctx do
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
      give_setting(ctx.mara, "secret cathedral")
      eventually(fn -> render(ctx.stage) =~ "Waiting for Gives: 1 of 2" end)
      refute render(ctx.stage) =~ "secret cathedral"

      # 2. Last give in: writing animation on stage and phones
      give_setting(ctx.jacob, "secret harbour")
      eventually(fn -> has_element?(ctx.stage, "[data-role=writing-stage]") end)
      assert has_element?(ctx.mara, "[data-role=writing-phase]")
      assert has_element?(ctx.jacob, "[data-role=writing-phase]")
      assert render(ctx.stage) =~ "The Author is reading your Gives..."
      assert render(ctx.mara) =~ "The Author is reading your Gives..."

      # 3. At five seconds (30ms test time): every screen says the Author is still writing
      eventually(fn -> render(ctx.stage) =~ "The Author is still writing..." end)
      assert render(ctx.mara) =~ "The Author is still writing..."
      assert render(ctx.jacob) =~ "The Author is still writing..."

      # 4. At deadline: stage and phones show failure state, writing animation gone
      eventually(fn -> has_element?(ctx.stage, "[data-role=author-failure]") end)
      assert has_element?(ctx.mara, "[data-role=author-failure]")
      assert has_element?(ctx.jacob, "[data-role=author-failure]")

      refute has_element?(ctx.stage, "[data-role=writing-stage]")
      refute has_element?(ctx.mara, "[data-role=writing-phase]")
      refute has_element?(ctx.jacob, "[data-role=writing-phase]")

      assert has_element?(
               ctx.stage,
               "[data-role=author-failure]",
               "The Author couldn't write from these Gives: timed out"
             )

      assert has_element?(
               ctx.mara,
               "[data-role=author-failure]",
               "The Author couldn't write from these Gives: timed out"
             )

      assert has_element?(
               ctx.jacob,
               "[data-role=author-failure]",
               "The Author couldn't write from these Gives: timed out"
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

      give_setting(ctx.mara, "setting one")
      give_setting(ctx.jacob, "setting two")

      eventually(fn -> has_element?(ctx.mara, "[data-role=author-failure]") end)
      assert has_element?(ctx.jacob, "[data-role=author-failure]")

      # Both phones see Try again and New settings
      for phone <- [ctx.mara, ctx.jacob] do
        assert has_element?(phone, "[data-role=retry-author]", "Try again")
        assert has_element?(phone, "[data-role=reset-gives]", "New Gives")

        assert has_element?(
                 phone,
                 "[data-role=author-failure]",
                 "The Author couldn't write from these Gives"
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
      eventually(fn -> has_element?(ctx.mara, "[data-role=bridge-form]") end)
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

      give_setting(ctx.mara, "setting mara")
      give_setting(ctx.jacob, "setting jacob")

      eventually(fn -> has_element?(ctx.mara, "[data-role=author-failure]") end)
      assert has_element?(ctx.jacob, "[data-role=author-failure]")

      # Mara clicks New settings
      ctx.mara |> element("[data-role=reset-gives]", "New Gives") |> render_click()

      # Both phones return to giving form
      eventually(fn -> has_element?(ctx.mara, "[data-role=setting-form]") end)
      assert has_element?(ctx.jacob, "[data-role=setting-form]")

      # Each phone is prefilled with its own last give
      assert render(ctx.mara) =~ "value=\"setting mara\""
      assert render(ctx.jacob) =~ "value=\"setting jacob\""

      # Stage returns to giving count 0 of 2
      eventually(fn -> render(ctx.stage) =~ "Waiting for Gives: 0 of 2" end)
    end

    test "submitting an empty Give shows an error", ctx do
      give_setting(ctx.mara, "   ")
      assert has_element?(ctx.mara, "[data-role=give-error]", "Type a Give first.")
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
      assert render(stage) =~ "Waiting for Gives: 0 of 2"

      give_setting(mara, "lanterns on the quay")
      eventually(fn -> render(stage) =~ "Waiting for Gives: 1 of 2" end)

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
      join(phone1, "Mara")

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
        assert has_element?(phone, "[data-seat]", "Mara")
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
      carried = snapshot.next_bookends
      assert carried == ["beacon", "cairn", "lamp", "seagull"]
      named = ThereishWeb.RoomComponents.join_and(carried)

      for phone <- [phone1, phone2, phone3, phone4] do
        # Again button names every carried word
        assert has_element?(phone, "[data-role=again]")
        assert render(element(phone, "[data-role=again]")) =~ "Again — #{named}"
        assert has_element?(phone, "[data-role=carry-forward]")
        assert render(element(phone, "[data-role=carry-forward]")) =~ named
      end

      # Tap Again to start Attempt 2 with the carried Bookends
      phone1 |> element("[data-role=again]") |> render_click()

      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=attempt]", "Attempt 2") end)

        for word <- carried do
          assert has_element?(phone, "[data-role=bookends]", word)
        end
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
        for name <- ["Mara", "Jacob", "Ada", "Sam"] do
          {:ok, phone, _} = live(phone(code))
          join(phone, name)
          phone
        end

      assert has_element?(stage, "[data-role=giving-stage]")
      assert render(stage) =~ "Waiting for Gives: 0 of 4"

      [p1, p2, p3, p4] = phones
      give_setting(p1, "setting one")
      eventually(fn -> render(stage) =~ "Waiting for Gives: 1 of 4" end)
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
    setup ctx do
      if ms = ctx[:beat], do: beat(ms)

      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      tap_for_sound(stage)

      join(mara, "Mara")
      join(jacob, "Jacob")

      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.put(fake_config, :vamp_mode, :unavailable)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      # The Stage starts wait music from the tap; later tests look at Page events.
      assert_push_event(stage, "foley:page", %{kind: "repertoire"})

      %{slug: slug, mara: mara, jacob: jacob, stage: stage}
    end

    test "waiting Stage: Repertoire draw then tap-for-sound has a foley:page to play" do
      slug = open_room(seat_limit: 6)
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      assert has_element?(stage, "[data-role=tap-for-sound]")
      assert has_element?(stage, "[data-role=music-house]")

      tap_for_sound(stage)

      assert_push_event(stage, "foley:page", %{kind: "repertoire", path: path})
      assert String.starts_with?(path, "/audio/house-loop")

      stage |> element("[data-role=music-off]") |> render_click()
      assert_push_event(stage, "foley:page", %{path: nil})

      stage |> element("[data-role=music-house]") |> render_click()
      assert Rooms.get_room(slug).music == "house"
      assert_push_event(stage, "foley:page", %{kind: "repertoire", path: house_path})
      assert String.starts_with?(house_path, "/audio/house-loop")
    end

    test "the tapped stage holds the speaker; phone claims take it from stage and silence it",
         ctx do
      # The tap has been taken in setup, so it has stopped asking.
      refute has_element?(ctx.stage, "[data-role=tap-for-sound]")
      assert has_element?(ctx.mara, "[data-role=speaker-toggle][data-speaker=other]")
      assert has_element?(ctx.jacob, "[data-role=speaker-toggle][data-speaker=other]")

      assert has_element?(ctx.stage, "[data-role=quick-sound] [data-role=voice-switch]")
      assert has_element?(ctx.stage, "[data-role=quick-sound] [data-role=settings-open]")
      assert has_element?(ctx.stage, "[data-role=settings-modal] [data-role=music-control]")
      assert has_element?(ctx.stage, "[data-role=settings-modal] [data-role=quips-switch]")
      assert has_element?(ctx.stage, "[data-role=settings-modal] [data-role=full-table-switch]")

      assert has_element?(
               ctx.stage,
               "[data-role=settings-modal] [data-role=voice-bookends-switch]"
             )

      assert has_element?(
               ctx.stage,
               "[data-role=settings-modal] [data-role=voice-verdict-switch]"
             )

      refute has_element?(ctx.mara, "[data-role=voice-switch]")
      assert has_element?(ctx.mara, "[data-role=quick-sound] [data-role=settings-open]")
      assert has_element?(ctx.mara, "[data-role=settings-modal] [data-role=music-control]")
      assert has_element?(ctx.mara, "[data-role=settings-modal] [data-role=quips-switch]")
      assert has_element?(ctx.mara, "[data-role=settings-modal] [data-role=full-table-switch]")

      assert has_element?(
               ctx.mara,
               "[data-role=settings-modal] [data-role=voice-bookends-switch]"
             )

      assert has_element?(
               ctx.mara,
               "[data-role=settings-modal] [data-role=voice-verdict-switch]"
             )

      assert has_element?(ctx.mara, "[data-role=local-sound-toggle]")

      assert has_element?(
               ctx.mara,
               "[data-role=local-sound-toggle][title=\"Commit sound plays from the Stage while connected\"]"
             )

      refute has_element?(ctx.jacob, "[data-role=voice-switch]")
      assert has_element?(ctx.jacob, "[data-role=quick-sound] [data-role=settings-open]")
      assert has_element?(ctx.jacob, "[data-role=settings-modal] [data-role=music-control]")
      assert has_element?(ctx.jacob, "[data-role=settings-modal] [data-role=quips-switch]")
      assert has_element?(ctx.jacob, "[data-role=settings-modal] [data-role=full-table-switch]")

      assert has_element?(
               ctx.jacob,
               "[data-role=settings-modal] [data-role=voice-bookends-switch]"
             )

      assert has_element?(ctx.jacob, "[data-role=local-sound-toggle]")
      refute has_element?(ctx.stage, "[data-role=local-sound-toggle]")

      assert has_element?(ctx.stage, "[data-role=voice-switch][data-active=false]")
      assert has_element?(ctx.stage, "[data-role=quips-switch][data-active=true]")
      assert has_element?(ctx.mara, "[data-role=quips-switch][data-active=true]")
      assert has_element?(ctx.jacob, "[data-role=quips-switch][data-active=true]")
      assert has_element?(ctx.stage, "[data-role=full-table-switch][data-active=true]")
      assert has_element?(ctx.mara, "[data-role=full-table-switch][data-active=true]")
      assert has_element?(ctx.jacob, "[data-role=full-table-switch][data-active=true]")
      assert has_element?(ctx.stage, "[data-role=full-table-note]")
      assert has_element?(ctx.mara, "[data-role=full-table-note]")
      assert has_element?(ctx.jacob, "[data-role=full-table-note]")
      assert has_element?(ctx.stage, "[data-role=music-page][data-active=true]")
      assert has_element?(ctx.mara, "[data-role=music-page][data-active=true]")
      assert has_element?(ctx.jacob, "[data-role=music-page][data-active=true]")

      ctx.mara |> element("[data-role=speaker-toggle]") |> render_click()

      assert_push_event(ctx.stage, "foley:stop", %{})

      # The Stage is silent again, so the tap is back on offer: one tap takes
      # the Speaker home.
      assert has_element?(ctx.stage, "[data-role=tap-for-sound]")

      refute has_element?(ctx.stage, "[data-role=voice-switch]")
      assert has_element?(ctx.stage, "[data-role=music-control]")
      assert has_element?(ctx.mara, "[data-role=speaker-toggle][data-speaker=self]")
      assert has_element?(ctx.jacob, "[data-role=speaker-toggle][data-speaker=other]")

      assert has_element?(ctx.mara, "[data-role=voice-switch]")
      refute has_element?(ctx.jacob, "[data-role=voice-switch]")
      assert has_element?(ctx.mara, "[data-role=music-control]")

      # Quips fact toggles from any device and updates all views
      ctx.mara |> element("[data-role=quips-switch]") |> render_click()
      assert Rooms.get_room(ctx.slug).quips == false
      assert has_element?(ctx.mara, "[data-role=quips-switch][data-active=false]")
      assert has_element?(ctx.stage, "[data-role=quips-switch][data-active=false]")
      assert has_element?(ctx.jacob, "[data-role=quips-switch][data-active=false]")

      # Full table fact toggles from any device and updates all views
      ctx.jacob |> element("[data-role=full-table-switch]") |> render_click()
      assert Rooms.get_room(ctx.slug).full_table == false
      assert has_element?(ctx.jacob, "[data-role=full-table-switch][data-active=false]")
      assert has_element?(ctx.stage, "[data-role=full-table-switch][data-active=false]")
      assert has_element?(ctx.mara, "[data-role=full-table-switch][data-active=false]")

      ctx.jacob |> element("[data-role=music-off]") |> render_click()
      assert Rooms.get_room(ctx.slug).music == "off"
      assert has_element?(ctx.mara, "[data-role=music-off][data-active=true]")
      assert has_element?(ctx.stage, "[data-role=music-off][data-active=true]")
      assert has_element?(ctx.jacob, "[data-role=music-off][data-active=true]")
    end

    # The Stage hears the Beat from an assaying snapshot, so the Beat must
    # outlast the broadcast that carries it.
    @tag beat: 200
    test "foley events push to the speaking view alone across a Page arc", ctx do
      give_setting(ctx.mara, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{kind: "track", path: track_path})
      assert String.starts_with?(track_path, "/media/tracks/fake-")
      refute_push_event(ctx.mara, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})

      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairo")

      assert_push_event(ctx.stage, "foley:beat", %{})
      refute_push_event(ctx.mara, "foley:beat", %{})
      refute_push_event(ctx.jacob, "foley:beat", %{})

      await_reveal_on(ctx.stage)
      assert_push_event(ctx.stage, "foley:sting", %{band: _})
      refute_push_event(ctx.mara, "foley:sting", %{})
      refute_push_event(ctx.jacob, "foley:sting", %{})

      ctx.mara |> element("[data-role=speaker-toggle]") |> render_click()
      assert_push_event(ctx.stage, "foley:stop", %{})
      assert_push_event(ctx.mara, "foley:page", %{path: mara_track_path})
      assert mara_track_path == track_path

      ctx.mara |> element("[data-role=again]") |> render_click()
      await_phase(ctx.slug, :bridging)
      eventually(fn -> has_element?(ctx.mara, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.jacob, "[data-role=bridge-form]") end)

      commit(ctx.mara, "stone")
      commit(ctx.jacob, "stone")

      assert_push_event(ctx.mara, "foley:beat", %{})
      refute_push_event(ctx.stage, "foley:beat", %{})

      await_reveal_on(ctx.mara)
      assert_push_event(ctx.mara, "foley:sting", %{band: _})
      assert_push_event(ctx.mara, "foley:ending", %{kind: :deep_meld})
      refute_push_event(ctx.stage, "foley:sting", %{})
      refute_push_event(ctx.stage, "foley:ending", %{})
    end

    test "foley:ending pushes :meld when closing on a meld band", ctx do
      give_setting(ctx.mara, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{path: _})

      # cairns and cairn has shared prefix 5/11 -> closeness 91, which is in :meld band
      commit(ctx.mara, "cairns")
      commit(ctx.jacob, "cairn")

      assert_push_event(ctx.stage, "foley:beat", %{})
      await_reveal_on(ctx.stage)

      assert_push_event(ctx.stage, "foley:sting", %{band: :meld})
      assert_push_event(ctx.stage, "foley:ending", %{kind: :meld})
      refute_push_event(ctx.mara, "foley:ending", %{})
      refute_push_event(ctx.jacob, "foley:ending", %{})
    end

    test "foley:ending pushes :unmelded when closing without a meld", ctx do
      attempt_cap(1)

      give_setting(ctx.mara, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{path: _})

      # cairn and beacon share 0 prefix -> closeness 0, miss
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "beacon")

      assert_push_event(ctx.stage, "foley:beat", %{})
      await_reveal_on(ctx.stage)

      assert_push_event(ctx.stage, "foley:sting", %{band: :miss})
      assert_push_event(ctx.stage, "foley:ending", %{kind: :unmelded})
      refute_push_event(ctx.mara, "foley:ending", %{})
      refute_push_event(ctx.jacob, "foley:ending", %{})
    end

    test "music control pushes off, house, and page to speaker alone", ctx do
      give_setting(ctx.mara, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{kind: "track", path: track_path})
      assert String.starts_with?(track_path, "/media/tracks/fake-")
      refute_push_event(ctx.mara, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})

      # Setting off (e.g. from Mara's phone) pushes path: nil to speaker alone
      ctx.mara |> element("[data-role=music-off]") |> render_click()

      assert_push_event(ctx.stage, "foley:page", %{path: nil})
      refute_push_event(ctx.mara, "foley:page", %{})
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

      refute_push_event(ctx.mara, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})

      # Setting back to page (from stage) pushes track_path to speaker alone
      ctx.stage |> element("[data-role=music-page]") |> render_click()

      assert_push_event(ctx.stage, "foley:page", %{path: ^track_path})
      refute_push_event(ctx.mara, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})
    end

    test "starting a page under off pushes nil path to speaker", ctx do
      ctx.mara |> element("[data-role=music-off]") |> render_click()
      assert Rooms.get_room(ctx.slug).music == "off"

      give_setting(ctx.mara, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{path: nil})
      refute_push_event(ctx.mara, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})
    end

    test "leaving stage releases speaker", ctx do
      assert Rooms.get_room(ctx.slug).speaker != nil

      GenServer.stop(ctx.stage.pid)

      eventually(fn ->
        is_nil(Rooms.get_room(ctx.slug).speaker)
      end)
    end

    # The Stage hears the Beat from an assaying snapshot, so the Beat must
    # outlast the broadcast that carries it.
    @tag beat: 200
    test "foley:beat, foley:sting, and foley:voice push in order to speaking view alone", ctx do
      give_setting(ctx.mara, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{path: _})
      refute_push_event(ctx.mara, "foley:page", %{})
      refute_push_event(ctx.jacob, "foley:page", %{})

      expected_bookends_url = "/r/#{ctx.slug}/voice/1/bookends"

      assert_push_event(ctx.stage, "foley:voice", %{
        attempt: 1,
        kind: "bookends",
        url: ^expected_bookends_url
      })

      refute_push_event(ctx.mara, "foley:voice", %{})
      refute_push_event(ctx.jacob, "foley:voice", %{})

      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairo")

      # Ordered push sequence: beat -> sting -> voice
      assert_push_event(ctx.stage, "foley:beat", %{})
      refute_push_event(ctx.mara, "foley:beat", %{})
      refute_push_event(ctx.jacob, "foley:beat", %{})

      await_reveal_on(ctx.stage)

      assert_push_event(ctx.stage, "foley:sting", %{band: _})
      refute_push_event(ctx.mara, "foley:sting", %{})
      refute_push_event(ctx.jacob, "foley:sting", %{})

      expected_stage_url = "/r/#{ctx.slug}/voice/1"

      assert_push_event(ctx.stage, "foley:voice", %{
        attempt: 1,
        kind: "verdict",
        url: ^expected_stage_url
      })

      refute_push_event(ctx.mara, "foley:voice", %{})
      refute_push_event(ctx.jacob, "foley:voice", %{})

      # Phone claims speaker
      ctx.mara |> element("[data-role=speaker-toggle]") |> render_click()

      ctx.mara |> element("[data-role=again]") |> render_click()
      await_phase(ctx.slug, :bridging)
      eventually(fn -> has_element?(ctx.mara, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.jacob, "[data-role=bridge-form]") end)

      expected_mara_bookends = "/r/#{ctx.slug}/voice/2/bookends"

      assert_push_event(ctx.mara, "foley:voice", %{
        attempt: 2,
        kind: "bookends",
        url: ^expected_mara_bookends
      })

      commit(ctx.mara, "stone")
      commit(ctx.jacob, "stone")

      assert_push_event(ctx.mara, "foley:beat", %{})
      refute_push_event(ctx.stage, "foley:beat", %{})

      await_reveal_on(ctx.mara)

      assert_push_event(ctx.mara, "foley:sting", %{band: _})
      expected_mara_url = "/r/#{ctx.slug}/voice/2"

      assert_push_event(ctx.mara, "foley:voice", %{
        attempt: 2,
        kind: "verdict",
        url: ^expected_mara_url
      })

      refute_push_event(ctx.stage, "foley:sting", %{})
      refute_push_event(ctx.stage, "foley:voice", %{})
      refute_push_event(ctx.jacob, "foley:voice", %{})
    end

    test "a later Room change or phone resync does not replay Bookends speech", ctx do
      give_setting(ctx.mara, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      expected_bookends_url = "/r/#{ctx.slug}/voice/1/bookends"

      assert_push_event(ctx.stage, "foley:voice", %{
        attempt: 1,
        kind: "bookends",
        url: ^expected_bookends_url
      })

      Rooms.set_quips(ctx.slug, false)
      refute_push_event(ctx.stage, "foley:voice", %{})

      render_hook(ctx.mara, "resync", %{})
      refute_push_event(ctx.mara, "foley:voice", %{})
      refute_push_event(ctx.stage, "foley:voice", %{})
    end

    test "ticket 10: quips toggle hides reveal quip everywhere while room quip still shows, and stings still push with voice off" do
      slug = open_room(quip: "A gentle word for quiet hours.")
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      tap_for_sound(stage)

      join(mara, "Mara")
      join(jacob, "Jacob")

      give_setting(mara, "setting one")
      give_setting(jacob, "setting two")
      await_phase(slug, :bridging)

      commit(mara, "cairn")
      commit(jacob, "cairo")

      await_reveal_on(stage)
      await_reveal_on(mara)

      # Initially quips is true: reveal quip is present on stage, room quip shows on stage footer
      assert has_element?(stage, "[data-role=quip]")
      assert has_element?(stage, "[data-role=stage-quip]", "A gentle word for quiet hours.")

      # Stings still push to speaker (stage) even with voice off
      assert_push_event(stage, "foley:sting", %{band: _})

      # Toggle quips switch from a phone device
      mara |> element("[data-role=quips-switch]") |> render_click()
      assert Rooms.get_room(slug).quips == false

      # Reveal quip is hidden everywhere
      refute has_element?(stage, "[data-role=quip]")
      refute has_element?(mara, "[data-role=quip]")
      refute has_element?(jacob, "[data-role=quip]")

      # Room quip still shows on Stage footer
      assert has_element?(stage, "[data-role=stage-quip]", "A gentle word for quiet hours.")

      # Next Page: confirm quips stays false and reveal quip stays hidden
      mara |> element("[data-role=again]") |> render_click()
      await_phase(slug, :bridging)
      eventually(fn -> has_element?(mara, "[data-role=bridge-form]") end)

      commit(mara, "stone")
      commit(jacob, "stone")

      await_reveal_on(stage)
      refute has_element?(stage, "[data-role=quip]")
      assert has_element?(stage, "[data-role=stage-quip]", "A gentle word for quiet hours.")
      assert_push_event(stage, "foley:sting", %{band: _})
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
          Keyword.merge(fake_config, music_delay_ms: 500, vamp_mode: :unavailable)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      give_setting(ctx.mara, "mountain cabin")
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
      refute has_element?(ctx.mara, "[data-role=now-playing]")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")

      # Check position on stage: now-playing is below the fold (after bookends)
      stage_html = render(ctx.stage)

      assert_order(stage_html, [
        ~s(data-role="bookends"),
        ~s(data-role="now-playing")
      ])

      # Mara claims speaker: Mara's phone now shows the Now playing line below the fold
      ctx.mara |> element("[data-role=speaker-toggle]") |> render_click()
      assert has_element?(ctx.mara, "[data-role=now-playing]", expected_loop.name)
      assert has_element?(ctx.mara, "[data-role=now-playing]", "the Repertoire")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")

      # Check position on Mara's phone: now-playing is below the fold (after bridge-form, before In the Room)
      mara_html = render(ctx.mara)

      assert_order(mara_html, [
        ~s(data-role="bridge-form"),
        ~s(data-role="now-playing"),
        "In the Room"
      ])

      # Setting off: pushes nil path to speaker, and Now playing says "Music is off"
      ctx.mara |> element("[data-role=music-off]") |> render_click()
      assert_push_event(ctx.mara, "foley:page", %{path: nil})
      assert has_element?(ctx.stage, "[data-role=now-playing]", "Music is off")
      assert has_element?(ctx.mara, "[data-role=now-playing]", "Music is off")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")

      # Setting house: pushes loop with title and kind: "repertoire" to speaker
      ctx.mara |> element("[data-role=music-house]") |> render_click()

      assert_push_event(ctx.mara, "foley:page", %{
        path: ^loop_path,
        title: ^loop_title,
        kind: "repertoire"
      })

      assert has_element?(ctx.stage, "[data-role=now-playing]", expected_loop.name)
      assert has_element?(ctx.stage, "[data-role=now-playing]", "the Repertoire")
      assert has_element?(ctx.mara, "[data-role=now-playing]", expected_loop.name)
      assert has_element?(ctx.mara, "[data-role=now-playing]", "the Repertoire")
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
          Keyword.merge(fake_config,
            music_delay_ms: 100,
            title_delay_ms: 0,
            vamp_mode: :unavailable
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

      give_setting(ctx.mara, "summer camp")
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
          "Now playing: written for this Page"
        )
      end)

      refute has_element?(
               ctx.stage,
               "[data-role=now-playing]",
               "Summer Camp · Viking Beaches"
             )
    end

    test "Speaker receives Vamp then Track as two music pushes with kind distinguishing them",
         ctx do
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

      give_setting(ctx.mara, "alpine forest")
      give_setting(ctx.jacob, "snowy peaks")
      await_phase(ctx.slug, :bridging)

      # 1. Vamp arrives early with kind: "vamp"
      assert_push_event(
        ctx.stage,
        "foley:page",
        %{
          path: vamp_path,
          kind: "vamp"
        },
        1000
      )

      assert String.starts_with?(vamp_path, "/media/vamps/")

      # "Now playing" line updates on speaker
      eventually(fn ->
        has_element?(
          ctx.stage,
          "[data-role=now-playing]",
          "Now playing: written for this Page"
        )
      end)

      refute has_element?(
               ctx.stage,
               "[data-role=now-playing]",
               "Alpine Forest · Snowy Peaks"
             )

      # 2. Later, completed Track lands and pushes updated foley:page with kind: "track"
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
            vamp_mode: :ok,
            vamp_delay_ms: 0,
            music_mode: :unavailable,
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

      give_setting(ctx.mara, "alpine forest")
      give_setting(ctx.jacob, "snowy peaks")
      await_phase(ctx.slug, :bridging)

      # 1. Vamp lands first
      assert_push_event(
        ctx.stage,
        "foley:page",
        %{
          path: _vamp_path,
          kind: "vamp"
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
      # In giving phase (setup joins Mara & Jacob)
      snapshot = Rooms.snapshot(ctx.slug, nil)
      assert snapshot.playing.kind == "repertoire"
      title = snapshot.playing.title
      path = snapshot.playing.path
      assert is_binary(path) and is_binary(title)

      # Now playing line renders below the fold on speaking Stage
      assert has_element?(ctx.stage, "[data-role=now-playing]", title)
      assert has_element?(ctx.stage, "[data-role=now-playing]", "the Repertoire")

      # Non-speaking phones do not show Now playing
      refute has_element?(ctx.mara, "[data-role=now-playing]")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")

      # Mara claims speaker during giving: Mara gets foley:page and shows Now playing
      ctx.mara |> element("[data-role=speaker-toggle]") |> render_click()

      assert_push_event(ctx.mara, "foley:page", %{
        path: ^path,
        title: ^title,
        kind: "repertoire"
      })

      assert has_element?(ctx.mara, "[data-role=now-playing]", title)
      assert has_element?(ctx.mara, "[data-role=now-playing]", "the Repertoire")
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
      give_setting(ctx.mara, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)

      assert_push_event(ctx.stage, "foley:page", %{kind: "repertoire"})

      assert_push_event(
        ctx.stage,
        "foley:page",
        %{
          path: p1_path,
          title: p1_title,
          kind: "track"
        },
        1000
      )

      eventually(fn ->
        has_element?(
          ctx.stage,
          "[data-role=now-playing]",
          "Now playing: written for this Page"
        )
      end)

      refute has_element?(
               ctx.stage,
               "[data-role=now-playing]",
               p1_title
             )

      eventually(fn -> has_element?(ctx.mara, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.jacob, "[data-role=bridge-form]") end)

      commit(ctx.mara, "cairn")
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
      eventually(fn -> has_element?(ctx.mara, "[data-role=one-more]") end)
      ctx.mara |> element("[data-role=one-more]") |> render_click()
      await_phase(ctx.slug, :giving)

      # Giving keeps Page 1's track: Now playing still shows holdover
      assert has_element?(
               ctx.stage,
               "[data-role=now-playing]",
               "Now playing: #{p1_title} (last Page's Track)"
             )

      refute has_element?(ctx.mara, "[data-role=now-playing]")
      refute has_element?(ctx.jacob, "[data-role=now-playing]")

      # Mara claims speaker during giving: Mara gets foley:page with holdover
      ctx.mara |> element("[data-role=speaker-toggle]") |> render_click()

      assert_push_event(ctx.mara, "foley:page", %{
        path: ^p1_path,
        title: ^p1_title,
        kind: "holdover"
      })

      assert has_element?(
               ctx.mara,
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
      give_setting(ctx.mara, "whispering pines")
      give_setting(ctx.jacob, "winding river")

      # Writing keeps Page 1's track as holdover
      assert has_element?(ctx.mara, "[data-role=writing-phase]")

      assert has_element?(
               ctx.mara,
               "[data-role=now-playing]",
               "Now playing: #{p1_title} (last Page's Track)"
             )

      # When Page 2 track lands, it seizes the speaker during writing
      assert_push_event(ctx.mara, "foley:page", %{
        path: p2_path,
        title: p2_title,
        kind: "track"
      })

      assert p2_path != p1_path

      eventually(fn ->
        has_element?(
          ctx.mara,
          "[data-role=now-playing]",
          "Now playing: written for this Page"
        )
      end)

      refute has_element?(
               ctx.mara,
               "[data-role=now-playing]",
               p2_title
             )
    end

    test "ticket 03: Next renders only on the speaking screen, below the fold with the music control, and pushes new foley:page on tap",
         ctx do
      initial_path = Rooms.snapshot(ctx.slug, ctx.mara.id).playing.path

      # Mara claims speaker
      ctx.mara |> element("[data-role=speaker-toggle]") |> render_click()
      assert_push_event(ctx.mara, "foley:page", %{kind: "repertoire", path: ^initial_path})

      # Mara is now speaker; Jacob and Stage are not
      assert has_element?(ctx.mara, "[data-role=music-control]")
      assert has_element?(ctx.mara, "[data-role=music-next]")

      refute has_element?(ctx.jacob, "[data-role=music-next]")
      refute has_element?(ctx.stage, "[data-role=music-next]")

      # Tap Next on Mara (speaking screen)
      ctx.mara |> element("[data-role=music-next]") |> render_click()

      # foley:page is pushed with new path
      assert_push_event(ctx.mara, "foley:page", %{
        kind: "repertoire",
        path: new_path,
        title: new_title
      })

      assert new_path != initial_path

      assert has_element?(
               ctx.mara,
               "[data-role=now-playing]",
               "Now playing: #{new_title} (the Repertoire)"
             )

      # Jacob and Stage do not get foley:page
      refute_push_event(ctx.jacob, "foley:page", %{})
      refute_push_event(ctx.stage, "foley:page", %{})

      # Now progress page until this Page's Track lands
      give_setting(ctx.mara, "mountain ridge")
      give_setting(ctx.jacob, "silent valley")
      await_phase(ctx.slug, :bridging)

      receive do
        {_ref, {:push_event, "foley:page", %{kind: "repertoire"}}} -> :ok
      after
        0 -> :ok
      end

      assert_push_event(
        ctx.mara,
        "foley:page",
        %{kind: "track", path: p1_track_path, title: _},
        1000
      )

      # Once this Page's Track is playing: Next is hidden on the speaking screen
      eventually(fn ->
        not has_element?(ctx.mara, "[data-role=music-next]")
      end)

      # Finish Page 1 to closed
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Advance to Page 2 (holdover)
      eventually(fn -> has_element?(ctx.mara, "[data-role=one-more]") end)
      ctx.mara |> element("[data-role=one-more]") |> render_click()
      await_phase(ctx.slug, :giving)

      # During holdover on Page 2: Next is visible again on speaking screen
      eventually(fn ->
        has_element?(ctx.mara, "[data-role=music-next]")
      end)

      # Tap Next to skip holdover
      ctx.mara |> element("[data-role=music-next]") |> render_click()

      # Pushes foley:page with repertoire draw
      assert_push_event(ctx.mara, "foley:page", %{
        kind: "repertoire",
        path: skipped_path,
        title: skipped_title
      })

      refute skipped_path == p1_track_path

      assert has_element?(
               ctx.mara,
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
      initial_path = Rooms.snapshot(ctx.slug, ctx.mara.id).playing.path

      # Mara claims speaker
      ctx.mara |> element("[data-role=speaker-toggle]") |> render_click()
      assert_push_event(ctx.mara, "foley:page", %{kind: "repertoire", path: ^initial_path})

      # Mara is speaker; Jacob and Stage are not
      assert has_element?(ctx.mara, "[data-role=music-never]")
      refute has_element?(ctx.jacob, "[data-role=music-never]")
      refute has_element?(ctx.stage, "[data-role=music-never]")

      # Tap Never on wait music
      ctx.mara |> element("[data-role=music-never]") |> render_click()

      assert_push_event(ctx.mara, "foley:page", %{
        kind: "repertoire",
        path: new_path,
        title: _new_title
      })

      assert new_path != initial_path
      assert initial_path in Thereish.Rooms.Store.list_nevers(Rooms.Store.get_room(ctx.slug).id)

      # Progress page until this Page's Track lands
      give_setting(ctx.mara, "mountain ridge")
      give_setting(ctx.jacob, "silent valley")
      await_phase(ctx.slug, :bridging)

      receive do
        {_ref, {:push_event, "foley:page", %{kind: "repertoire"}}} -> :ok
      after
        0 -> :ok
      end

      assert_push_event(
        ctx.mara,
        "foley:page",
        %{kind: "track", path: p1_track_path, title: _},
        1000
      )

      # While Page's Track is playing: Next is hidden, but Never is still rendered!
      eventually(fn ->
        not has_element?(ctx.mara, "[data-role=music-next]") and
          has_element?(ctx.mara, "[data-role=music-never]")
      end)

      # Tap Never on this Page's Track
      ctx.mara |> element("[data-role=music-never]") |> render_click()

      # Track is refused: pushes foley:page for Repertoire draw
      assert_push_event(ctx.mara, "foley:page", %{
        kind: "repertoire",
        path: next_rep_path,
        title: next_rep_title
      })

      refute next_rep_path == p1_track_path
      assert p1_track_path in Thereish.Rooms.Store.list_nevers(Rooms.Store.get_room(ctx.slug).id)

      eventually(fn ->
        has_element?(
          ctx.mara,
          "[data-role=now-playing]",
          "Now playing: #{next_rep_title} (the Repertoire)"
        )
      end)
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
      refute has_element?(ctx.mara, "[data-role=music-next]")
      refute has_element?(ctx.mara, "[data-role=music-never]")
      refute has_element?(ctx.jacob, "[data-role=music-next]")
      refute has_element?(ctx.jacob, "[data-role=music-never]")

      # Gives submitted for Page 1
      give_setting(ctx.mara, "mountain ridge")
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
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      # Page closes: landed Track still playing as holdover
      closed_snapshot = Rooms.snapshot(ctx.slug, nil)
      assert closed_snapshot.playing.kind == "holdover"
      assert closed_snapshot.playing.path == p1_track_path

      # "One more?" keeps that Track through giving
      eventually(fn -> has_element?(ctx.mara, "[data-role=one-more]") end)
      ctx.mara |> element("[data-role=one-more]") |> render_click()
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
      give_setting(ctx.mara, "deep woods")
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
      give_setting(ctx.mara, "setting alpha")
      give_setting(ctx.jacob, "setting beta")
      await_phase(ctx.slug, :bridging)

      receive do
        {_ref, {:push_event, "foley:page", %{kind: "repertoire"}}} -> :ok
      after
        0 -> :ok
      end

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
      give_setting(ctx.mara, "cozy fireplace")
      give_setting(ctx.jacob, "warm blanket")
      await_phase(ctx.slug, :bridging)
      refute Rooms.snapshot(ctx.slug, nil).track

      # 2. Switch to Written for this Page: now starts score and lands track
      ctx.stage |> element("[data-role=music-page]") |> render_click()
      eventually(fn -> Rooms.snapshot(ctx.slug, nil).music == "page" end)

      assert_push_event(
        ctx.stage,
        "foley:page",
        %{
          kind: "track",
          path: landed_path
        },
        1000
      )

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
      commit(ctx.mara, "cozy")
      commit(ctx.jacob, "cozy")
      await_reveal(ctx.slug)
      assert_push_event(ctx.stage, "foley:sting", %{})
    end

    test "ticket 05: without a Stage, the claiming phone is the only one that plays the chain; Next and Never live there" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      join(mara, "Mara")
      join(jacob, "Jacob")

      # Before claiming: neither phone plays sound or shows Next/Never
      refute has_element?(mara, "[data-role=music-next]")
      refute has_element?(mara, "[data-role=music-never]")
      refute has_element?(jacob, "[data-role=music-next]")
      refute has_element?(jacob, "[data-role=music-never]")
      refute_push_event(mara, "foley:page", %{})
      refute_push_event(jacob, "foley:page", %{})

      # Mara claims speaker
      mara |> element("[data-role=speaker-toggle]") |> render_click()

      # Only Mara gets foley:page; Next and Never live on Mara
      assert_push_event(mara, "foley:page", %{kind: "repertoire"})
      refute_push_event(jacob, "foley:page", %{})
      assert has_element?(mara, "[data-role=music-next]")
      assert has_element?(mara, "[data-role=music-never]")
      refute has_element?(jacob, "[data-role=music-next]")
      refute has_element?(jacob, "[data-role=music-never]")

      # Jacob claims speaker: transfers to Jacob, Mara is silenced
      jacob |> element("[data-role=speaker-toggle]") |> render_click()

      assert_push_event(jacob, "foley:page", %{kind: "repertoire"})
      assert_push_event(mara, "foley:stop", %{})
      assert has_element?(jacob, "[data-role=music-next]")
      assert has_element?(jacob, "[data-role=music-never]")
      refute has_element?(mara, "[data-role=music-next]")
      refute has_element?(mara, "[data-role=music-never]")
    end

    test "ticket 05: Foley track generation records charges visible on /spend", ctx do
      give_setting(ctx.mara, "setting emerald")
      give_setting(ctx.jacob, "setting sapphire")
      await_phase(ctx.slug, :bridging)

      receive do
        {_ref, {:push_event, "foley:page", %{kind: "repertoire"}}} -> :ok
      after
        0 -> :ok
      end

      assert_push_event(ctx.stage, "foley:page", %{kind: "track", path: _}, 1000)

      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      {:ok, _view, html} = live(log_in_admin(build_conn()), ~p"/spend")
      assert html =~ "Foley"
    end

    test "commit pushes foley:commit to stage and foley:own-commit to nobody when stage is present",
         ctx do
      give_setting(ctx.mara, "setting one")
      give_setting(ctx.jacob, "setting two")
      await_phase(ctx.slug, :bridging)
      eventually(fn -> has_element?(ctx.mara, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.jacob, "[data-role=bridge-form]") end)

      commit(ctx.mara, "cairn")

      assert_push_event(ctx.stage, "foley:commit", %{})
      refute_push_event(ctx.mara, "foley:own-commit", %{})
      refute_push_event(ctx.jacob, "foley:commit", %{})
      refute_push_event(ctx.jacob, "foley:own-commit", %{})
      refute_push_event(ctx.mara, "foley:commit", %{})
      refute_push_event(ctx.stage, "foley:own-commit", %{})

      commit(ctx.jacob, "cairo")

      assert_push_event(ctx.stage, "foley:commit", %{})
      refute_push_event(ctx.jacob, "foley:own-commit", %{})
      refute_push_event(ctx.mara, "foley:commit", %{})
      refute_push_event(ctx.mara, "foley:own-commit", %{})
      refute_push_event(ctx.jacob, "foley:commit", %{})
      refute_push_event(ctx.stage, "foley:own-commit", %{})
    end

    test "with no Stage and one phone holding Speaker, commit pushes foley:own-commit to committer and foley:commit to nobody" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      join(mara, "Mara")
      join(jacob, "Jacob")

      mara |> element("[data-role=speaker-toggle]") |> render_click()
      assert has_element?(mara, "[data-role=speaker-toggle][data-speaker=self]")

      assert has_element?(
               mara,
               "[data-role=local-sound-toggle][title=\"Toggle commit sound on this device\"]"
             )

      give_setting(mara, "setting one")
      give_setting(jacob, "setting two")
      await_phase(slug, :bridging)
      eventually(fn -> has_element?(mara, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(jacob, "[data-role=bridge-form]") end)

      commit(mara, "cairn")

      assert_push_event(mara, "foley:own-commit", %{})
      refute_push_event(mara, "foley:commit", %{})
      refute_push_event(jacob, "foley:commit", %{})
      refute_push_event(jacob, "foley:own-commit", %{})

      commit(jacob, "cairo")

      assert_push_event(jacob, "foley:own-commit", %{})
      refute_push_event(jacob, "foley:commit", %{})
      refute_push_event(mara, "foley:commit", %{})
      refute_push_event(mara, "foley:own-commit", %{})
    end

    test "stage leaving mid-Page moves commit sound to committer phone on next commit" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      join(mara, "Mara")
      join(jacob, "Jacob")

      give_setting(mara, "setting one")
      give_setting(jacob, "setting two")
      await_phase(slug, :bridging)
      eventually(fn -> has_element?(mara, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(jacob, "[data-role=bridge-form]") end)

      # First commit with Stage present: Stage sounds, phones are quiet
      commit(mara, "cairn")
      assert_push_event(stage, "foley:commit", %{})
      refute_push_event(mara, "foley:own-commit", %{})
      refute_push_event(jacob, "foley:own-commit", %{})

      # Stage leaves mid-Page
      GenServer.stop(stage.pid)
      eventually(fn -> not ThereishWeb.Presence.stage_present?(slug) end)

      # Second commit with Stage gone: committer phone sounds
      commit(jacob, "cairo")
      assert_push_event(jacob, "foley:own-commit", %{})
      refute_push_event(mara, "foley:own-commit", %{})
    end

    test "stage joining mid-Page moves commit sound to Stage on next commit" do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      join(mara, "Mara")
      join(jacob, "Jacob")

      give_setting(mara, "setting one")
      give_setting(jacob, "setting two")
      await_phase(slug, :bridging)
      eventually(fn -> has_element?(mara, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(jacob, "[data-role=bridge-form]") end)

      # First commit with no Stage: committer phone sounds
      commit(mara, "cairn")
      assert_push_event(mara, "foley:own-commit", %{})
      refute_push_event(jacob, "foley:own-commit", %{})

      # Stage joins mid-Page
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      eventually(fn -> ThereishWeb.Presence.stage_present?(slug) end)

      # Second commit with Stage now present: Stage sounds, phones are quiet
      commit(jacob, "cairo")
      assert_push_event(stage, "foley:commit", %{})
      refute_push_event(jacob, "foley:own-commit", %{})
      refute_push_event(mara, "foley:own-commit", %{})
    end
  end

  describe "a four-Seat Room plays as one table" do
    setup do
      beat(0)
      steward(delay_ms: 0)
      :ok
    end

    test "offers no partners, grades one Verdict, and an overrule needs the whole Room" do
      code = open_room(seat_limit: 4)

      {:ok, phone1, _} = live(phone(code))
      join(phone1, "Mara")

      {:ok, phone2, html2} = live(phone(code))
      refute html2 =~ ~s(data-role="partner-select")
      refute html2 =~ "Partner (optional)"
      join(phone2, "Jacob")

      {:ok, phone3, _} = live(phone(code))
      join(phone3, "Ada")

      {:ok, phone4, _} = live(phone(code))
      join(phone4, "Sam")

      for phone <- [phone1, phone2, phone3, phone4] do
        html = render(phone)
        refute has_element?(phone, "[data-role=partner-picker]")
        refute has_element?(phone, "[data-role=partner-select]")
        refute has_element?(phone, "[data-role=pair-partner]")
        refute html =~ "I'm with"
        refute html =~ "Couple versus Couple"
        refute html =~ "Pick your partner"
      end

      give_setting(phone1, "setting one")
      give_setting(phone2, "setting two")
      give_setting(phone3, "setting three")
      give_setting(phone4, "setting four")

      await_phase(code, :bridging)

      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=bridge-form]") end)
      end

      commit(phone1, "beacon")
      commit(phone2, "pier")
      commit(phone3, "lamp")
      commit(phone4, "seagull")

      await_reveal(code)

      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=reveal]") end)
        assert has_element?(phone, "[data-role=closeness]")
        assert has_element?(phone, "[data-role=propose-overrule]")
      end

      phone1 |> element("[data-role=propose-overrule]") |> render_click()

      assert render(phone1) =~ "Waiting for everyone to agree"

      for phone <- [phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=agree-overrule]") end)
      end

      phone2 |> element("[data-role=agree-overrule]") |> render_click()
      phone3 |> element("[data-role=agree-overrule]") |> render_click()

      refute Rooms.snapshot(code, nil).phase == :closed

      phone4 |> element("[data-role=agree-overrule]") |> render_click()

      await_phase(code, :closed)

      for phone <- [phone1, phone2, phone3, phone4] do
        eventually(fn -> has_element?(phone, "[data-role=overruled-notice]") end)
      end
    end
  end

  describe "the Room starts when everyone is here (ticket 08)" do
    test "count-free start with Start Page button and late seat joins next page" do
      # 1. Front page -> New Room (no player count chosen, opens at the seat cap)
      conn1 = build_conn()
      {:ok, front, _} = live(conn1, ~p"/")
      assert has_element?(front, "[data-role=new-room]")

      {:ok, new_room_view, _} = live(conn1, ~p"/new")
      refute has_element?(new_room_view, "select[name=players]")

      assert {:error, {:live_redirect, %{to: to}}} =
               new_room_view |> form("form") |> render_submit()

      "/r/" <> code = to
      on_exit(fn -> stop_room(code) end)

      assert Rooms.snapshot(code, nil).seat_limit == Thereish.Steward.seat_cap()

      # Phone 1 connects and joins
      {:ok, phone1, _} = live(conn1, to)
      join(phone1, "Mara")

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

  describe "the title keeps the secret, the end screen tells it (ticket 09)" do
    setup do
      slug = open_room()
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      tap_for_sound(stage)

      join(mara, "Mara")
      join(jacob, "Jacob")

      %{slug: slug, mara: mara, jacob: jacob, stage: stage}
    end

    test "\"Now playing\" reads \"written for this Page\" before reveal and shows title after; Gives with Seat names render on closed Page reveal on phone and Stage",
         ctx do
      # 1. Giving phase: Mara and Jacob give settings
      give_setting(ctx.mara, "lighthouse on the rocks")
      give_setting(ctx.jacob, "candle in the window")
      await_phase(ctx.slug, :bridging)

      # Track lands for the page
      assert_push_event(
        ctx.stage,
        "foley:page",
        %{
          path: _track_path,
          title: track_title,
          kind: "track"
        },
        1000
      )

      # 2. Before reveal: "Now playing" reads "written for this Page" on Stage
      # Excludes Track's title
      eventually(fn ->
        has_element?(
          ctx.stage,
          "[data-role=now-playing]",
          "Now playing: written for this Page"
        )
      end)

      refute has_element?(ctx.stage, "[data-role=now-playing]", track_title)

      # Both players commit bridges and close the page with a meld
      eventually(fn -> has_element?(ctx.mara, "[data-role=bridge-form]") end)
      eventually(fn -> has_element?(ctx.jacob, "[data-role=bridge-form]") end)

      commit(ctx.mara, "beacon")
      commit(ctx.jacob, "beacon")
      await_reveal(ctx.slug)

      # 3. After reveal: title is now visible in "Now playing"
      eventually(fn ->
        has_element?(
          ctx.stage,
          "[data-role=now-playing]",
          track_title
        )
      end)

      await_phase(ctx.slug, :closed)

      # On closed page, the title is still visible
      assert has_element?(
               ctx.stage,
               "[data-role=now-playing]",
               track_title
             )

      # 4. Gives with Seat names render on the closed Page's reveal on phone and Stage
      eventually(fn ->
        has_element?(ctx.stage, "[data-role=gives]") and
          has_element?(ctx.mara, "[data-role=gives]") and
          has_element?(ctx.jacob, "[data-role=gives]")
      end)

      # Stage shows every Seat's Give with Seat name
      assert has_element?(ctx.stage, "[data-role=give][data-seat]", "Mara")
      assert has_element?(ctx.stage, "[data-role=give][data-seat]", "lighthouse on the rocks")
      assert has_element?(ctx.stage, "[data-role=give][data-seat]", "Jacob")
      assert has_element?(ctx.stage, "[data-role=give][data-seat]", "candle in the window")

      # Phones also show every Seat's Give with Seat name
      assert has_element?(ctx.mara, "[data-role=give][data-seat]", "Mara")
      assert has_element?(ctx.mara, "[data-role=give][data-seat]", "lighthouse on the rocks")
      assert has_element?(ctx.mara, "[data-role=give][data-seat]", "Jacob")
      assert has_element?(ctx.mara, "[data-role=give][data-seat]", "candle in the window")

      assert has_element?(ctx.jacob, "[data-role=give][data-seat]", "Mara")
      assert has_element?(ctx.jacob, "[data-role=give][data-seat]", "lighthouse on the rocks")
      assert has_element?(ctx.jacob, "[data-role=give][data-seat]", "Jacob")
      assert has_element?(ctx.jacob, "[data-role=give][data-seat]", "candle in the window")
    end
  end

  describe "the prologue (ticket 14)" do
    test "Stage on a Room with no Chronicle plays a reading from the tap when Voice is on, shows words only when off" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      refute has_element?(stage, "[data-role=prologue-words]")
      refute has_element?(stage, "[data-role=play-prologue]")

      tap_for_sound(stage)

      # Audio reading event pushed to speaking stage
      assert_push_event(stage, "foley:prologue", %{path: reading})
      assert String.starts_with?(reading, "/audio/prologue-")

      # Words show on the Stage
      assert has_element?(stage, "[data-role=prologue-words]")
      assert has_element?(stage, "[data-role=prologue-words]", "Welcome to Thereish")
      assert has_element?(stage, "[data-role=prologue-words]", "Give")
      refute has_element?(stage, "[data-role=prologue-words]", "setting")
      assert has_element?(stage, "[data-role=prologue-skip]", "Skip")
    end

    test "\"Play the Prologue\" control present on the waiting screen after prologue ends or on a Room with a Chronicle" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      tap_for_sound(stage)

      assert has_element?(stage, "[data-role=prologue-skip]")
      stage |> element("[data-role=prologue-skip]") |> render_click()

      # Words disappear and Play the Prologue control appears on waiting screen
      refute has_element?(stage, "[data-role=prologue-words]")
      assert has_element?(stage, "[data-role=play-prologue]", "Play the Prologue")

      # Clicking Play the Prologue restarts reading
      stage |> element("[data-role=play-prologue]") |> render_click()
      assert_push_event(stage, "foley:prologue", %{path: _})
      assert has_element?(stage, "[data-role=prologue-words]")

      # On a Room with a Chronicle: opening tap does NOT play prologue, but Play the Prologue is present
      chronicle_slug = open_room()
      room = Rooms.Store.get_room(chronicle_slug)

      Thereish.Repo.insert!(%Thereish.Chronicle.Page{
        room_id: room.id,
        opened_at: DateTime.utc_now(),
        closed_at: DateTime.utc_now(),
        closed_because: "meld",
        document: %{"bookends" => ["lantern", "harbour"]},
        melded: true
      })

      {:ok, stage_c, _} = live(build_conn(), ~p"/r/#{chronicle_slug}/stage")
      tap_for_sound(stage_c)
      refute_push_event(stage_c, "foley:prologue", %{})
      refute has_element?(stage_c, "[data-role=prologue-words]")
      assert has_element?(stage_c, "[data-role=play-prologue]", "Play the Prologue")

      # And clicking Play the Prologue plays it on request
      stage_c |> element("[data-role=play-prologue]") |> render_click()
      assert_push_event(stage_c, "foley:prologue", %{})
      assert has_element?(stage_c, "[data-role=prologue-words]")
    end

    test "Skip ends it for the Room and the Room fact is set; a later open does not play it" do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      tap_for_sound(stage)

      assert has_element?(stage, "[data-role=prologue-skip]")
      stage |> element("[data-role=prologue-skip]") |> render_click()

      refute has_element?(stage, "[data-role=prologue-words]")
      assert Rooms.get_room(slug).prologue_skipped == true

      # Later open of stage does not play it from the tap
      {:ok, stage2, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      tap_for_sound(stage2)
      refute_push_event(stage2, "foley:prologue", %{})
      refute has_element?(stage2, "[data-role=prologue-words]")
    end

    test "phone-only Room shows the prologue card on the waiting screen, and skip removes it" do
      slug = open_room()
      {:ok, phone, _} = live(phone(slug))
      join(phone, "Mara")

      # Phone-only room shows the prologue card on waiting screen
      assert has_element?(phone, "[data-role=prologue-card]")
      assert has_element?(phone, "[data-role=prologue-words]", "Welcome to Thereish")
      assert has_element?(phone, "[data-role=prologue-skip]", "Skip")

      # Skip removes it and sets Room fact
      phone |> element("[data-role=prologue-skip]") |> render_click()
      refute has_element?(phone, "[data-role=prologue-card]")
      assert Rooms.get_room(slug).prologue_skipped == true

      # Stage present: phone does not show the card
      slug_with_stage = open_room()
      {:ok, _stage, _} = live(build_conn(), ~p"/r/#{slug_with_stage}/stage")
      {:ok, phone2, _} = live(phone(slug_with_stage))
      join(phone2, "Jacob")
      refute has_element?(phone2, "[data-role=prologue-card]")

      # Room with a Chronicle: phone does not show the card
      slug_with_chronicle = open_room()
      room_c = Rooms.Store.get_room(slug_with_chronicle)

      Thereish.Repo.insert!(%Thereish.Chronicle.Page{
        room_id: room_c.id,
        opened_at: DateTime.utc_now(),
        closed_at: DateTime.utc_now(),
        closed_because: "meld",
        document: %{"bookends" => ["lantern", "harbour"]},
        melded: true
      })

      {:ok, phone3, _} = live(phone(slug_with_chronicle))
      join(phone3, "Nora")
      refute has_element?(phone3, "[data-role=prologue-card]")
    end
  end

  describe "masks on the stage (ticket 17)" do
    setup do
      slug = open_room()
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")
      {:ok, mara, _} = live(phone(slug))
      {:ok, jacob, _} = live(phone(slug))

      join(mara, "Mara")
      join(jacob, "Jacob")

      %{
        slug: slug,
        stage: stage,
        mara: mara,
        jacob: jacob
      }
    end

    test "bridge marker replaces name chip with face-down card before reveal, lighting on bridge commit",
         ctx do
      play_to_bridging(ctx.mara, ctx.jacob, ctx.slug, "candlelit cathedral", "misty harbor")

      mara = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Mara"))
      jacob = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Jacob"))

      # Before reveal (attempt 1 bridging): markers are face-down cards
      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{mara.id}'][data-state=dim] [data-role=mask-face-down]"
             )

      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{jacob.id}'][data-state=dim] [data-role=mask-face-down]"
             )

      # When Mara commits bridge, Mara's marker lights
      commit(ctx.mara, "cairn")

      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{mara.id}'][data-state=lit] [data-role=mask-face-down]"
             )

      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{jacob.id}'][data-state=dim] [data-role=mask-face-down]"
             )
    end

    test "after first reveal, Mask replaces face-down card as the marker on next attempt", ctx do
      play_to_bridging(ctx.mara, ctx.jacob, ctx.slug, "candlelit cathedral", "misty harbor")

      mara = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Mara"))
      jacob = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Jacob"))

      # Complete attempt 1 with a miss to trigger first reveal
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "tallow")
      await_reveal_on(ctx.stage)

      # Advance to attempt 2
      ctx.mara |> element("[data-role=again]") |> render_click()
      assert has_element?(ctx.stage, "[data-role=attempt]", "Attempt 2 of 5")

      # On attempt 2 bridging (after first reveal), markers are now the Masks, dim until committed
      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{mara.id}'][data-state=dim] [data-role=seat-mask]"
             )

      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{jacob.id}'][data-state=dim] [data-role=seat-mask]"
             )

      # Committing bridge on attempt 2 lights the Mask marker
      commit(ctx.mara, "candle")

      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{mara.id}'][data-state=lit] [data-role=seat-mask]"
             )
    end

    test "seat with no Mask shows the colour dot as its marker", ctx do
      fake_config = Keyword.get(Application.get_env(:thereish, :steward, []), :fake, [])

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.merge(fake_config, draw_mode: :refused)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      play_to_bridging(ctx.mara, ctx.jacob, ctx.slug, "candlelit cathedral", "misty harbor")

      mara = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Mara"))

      # Complete attempt 1 to trigger first reveal
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "tallow")
      await_reveal_on(ctx.stage)

      # Advance to attempt 2
      ctx.mara |> element("[data-role=again]") |> render_click()
      assert has_element?(ctx.stage, "[data-role=attempt]", "Attempt 2 of 5")

      # Because draw was refused, seats have no mask (:dot), so marker is colour dot
      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{mara.id}'][data-state=dim] [data-role=seat-colour-dot]"
             )

      # Lighting works on the colour dot marker
      commit(ctx.mara, "candle")

      assert has_element?(
               ctx.stage,
               "[data-role=bridge-marker][data-seat='#{mara.id}'][data-state=lit] [data-role=seat-colour-dot]"
             )
    end

    test "Stage shows face-down cards as Gives land and flips them at the first reveal", ctx do
      # Room is in giving phase
      assert has_element?(ctx.stage, "[data-role=giving-stage]")

      mara = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Mara"))
      jacob = Enum.find(Rooms.snapshot(ctx.slug, nil).seats, &(&1.name == "Jacob"))

      # Initially no gives have landed, so no face-down cards on stage
      refute has_element?(ctx.stage, "[data-role=mask-face-down]")

      # Mara gives a setting -> Mara's face-down card appears on the Stage
      give_setting(ctx.mara, "candlelit cathedral")

      eventually(fn ->
        has_element?(ctx.stage, "[data-role=mask-face-down][data-seat='#{mara.id}']")
      end)

      refute has_element?(ctx.stage, "[data-role=mask-face-down][data-seat='#{jacob.id}']")

      # Jacob gives a setting -> both face-down cards appear on the Stage
      give_setting(ctx.jacob, "misty harbor")

      eventually(fn ->
        has_element?(ctx.stage, "[data-role=mask-face-down][data-seat='#{jacob.id}']")
      end)

      assert has_element?(ctx.stage, "[data-role=mask-face-down][data-seat='#{mara.id}']")

      # Progress to bridging: stage still shows face-down cards (in bridge-markers)
      await_phase(ctx.slug, :bridging)
      assert has_element?(ctx.stage, "[data-role=bridge-marker] [data-role=mask-face-down]")

      # Both seats commit bridges and reveal arrives (the first reveal)
      commit(ctx.mara, "cairn")
      commit(ctx.jacob, "tallow")
      await_reveal_on(ctx.stage)

      # At the first reveal, every mask turns over together:
      # face-down cards are gone and replaced by revealed Masks
      refute has_element?(ctx.stage, "[data-role=mask-face-down]")
      assert has_element?(ctx.stage, "[data-role=stage-masks]")

      assert has_element?(
               ctx.stage,
               "[data-role=stage-mask][data-seat='#{mara.id}'] [data-role=seat-mask]"
             )

      assert has_element?(
               ctx.stage,
               "[data-role=stage-mask][data-seat='#{jacob.id}'] [data-role=seat-mask]"
             )
    end
  end

  describe "eight-Seat Rooms (ticket 01, #132)" do
    @eight ~w(Mara Jacob Ada Ida Ola Ora Ivy Ned)
    @eight_bridges ~w(cairn beacon wharf signal torch lamp stone flare)

    test "phones and the Stage play a full Page with eight distinguishable Seats" do
      slug = open_room(seat_limit: 8)
      {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

      phones =
        for name <- @eight do
          {:ok, view, _} = live(phone(slug))
          join(view, name)
          view
        end

      {:ok, ninth, _} = live(phone(slug))
      assert join(ninth, "Ninth") =~ "Every seat is taken"

      snapshot = Rooms.snapshot(slug, nil)
      assert length(snapshot.seats) == 8

      for {phone_view, name} <- Enum.zip(phones, @eight) do
        assert has_element?(phone_view, "[data-role=roster] [data-seat]", name)
        assert has_element?(phone_view, "[data-role=setting-form]")
      end

      for name <- @eight do
        assert has_element?(stage, "[data-role=roster] [data-seat]", name)
      end

      for {phone_view, name} <- Enum.zip(phones, @eight) do
        give_setting(phone_view, "setting #{name}")
      end

      await_phase(slug, :bridging)

      snapshot = Rooms.snapshot(slug, nil)
      colours = Enum.map(snapshot.seats, & &1.colour)
      assert length(Enum.uniq(colours)) == 8

      for seat <- snapshot.seats do
        assert has_element?(stage, "[data-role=bridge-marker][data-seat='#{seat.id}']", seat.name)
      end

      for phone_view <- phones do
        eventually(fn -> has_element?(phone_view, "[data-role=bridge-form]") end)
        assert has_element?(phone_view, "[data-role=bookend-chip]", "lantern")
        assert has_element?(phone_view, "[data-role=bookend-chip]", "hearth")
      end

      assert has_element?(stage, "[data-role=bookend-chip]", "lantern")
      assert has_element?(stage, "[data-role=bookend-chip]", "hearth")

      for {phone_view, bridge} <- Enum.zip(phones, @eight_bridges) do
        commit(phone_view, bridge)
      end

      await_reveal(slug)
      await_reveal_on(stage)

      for bridge <- @eight_bridges do
        assert has_element?(stage, "[data-bridge]", bridge)
      end

      refute has_element?(stage, "[data-role=pair]")
      assert has_element?(stage, "[data-role=closeness]")
      assert has_element?(stage, "[data-role=quip]")

      for {phone_view, name} <- Enum.zip(phones, @eight) do
        eventually(fn -> has_element?(phone_view, "[data-role=reveal]") end)
        assert has_element?(phone_view, "[data-seat]", name)
        refute has_element?(phone_view, "[data-role=pair]")
      end

      hd(phones) |> element("[data-role=again]") |> render_click()
      await_phase(slug, :bridging)

      for phone_view <- phones do
        eventually(fn -> has_element?(phone_view, "[data-role=bridge-form]") end)
      end

      Enum.each(phones, &commit(&1, "peak"))
      await_reveal(slug)
      await_phase(slug, :closed)

      for phone_view <- phones do
        eventually(fn -> has_element?(phone_view, "[data-role=one-more]") end)
      end

      refute has_element?(stage, "[data-role=pair]")
    end
  end
end
