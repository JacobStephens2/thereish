defmodule ThereishWeb.ChronicleLiveTest do
  @moduledoc """
  The Chronicle as a book read on a phone (ticket 08).
  """
  use ThereishWeb.ConnCase, async: false

  import Thereish.RoomFixtures
  import Phoenix.LiveViewTest

  alias Thereish.Chronicle
  alias Thereish.Rooms
  alias Thereish.Repo
  alias Thereish.Rooms.Room

  setup do
    slug = open_room()
    {:ok, mara} = Rooms.join(slug, "Mara", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    %{slug: slug, mara: mara, jacob: jacob}
  end

  defp play(ctx, mara_bridge, jacob_bridge) do
    if Rooms.snapshot(ctx.slug, nil).phase == :giving do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)
    end

    :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, mara_bridge)
    :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, jacob_bridge)

    await_reveal(ctx.slug)
  end

  # The Scribe writes from a task the Room does not wait for, so a page that
  # wants the paragraph on screen waits for it the way the phone does.
  defp await_recap(slug) do
    eventually(
      fn -> Chronicle.recaps(Repo.get_by!(Room, slug: slug).id) != [] end,
      "the Scribe never wrote a recap for #{slug}"
    )
  end

  describe "what the Scribe wrote" do
    test "is on the Page it was written about", %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")
      await_recap(slug)

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=recap]")
      assert render(element(view, "[data-role=recap-prose]")) =~ "cairn"
    end

    test "reaches back to an earlier Page where the Chronicle has one",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")
      await_recap(slug)
      :ok = Rooms.next_page(slug, ctx.mara.id)
      play(ctx, "mirage", "mirages")
      await_scribe()

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      # The newest Page is first in the book, and it is the one with something
      # behind it to remember.
      assert render(element(view, "[data-role=recap-callback]")) =~ "been here before"
    end

    test "is nowhere at all on a Page the Scribe could not write",
         %{conn: conn, slug: slug} = ctx do
      steward(recap_mode: :unavailable)
      play(ctx, "cairn", "cairns")
      await_scribe()

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=chronicle-page]")
      refute has_element?(view, "[data-role=recap]")
    end

    test "is the players' to rewrite, like everything else in the book",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")
      await_recap(slug)

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")
      [page] = Chronicle.book(slug)

      view
      |> element(~s([data-role=open-correction][data-page-id="#{page.id}"]))
      |> render_click()

      view
      |> form(~s(form[data-role=correction-form]), %{
        "correction" => %{
          "attempt_number" => "",
          "target" => "recap",
          "original_value" => page.recap.recap,
          "corrected_value" => "We both wrote cairn, near enough, and went to bed.",
          "note" => "The Scribe missed the point"
        }
      })
      |> render_submit()

      assert render(element(view, "[data-role=recap-prose]")) =~
               "We both wrote cairn, near enough"

      assert render(view) =~ "The Scribe missed the point"
    end

    test "arrives on a book that is already open", %{conn: conn, slug: slug} = ctx do
      # The paragraph lands after the reveal, so a phone left on the Chronicle
      # gets it without being asked to look again.
      steward(recap_delay_ms: 150)

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      play(ctx, "cairn", "cairns")
      await_recap(slug)

      assert eventually(
               fn -> render(view) =~ "cairn" and has_element?(view, "[data-role=recap]") end,
               "the recap never reached a book that was already open"
             )
    end
  end

  describe "the Chronicle book page" do
    test "shows empty state when no pages have closed", %{conn: conn, slug: slug} do
      {:ok, view, html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert html =~ "The Chronicle"
      assert html =~ "empty" or has_element?(view, "[data-role=empty-chronicle]")
    end

    test "a quiet credit names who made Thereish", %{conn: conn, slug: slug} do
      {:ok, view, _} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(
               view,
               "[data-role=made-by] a[href='https://stephens.page']",
               "Made by Jacob Stephens"
             )
    end

    test "reads pages in reverse chronological order with bookends, attempts, bridges, and verdicts",
         %{conn: conn, slug: slug} = ctx do
      # Play first page: melded
      play(ctx, "cairn", "cairns")

      # Play second page with different bookends: two attempts
      attempt_cap(2)
      steward(author_bookends: ["cactus", "dune"])
      :ok = Rooms.next_page(slug, ctx.mara.id)
      play(ctx, "mirage", "oasis")
      :ok = Rooms.next_attempt(slug, ctx.mara.id)
      play(ctx, "sand", "dust")

      {:ok, view, html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert html =~ "The Chronicle"

      # Both pages rendered
      assert has_element?(view, "[data-role=chronicle-page]", "lantern")

      assert has_element?(view, "[data-role=chronicle-page]", "dune") or
               has_element?(view, "[data-role=chronicle-page]", "mirage")

      # Reverse chronological order: newest page (second page) appears before first page in HTML
      rendered_html = render(view)
      assert rendered_html =~ "lantern"
      assert rendered_html =~ "harbour"
      assert rendered_html =~ "Mara"
      assert rendered_html =~ "cairn"
      assert rendered_html =~ "Jacob"
      assert rendered_html =~ "cairns"
      assert rendered_html =~ "80"

      {p2_pos, _} = :binary.match(rendered_html, "cactus")
      {p1_pos, _} = :binary.match(rendered_html, "lantern")
      assert p2_pos < p1_pos

      # The Code opens it in whatever case it was typed in.
      {:ok, _shouted, shouted_html} = live(conn, "/r/#{String.upcase(slug)}/chronicle")
      assert shouted_html =~ "The Chronicle"
    end

    test "renders an Attempt that holds two Verdicts, each covering two Seats", %{conn: conn} do
      slug = open_room(seat_limit: 4)
      room = Repo.get_by!(Room, slug: slug)

      seats =
        for name <- ["Mara", "Jacob", "Ada", "Sam"] do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          seat
        end

      [mara, jacob, ada, sam] = seats

      entry = %{
        page: %{
          id: "two-verdicts-live",
          chapter: "harbour",
          bookends: ["lantern", "harbour"],
          why_these: "An earlier night graded the table as two pairs."
        },
        closed_because: :attempts,
        melded?: false,
        closeness: 85,
        attempts: [
          %{
            number: 1,
            bookends: ["lantern", "harbour"],
            closeness: 85,
            melded?: false,
            bridges: [
              %{seat_id: mara.id, bridge: "beacon"},
              %{seat_id: jacob.id, bridge: "cairn"},
              %{seat_id: ada.id, bridge: "lamp"},
              %{seat_id: sam.id, bridge: "seagull"}
            ],
            verdicts: [
              %{
                seat_ids: [mara.id, jacob.id],
                bridges: ["beacon", "cairn"],
                graded?: true,
                closeness: 85,
                band: :almost,
                reasoning: "Close on the shore.",
                quip: "A cairn for the beacon.",
                furthest: ["beacon", "cairn"],
                meta: %{model: "fake", prompt_version: "assay-2", latency_ms: 40, cost_usd: 0.0}
              },
              %{
                seat_ids: [ada.id, sam.id],
                bridges: ["lamp", "seagull"],
                graded?: true,
                closeness: 27,
                band: :miss,
                reasoning: "The seagull is having its own evening.",
                quip: "One of you brought a bird.",
                furthest: ["lamp", "seagull"],
                meta: %{model: "fake", prompt_version: "assay-2", latency_ms: 40, cost_usd: 0.0}
              }
            ]
          }
        ]
      }

      assert {:ok, _page} = Chronicle.write(room.id, entry, DateTime.utc_now())

      {:ok, view, html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert html =~ "lantern"
      assert html =~ "beacon"
      assert html =~ "cairn"
      assert html =~ "lamp"
      assert html =~ "seagull"
      assert has_element?(view, "[data-role=attempt]")
      assert html =~ "85"
      assert html =~ "27"
      assert html =~ "Close on the shore."
      assert html =~ "The seagull is having its own evening."
    end

    test "shows overrules and player corrections, and allows recording an edit",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")

      room = Repo.get_by!(Room, slug: slug)
      [page] = Chronicle.pages(room.id)

      # Record an overrule
      {:ok, _overrule} =
        Chronicle.record_overrule(room.id, %{
          page_id: page.id,
          attempt_number: 1,
          proposer_seat_id: ctx.mara.id,
          bookends: ["lantern", "harbour"],
          bridges: ["cairn", "cairns"],
          machine_closeness: 80,
          machine_reasoning: "Share 4 letters",
          machine_quip: "Quip",
          couple_closeness: 100,
          couple_reasoning: "Deep meld in our hearts"
        })

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      # Overrule is shown
      assert has_element?(view, "[data-role=overrule]")
      assert render(view) =~ "Deep meld in our hearts"

      # Open correction form
      assert has_element?(view, ~s([data-role=open-correction][data-page-id="#{page.id}"]))

      view
      |> element(~s([data-role=open-correction][data-page-id="#{page.id}"]))
      |> render_click()

      assert has_element?(view, ~s(form[data-role=correction-form]))

      # Submit correction
      view
      |> form(~s(form[data-role=correction-form]), %{
        "correction" => %{
          "attempt_number" => "1",
          "target" => "bridge",
          "original_value" => "cairns",
          "corrected_value" => "cairn",
          "note" => "Fixed spelling on phone"
        }
      })
      |> render_submit()

      # Form is closed and correction is visible
      refute has_element?(view, ~s(form[data-role=correction-form]))
      rendered = render(view)
      assert rendered =~ "Fixed spelling on phone"
      assert rendered =~ "cairn"
      assert rendered =~ "(cairns)"

      # Database verifies it appended rather than mutating
      assert [correction] = Chronicle.corrections(room.id)
      assert correction.page_id == page.id
      assert correction.attempt_number == 1
      assert correction.corrected_value == "cairn"
      assert correction.original_value == "cairns"
    end

    test "shows fairness taps alongside the page and attempt they judge",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")

      :ok = Rooms.record_fairness_tap(slug, ctx.mara.id, :fair)
      :ok = Rooms.record_fairness_tap(slug, ctx.jacob.id, :too_harsh)

      # Advance to close page
      :ok = Rooms.next_page(slug, ctx.mara.id)

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=fairness-taps]")
      rendered = render(view)
      assert rendered =~ "Fairness:"
      assert rendered =~ "Mara: fair"
      assert rendered =~ "Jacob: too harsh"
    end

    test "book view displays gives, every bridge, the verdict with reasoning, and the carried words",
         %{conn: conn, slug: slug} = ctx do
      # Play attempt 1 which misses and carries furthest words
      play(ctx, "cairn", "beacon")
      # Advance and play attempt 2 which melds
      :ok = Rooms.next_attempt(slug, ctx.mara.id)
      play(ctx, "wharf", "wharf")

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=chronicle-page]")
      assert has_element?(view, "[data-role=give-tag]", "Give (Mara): setting one")
      assert has_element?(view, "[data-role=give-tag]", "Give (Jacob): setting two")

      # Attempt 1 shows carried words
      assert has_element?(
               view,
               ~s([data-role=attempt][data-attempt-number="1"] [data-role=carried-words])
             )

      carried_text =
        element(view, ~s([data-role=attempt][data-attempt-number="1"] [data-role=carried-words]))
        |> render()

      assert carried_text =~ "Carried:"
      assert carried_text =~ "cairn and beacon"

      assert has_element?(view, "[data-role=page-rule]", "Full table")
      assert has_element?(view, "[data-role=bookend-give]", "lantern from Mara's setting one")
      assert has_element?(view, "[data-role=bookend-give]", "harbour from Jacob's setting two")
    end

    test "book view displays each Seat's Mask on the Page", %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=chronicle-page]")
      assert has_element?(view, "[data-role=page-mask]")
    end

    test "a Chronicle Mask opens in an enlarged view and closes with a labelled control",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=enlarge-mask]")
      refute has_element?(view, "[data-role=enlarged-mask]")

      view
      |> element("[data-role=give-tag] [data-role=enlarge-mask][data-seat='#{ctx.mara.id}']")
      |> render_click()

      assert has_element?(view, "[data-role=enlarged-mask]")
      assert has_element?(view, "[data-role=enlarged-mask-image]")
      assert has_element?(view, "[data-role=close-enlarged-mask][aria-label='Close']")

      view |> element("[data-role=close-enlarged-mask]") |> render_click()
      refute has_element?(view, "[data-role=enlarged-mask]")
    end

    test "an older retained Mask enlarges and closes the same way",
         %{conn: conn, slug: slug} = ctx do
      room = Repo.get_by!(Room, slug: slug)
      now = DateTime.utc_now()

      {:ok, _page} =
        Chronicle.write(
          room.id,
          %{
            document: %{"bookends" => ["desert", "oasis"]},
            author_meta: %{model: "gemini-3.8-flash", cost_usd: 0.0002},
            gives: [
              %{seat_id: ctx.mara.id, text: "cactus"},
              %{seat_id: ctx.jacob.id, text: "dune"}
            ],
            masks: %{
              ctx.mara.id => %{url: "/media/masks/mask-historical.png"},
              ctx.jacob.id => %{url: "/media/masks/mask-jacob-old.png"}
            },
            closed_because: :meld,
            melded?: true,
            closeness: 90,
            attempts: []
          },
          now
        )

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(
               view,
               "[data-role=give-tag] [data-role=enlarge-mask][data-seat='#{ctx.mara.id}']"
             )

      view
      |> element("[data-role=give-tag] [data-role=enlarge-mask][data-seat='#{ctx.mara.id}']")
      |> render_click()

      assert has_element?(view, "[data-role=enlarged-mask]")

      assert has_element?(
               view,
               "[data-role=enlarged-mask-image][src='/media/masks/mask-historical.png']"
             )

      view |> element("[data-role=close-enlarged-mask]") |> render_click()
      refute has_element?(view, "[data-role=enlarged-mask]")
    end
  end

  describe "operator information stays off the ordinary Chronicle (ticket 09)" do
    test "has no export links, experiment card, or spend foot",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")
      await_recap(slug)

      {:ok, view, html} = live(conn, ~p"/r/#{slug}/chronicle")

      refute html =~ "Export Markdown"
      refute html =~ "Export Calibration"
      refute has_element?(view, "[data-role=experiment-card]")
      refute has_element?(view, "[data-role=chronicle-spend]")
      refute has_element?(view, "[data-role=in-play-line]")
    end

    test "omits in-play sentence that used to sit at the Chronicle foot",
         %{conn: conn, slug: slug} = ctx do
      :ok = Rooms.give(slug, ctx.mara.id, "lantern")
      :ok = Rooms.give(slug, ctx.jacob.id, "harbour")
      await_phase(slug, :bridging)

      {:ok, view, html} = live(conn, ~p"/r/#{slug}/chronicle")
      refute html =~ "1 Page in play, not yet counted"
      refute has_element?(view, "[data-role=in-play-line]")

      # Melding closes the page
      :ok = Rooms.commit_bridge(slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(slug, ctx.jacob.id, "cairn")
      await_reveal(slug)

      eventually(
        fn ->
          Rooms.snapshot(slug, nil).phase == :closed
        end,
        "room never closed"
      )

      {:ok, view2, html2} = live(conn, ~p"/r/#{slug}/chronicle")
      refute html2 =~ "not yet counted"
      refute has_element?(view2, "[data-role=in-play-line]")
    end
  end

  describe "The Chronicle plays the Track (ticket 05)" do
    test "shows Track title and audio player when page has a music path, and shows no music line otherwise",
         %{conn: conn, slug: slug} = ctx do
      room = Repo.get_by!(Room, slug: slug)
      now = DateTime.utc_now()

      # Page 1: Closed Page with music_meta carrying path and title
      entry1 = %{
        document: %{"bookends" => ["lantern", "harbour"]},
        author_meta: %{model: "gemini-3.8-flash"},
        music_meta: %{
          provider: "mureka",
          path: "/media/tracks/harbour-lights.mp3",
          title: "Harbour Lights"
        },
        closed_because: :meld,
        melded?: true,
        closeness: 95,
        attempts: [
          %{
            number: 1,
            bookends: ["lantern", "harbour"],
            closeness: 95,
            melded?: true,
            bridges: [
              %{seat_id: ctx.mara.id, bridge: "lighthouse"},
              %{seat_id: ctx.jacob.id, bridge: "lighthouse"}
            ],
            verdicts: []
          }
        ]
      }

      assert {:ok, p1} = Chronicle.write(room.id, entry1, now)

      # Page 2: Page with a failed score (music_meta has failure, no path)
      entry2 = %{
        document: %{"bookends" => ["desert", "oasis"]},
        author_meta: %{model: "gemini-3.8-flash"},
        music_meta: %{provider: "mureka", failure: :timed_out, cost_usd: 0.0},
        closed_because: :meld,
        melded?: true,
        closeness: 90,
        attempts: [
          %{
            number: 1,
            bookends: ["desert", "oasis"],
            closeness: 90,
            melded?: true,
            bridges: [
              %{seat_id: ctx.mara.id, bridge: "water"},
              %{seat_id: ctx.jacob.id, bridge: "water"}
            ],
            verdicts: []
          }
        ]
      }

      assert {:ok, p2} = Chronicle.write(room.id, entry2, DateTime.add(now, 60, :second))

      # Page 3: Music under Off (music_meta is nil)
      entry3 = %{
        document: %{"bookends" => ["mountain", "valley"]},
        author_meta: %{model: "gemini-3.8-flash"},
        music_meta: nil,
        closed_because: :meld,
        melded?: true,
        closeness: 88,
        attempts: [
          %{
            number: 1,
            bookends: ["mountain", "valley"],
            closeness: 88,
            melded?: true,
            bridges: [
              %{seat_id: ctx.mara.id, bridge: "ridge"},
              %{seat_id: ctx.jacob.id, bridge: "ridge"}
            ],
            verdicts: []
          }
        ]
      }

      assert {:ok, p3} = Chronicle.write(room.id, entry3, DateTime.add(now, 120, :second))

      # Page 4: Legacy page without path (music_meta has provider/model/cost but no path)
      entry4 = %{
        document: %{"bookends" => ["frost", "glacier"]},
        author_meta: %{model: "gemini-3.8-flash"},
        music_meta: %{provider: "mureka", model: "mureka-v1", cost_usd: 0.04},
        closed_because: :meld,
        melded?: true,
        closeness: 85,
        attempts: [
          %{
            number: 1,
            bookends: ["frost", "glacier"],
            closeness: 85,
            melded?: true,
            bridges: [
              %{seat_id: ctx.mara.id, bridge: "ice"},
              %{seat_id: ctx.jacob.id, bridge: "ice"}
            ],
            verdicts: []
          }
        ]
      }

      assert {:ok, p4} = Chronicle.write(room.id, entry4, DateTime.add(now, 180, :second))

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      # Page 1 shows its title and player pointing at /media/tracks/...
      assert has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{p1.id}"] [data-role=track])
             )

      assert has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{p1.id}"] audio[src="/media/tracks/harbour-lights.mp3"])
             )

      assert render(
               element(
                 view,
                 ~s([data-role=chronicle-page][data-page-id="#{p1.id}"] [data-role=track])
               )
             ) =~ "Harbour Lights"

      # Pages without a path show no music line at all rather than an empty player
      refute has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{p2.id}"] [data-role=track])
             )

      refute has_element?(view, ~s([data-role=chronicle-page][data-page-id="#{p2.id}"] audio))

      refute has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{p3.id}"] [data-role=track])
             )

      refute has_element?(view, ~s([data-role=chronicle-page][data-page-id="#{p3.id}"] audio))

      refute has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{p4.id}"] [data-role=track])
             )

      refute has_element?(view, ~s([data-role=chronicle-page][data-page-id="#{p4.id}"] audio))
    end

    test "a completed Page's Chronicle still plays its Vamp and Track after a fresh read",
         %{conn: conn} = ctx do
      steward(vamp_delay_ms: 0, music_delay_ms: 80)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "frozen lake")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "northern lights")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.mara.id)
        not is_nil(view[:vamp]) and is_nil(view[:track])
      end)

      vamp_path = Rooms.snapshot(ctx.slug, ctx.mara.id).vamp.path

      eventually(fn ->
        not is_nil(Rooms.snapshot(ctx.slug, ctx.mara.id)[:track])
      end)

      track_path = Rooms.snapshot(ctx.slug, ctx.mara.id).track.path

      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, "cairn")
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, "cairn")
      await_reveal(ctx.slug)
      await_phase(ctx.slug, :closed)

      eventually(fn ->
        pages = Chronicle.page_views(ctx.slug)

        pages != [] and Chronicle.page_vamp(hd(pages)) != nil and
          Chronicle.page_track(hd(pages)) != nil
      end)

      [page] = Chronicle.page_views(ctx.slug)
      {:ok, view, _html} = live(conn, ~p"/r/#{ctx.slug}/chronicle")

      assert has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{page.id}"] [data-role=vamp] audio[src="#{vamp_path}"])
             )

      assert has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{page.id}"] [data-role=track] audio[src="#{track_path}"])
             )

      assert render(
               element(
                 view,
                 ~s([data-role=chronicle-page][data-page-id="#{page.id}"] [data-role=vamp])
               )
             ) =~ "short"
    end

    test "shows a Vamp player labelled as the short piece beside the Track, and none when absent",
         %{conn: conn, slug: slug} = ctx do
      room = Repo.get_by!(Room, slug: slug)
      now = DateTime.utc_now()

      entry1 = %{
        document: %{"bookends" => ["lantern", "harbour"]},
        author_meta: %{model: "gemini-3.8-flash"},
        music_meta: %{
          provider: "mureka",
          path: "/media/tracks/harbour-lights.mp3",
          title: "Harbour Lights"
        },
        vamp_meta: %{
          path: "/media/vamps/harbour-vamp.mp3",
          duration: 30,
          loop: true
        },
        closed_because: :meld,
        melded?: true,
        closeness: 95,
        attempts: [
          %{
            number: 1,
            bookends: ["lantern", "harbour"],
            closeness: 95,
            melded?: true,
            bridges: [
              %{seat_id: ctx.mara.id, bridge: "lighthouse"},
              %{seat_id: ctx.jacob.id, bridge: "lighthouse"}
            ],
            verdicts: []
          }
        ]
      }

      assert {:ok, p1} = Chronicle.write(room.id, entry1, now)

      entry2 = %{
        document: %{"bookends" => ["desert", "oasis"]},
        author_meta: %{model: "gemini-3.8-flash"},
        music_meta: %{
          provider: "mureka",
          path: "/media/tracks/oasis.mp3",
          title: "Oasis"
        },
        closed_because: :meld,
        melded?: true,
        closeness: 90,
        attempts: [
          %{
            number: 1,
            bookends: ["desert", "oasis"],
            closeness: 90,
            melded?: true,
            bridges: [
              %{seat_id: ctx.mara.id, bridge: "water"},
              %{seat_id: ctx.jacob.id, bridge: "water"}
            ],
            verdicts: []
          }
        ]
      }

      assert {:ok, p2} = Chronicle.write(room.id, entry2, DateTime.add(now, 60, :second))

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{p1.id}"] [data-role=vamp])
             )

      assert has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{p1.id}"] [data-role=vamp] audio[src="/media/vamps/harbour-vamp.mp3"][loop])
             )

      vamp_html =
        render(
          element(
            view,
            ~s([data-role=chronicle-page][data-page-id="#{p1.id}"] [data-role=vamp])
          )
        )

      assert vamp_html =~ "Vamp"
      assert vamp_html =~ "short"

      assert has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{p1.id}"] [data-role=track] audio[src="/media/tracks/harbour-lights.mp3"])
             )

      refute has_element?(
               view,
               ~s([data-role=chronicle-page][data-page-id="#{p2.id}"] [data-role=vamp])
             )
    end

    test "Thereish wordmark links home to front page on the Chronicle" do
      slug = open_room()
      {:ok, view, _html} = live(build_conn(), ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "header a[href='/']", "Thereish")
    end
  end
end
