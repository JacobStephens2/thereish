defmodule ThereishWeb.ChronicleLiveTest do
  @moduledoc """
  The Chronicle as a book read on a phone (ticket 08).
  """
  use ThereishWeb.ConnCase, async: false

  import Thereish.EntryFixtures
  import Thereish.RoomFixtures
  import Phoenix.LiveViewTest

  alias Thereish.Chronicle
  alias Thereish.Foley.Track
  alias Thereish.Foley.Vamp
  alias Thereish.Mask
  alias Thereish.Rooms
  alias Thereish.Repo
  alias Thereish.Rooms.Room

  setup do
    slug = open_room()
    {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    %{slug: slug, melissa: melissa, jacob: jacob}
  end

  defp play(ctx, melissa_bridge, jacob_bridge) do
    if Rooms.snapshot(ctx.slug, nil).phase == :giving do
      :ok = Rooms.give(ctx.slug, ctx.melissa.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)
    end

    :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, melissa_bridge)
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
      :ok = Rooms.next_page(slug, ctx.melissa.id)
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

    test "a historical recap correction still reads over the Scribe, without a correction form",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")
      await_recap(slug)
      [page] = Chronicle.book(slug)
      room = Repo.get_by!(Room, slug: slug)

      {:ok, _} =
        %Thereish.Chronicle.Correction{}
        |> Thereish.Chronicle.Correction.changeset(%{
          room_id: room.id,
          page_id: page.id,
          seat_id: ctx.melissa.id,
          target: "recap",
          original_value: page.recap.recap,
          corrected_value: "We both wrote cairn, near enough, and went to bed.",
          note: "The Scribe missed the point"
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert render(element(view, "[data-role=recap-prose]")) =~
               "We both wrote cairn, near enough"

      assert render(view) =~ "The Scribe missed the point"
      refute has_element?(view, "[data-role=open-correction]")
      refute has_element?(view, "[data-role=correction-form]")
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
      :ok = Rooms.next_page(slug, ctx.melissa.id)
      play(ctx, "mirage", "oasis")
      :ok = Rooms.next_attempt(slug, ctx.melissa.id)
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
      assert rendered_html =~ "Melissa"
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
        for name <- ["Melissa", "Jacob", "Ada", "Sam"] do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          seat
        end

      [melissa, jacob, ada, sam] = seats

      entry =
        entry(%{
          page: %{
            id: "two-verdicts-live",
            chapter: "harbour",
            bookends: ["lantern", "harbour"],
            why_these: "An earlier night graded the table as two pairs."
          },
          closed_because: :attempts_spent,
          melded?: false,
          closeness: 85,
          attempts: [
            %{
              number: 1,
              bookends: ["lantern", "harbour"],
              closeness: 85,
              melded?: false,
              bridges: [
                %{seat_id: melissa.id, bridge: "beacon"},
                %{seat_id: jacob.id, bridge: "cairn"},
                %{seat_id: ada.id, bridge: "lamp"},
                %{seat_id: sam.id, bridge: "seagull"}
              ],
              verdicts: [
                %{
                  seat_ids: [melissa.id, jacob.id],
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
        })

      assert {:ok, _page} = Chronicle.write(room.id, entry)

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

    test "shows overrules and historical corrections without a correction form",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")

      room = Repo.get_by!(Room, slug: slug)
      [page] = Chronicle.pages(room.id)

      {:ok, _overrule} =
        Chronicle.record_overrule(room.id, %{
          page_id: page.id,
          attempt_number: 1,
          proposer_seat_id: ctx.melissa.id,
          bookends: ["lantern", "harbour"],
          bridges: ["cairn", "cairns"],
          machine_closeness: 80,
          machine_reasoning: "Share 4 letters",
          machine_quip: "Quip",
          couple_closeness: 100,
          couple_reasoning: "Deep meld in our hearts"
        })

      {:ok, _} =
        %Thereish.Chronicle.Correction{}
        |> Thereish.Chronicle.Correction.changeset(%{
          room_id: room.id,
          page_id: page.id,
          seat_id: ctx.jacob.id,
          attempt_number: 1,
          target: "bridge",
          original_value: "cairns",
          corrected_value: "cairn",
          note: "Fixed spelling on phone"
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=overrule]")
      assert render(view) =~ "Deep meld in our hearts"
      assert has_element?(view, "[data-role=corrections]")
      rendered = render(view)
      assert rendered =~ "Fixed spelling on phone"
      assert rendered =~ "cairn"
      assert rendered =~ "(cairns)"
      refute has_element?(view, "[data-role=open-correction]")
      refute has_element?(view, "[data-role=correction-form]")
    end

    test "shows fairness taps alongside the page and attempt they judge",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairns")

      :ok = Rooms.record_fairness_tap(slug, ctx.melissa.id, :fair)
      :ok = Rooms.record_fairness_tap(slug, ctx.jacob.id, :too_harsh)

      # Advance to close page
      :ok = Rooms.next_page(slug, ctx.melissa.id)

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=fairness-taps]")
      rendered = render(view)
      assert rendered =~ "Fairness:"
      assert rendered =~ "Melissa: fair"
      assert rendered =~ "Jacob: too harsh"
    end

    test "book view displays gives, every bridge, the verdict with reasoning, and the carried words",
         %{conn: conn, slug: slug} = ctx do
      # Play attempt 1 which misses and carries furthest words
      play(ctx, "cairn", "beacon")
      # Advance and play attempt 2 which melds
      :ok = Rooms.next_attempt(slug, ctx.melissa.id)
      play(ctx, "wharf", "wharf")

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=chronicle-page]")
      assert has_element?(view, "[data-role=give-tag]", "Give (Melissa): setting one")
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
      assert has_element?(view, "[data-role=bookend-give]", "lantern from Melissa's setting one")
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
      |> element("[data-role=give-tag] [data-role=enlarge-mask][data-seat='#{ctx.melissa.id}']")
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
          entry(%{
            opened_at: now,
            page: %{bookends: ["desert", "oasis"]},
            author_meta: %{model: "gemini-3.8-flash", cost_usd: 0.0002},
            gives: [
              %{seat_id: ctx.melissa.id, text: "cactus"},
              %{seat_id: ctx.jacob.id, text: "dune"}
            ],
            masks: %{
              ctx.melissa.id => %Mask{url: "/media/masks/mask-historical.png", meta: %{}},
              ctx.jacob.id => %Mask{url: "/media/masks/mask-jacob-old.png", meta: %{}}
            },
            closed_because: :meld,
            melded?: true,
            closeness: 90,
            attempts: []
          })
        )

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(
               view,
               "[data-role=give-tag] [data-role=enlarge-mask][data-seat='#{ctx.melissa.id}']"
             )

      view
      |> element("[data-role=give-tag] [data-role=enlarge-mask][data-seat='#{ctx.melissa.id}']")
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
      :ok = Rooms.give(slug, ctx.melissa.id, "lantern")
      :ok = Rooms.give(slug, ctx.jacob.id, "harbour")
      await_phase(slug, :bridging)

      {:ok, view, html} = live(conn, ~p"/r/#{slug}/chronicle")
      refute html =~ "1 Page in play, not yet counted"
      refute has_element?(view, "[data-role=in-play-line]")

      # Melding closes the page
      :ok = Rooms.commit_bridge(slug, ctx.melissa.id, "cairn")
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

      # Page 1: Closed Page with a titled Track
      entry1 =
        entry(%{
          opened_at: now,
          page: %{bookends: ["lantern", "harbour"]},
          author_meta: %{model: "gemini-3.8-flash"},
          music_meta: %Track{
            path: "/media/tracks/harbour-lights.mp3",
            title: "Harbour Lights",
            meta: %{"provider" => "mureka"}
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
                %{seat_id: ctx.melissa.id, bridge: "lighthouse"},
                %{seat_id: ctx.jacob.id, bridge: "lighthouse"}
              ],
              verdicts: []
            }
          ]
        })

      assert {:ok, p1} = Chronicle.write(room.id, entry1)

      # Page 2: Page with a failed Track, with no path
      entry2 =
        entry(%{
          opened_at: DateTime.add(now, 60, :second),
          page: %{bookends: ["desert", "oasis"]},
          author_meta: %{model: "gemini-3.8-flash"},
          music_meta: %Track{
            failure: "timed_out",
            meta: %{"provider" => "mureka", "cost_usd" => 0.0}
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
                %{seat_id: ctx.melissa.id, bridge: "water"},
                %{seat_id: ctx.jacob.id, bridge: "water"}
              ],
              verdicts: []
            }
          ]
        })

      assert {:ok, p2} = Chronicle.write(room.id, entry2)

      # Page 3: Music under Off (no Track)
      entry3 =
        entry(%{
          opened_at: DateTime.add(now, 120, :second),
          page: %{bookends: ["mountain", "valley"]},
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
                %{seat_id: ctx.melissa.id, bridge: "ridge"},
                %{seat_id: ctx.jacob.id, bridge: "ridge"}
              ],
              verdicts: []
            }
          ]
        })

      assert {:ok, p3} = Chronicle.write(room.id, entry3)

      # Page 4: Legacy page whose Track has provider/model/cost but no path
      entry4 =
        entry(%{
          opened_at: DateTime.add(now, 180, :second),
          page: %{bookends: ["frost", "glacier"]},
          author_meta: %{model: "gemini-3.8-flash"},
          music_meta: %Track{
            meta: %{"provider" => "mureka", "model" => "mureka-v1", "cost_usd" => 0.04}
          },
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
                %{seat_id: ctx.melissa.id, bridge: "ice"},
                %{seat_id: ctx.jacob.id, bridge: "ice"}
              ],
              verdicts: []
            }
          ]
        })

      assert {:ok, p4} = Chronicle.write(room.id, entry4)

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

      :ok = Rooms.give(ctx.slug, ctx.melissa.id, "frozen lake")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "northern lights")
      await_phase(ctx.slug, :bridging)

      eventually(fn ->
        view = Rooms.snapshot(ctx.slug, ctx.melissa.id)
        not is_nil(view[:vamp]) and is_nil(view[:track])
      end)

      vamp_path = Rooms.snapshot(ctx.slug, ctx.melissa.id).vamp.path

      eventually(fn ->
        not is_nil(Rooms.snapshot(ctx.slug, ctx.melissa.id)[:track])
      end)

      track_path = Rooms.snapshot(ctx.slug, ctx.melissa.id).track.path

      :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, "cairn")
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

      entry1 =
        entry(%{
          opened_at: now,
          page: %{bookends: ["lantern", "harbour"]},
          author_meta: %{model: "gemini-3.8-flash"},
          music_meta: %Track{
            path: "/media/tracks/harbour-lights.mp3",
            title: "Harbour Lights",
            meta: %{"provider" => "mureka"}
          },
          vamp_meta: %Vamp{path: "/media/vamps/harbour-vamp.mp3", duration: 30, loop: true},
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
                %{seat_id: ctx.melissa.id, bridge: "lighthouse"},
                %{seat_id: ctx.jacob.id, bridge: "lighthouse"}
              ],
              verdicts: []
            }
          ]
        })

      assert {:ok, p1} = Chronicle.write(room.id, entry1)

      entry2 =
        entry(%{
          opened_at: DateTime.add(now, 60, :second),
          page: %{bookends: ["desert", "oasis"]},
          author_meta: %{model: "gemini-3.8-flash"},
          music_meta: %Track{
            path: "/media/tracks/oasis.mp3",
            title: "Oasis",
            meta: %{"provider" => "mureka"}
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
                %{seat_id: ctx.melissa.id, bridge: "water"},
                %{seat_id: ctx.jacob.id, bridge: "water"}
              ],
              verdicts: []
            }
          ]
        })

      assert {:ok, p2} = Chronicle.write(room.id, entry2)

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

  describe "historical feedback without rewriting play (ticket 11, #142)" do
    test "an original participant can submit and update their opinion from the Chronicle" do
      slug = open_room()
      melissa_token = device_token()
      jacob_token = device_token()
      {:ok, melissa} = Rooms.join(slug, "Melissa", melissa_token)
      {:ok, jacob} = Rooms.join(slug, "Jacob", jacob_token)

      play(%{slug: slug, melissa: melissa, jacob: jacob}, "cairn", "cairns")
      [page] = Chronicle.book(slug)

      conn = init_test_session(build_conn(), %{"device_token" => melissa_token})
      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=opinion-controls]")
      refute has_element?(view, "[data-role=admin-review-controls]")

      view
      |> element(~s([data-role=opinion-controls] [data-role=tap-too-harsh]))
      |> render_click()

      assert has_element?(view, "[data-role=fairness-tap-entry]", "Melissa: too harsh")

      view
      |> element(~s([data-role=opinion-controls] [data-role=tap-fair]))
      |> render_click()

      rendered = render(view)
      assert rendered =~ "Melissa: too harsh"
      assert rendered =~ "Melissa: fair"

      taps = Chronicle.fairness_taps(Repo.get_by!(Room, slug: slug).id)
      assert Enum.map(taps, & &1.label) == ["too_harsh", "fair"]
      assert Enum.all?(taps, &(&1.seat_id == melissa.id))
      assert page.id == hd(Chronicle.book(slug)).id
    end

    test "a visitor without a Seat cannot submit participant feedback", %{conn: conn} = ctx do
      play(ctx, "cairn", "cairns")
      room = Repo.get_by!(Room, slug: ctx.slug)
      [page] = Chronicle.book(room.id)

      {:ok, view, _html} = live(conn, ~p"/r/#{ctx.slug}/chronicle")

      refute has_element?(view, "[data-role=opinion-controls]")
      refute has_element?(view, "[data-role=admin-review-controls]")

      render_click(view, "record_opinion", %{
        "page-id" => page.id,
        "attempt" => "1",
        "label" => "too_harsh"
      })

      assert Chronicle.fairness_taps(room.id) == []
    end

    test "a Seat cannot replace another participant's opinion" do
      slug = open_room()
      melissa_token = device_token()
      jacob_token = device_token()
      {:ok, melissa} = Rooms.join(slug, "Melissa", melissa_token)
      {:ok, jacob} = Rooms.join(slug, "Jacob", jacob_token)
      play(%{slug: slug, melissa: melissa, jacob: jacob}, "cairn", "cairns")

      melissa_conn = init_test_session(build_conn(), %{"device_token" => melissa_token})
      {:ok, melissa_view, _} = live(melissa_conn, ~p"/r/#{slug}/chronicle")

      melissa_view
      |> element(~s([data-role=opinion-controls] [data-role=tap-fair]))
      |> render_click()

      jacob_conn = init_test_session(build_conn(), %{"device_token" => jacob_token})
      {:ok, jacob_view, _} = live(jacob_conn, ~p"/r/#{slug}/chronicle")

      jacob_view
      |> element(~s([data-role=opinion-controls] [data-role=tap-too-kind]))
      |> render_click()

      room = Repo.get_by!(Room, slug: slug)
      taps = Chronicle.fairness_taps(room.id)
      assert Enum.find(taps, &(&1.seat_id == melissa.id)).label == "fair"
      assert Enum.find(taps, &(&1.seat_id == jacob.id)).label == "too_kind"
    end

    test "the authenticated admin can review any Attempt with distinct attribution", ctx do
      play(ctx, "cairn", "cairns")
      room = Repo.get_by!(Room, slug: ctx.slug)

      conn = log_in_admin(build_conn())
      {:ok, view, _html} = live(conn, ~p"/r/#{ctx.slug}/chronicle")

      refute has_element?(view, "[data-role=opinion-controls]")
      assert has_element?(view, "[data-role=admin-review-controls]")

      view
      |> element(~s([data-role=admin-review-controls] [data-role=tap-too-kind]))
      |> render_click()

      assert has_element?(view, "[data-role=admin-review]", "Admin: too kind")

      [tap] = Chronicle.fairness_taps(room.id)
      assert tap.source == "admin"
      assert tap.seat_id == nil
      assert tap.label == "too_kind"
    end

    test "an overruled Attempt can be reviewed without changing the Verdict or Precedent" do
      slug = open_room()
      melissa_token = device_token()
      jacob_token = device_token()
      {:ok, melissa} = Rooms.join(slug, "Melissa", melissa_token)
      {:ok, jacob} = Rooms.join(slug, "Jacob", jacob_token)
      play(%{slug: slug, melissa: melissa, jacob: jacob}, "cairn", "beacon")
      :ok = Rooms.propose_overrule(slug, melissa.id)
      :ok = Rooms.agree_overrule(slug, jacob.id)

      room = Repo.get_by!(Room, slug: slug)
      [page] = Chronicle.pages(room.id)
      [attempt] = page.attempts
      [verdict] = attempt.verdicts
      verdict_before = {verdict.id, verdict.closeness, verdict.overruled}

      precedents_before =
        Thereish.Steward.Precedent
        |> Repo.all()
        |> Enum.map(&{&1.id, &1.key, &1.closeness})

      conn = init_test_session(build_conn(), %{"device_token" => melissa_token})
      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert has_element?(view, "[data-role=overrule]")

      view
      |> element(~s([data-role=opinion-controls] [data-role=tap-too-harsh]))
      |> render_click()

      assert has_element?(view, "[data-role=fairness-tap-entry]", "Melissa: too harsh")
      assert has_element?(view, "[data-role=overrule]")

      [tap] = Chronicle.fairness_taps(room.id)
      assert tap.label == "too_harsh"
      assert tap.closeness == 0

      fresh = Repo.get!(Thereish.Chronicle.Verdict, verdict.id)
      assert {fresh.id, fresh.closeness, fresh.overruled} == verdict_before

      precedents_after =
        Thereish.Steward.Precedent
        |> Repo.all()
        |> Enum.map(&{&1.id, &1.key, &1.closeness})

      assert precedents_after == precedents_before
    end

    test "an obsolete correction event does not write", %{conn: conn} = ctx do
      play(ctx, "cairn", "cairns")
      room = Repo.get_by!(Room, slug: ctx.slug)

      {:ok, view, _html} = live(conn, ~p"/r/#{ctx.slug}/chronicle")

      render_click(view, "record_correction", %{
        "correction" => %{
          "attempt_number" => "1",
          "target" => "bridge",
          "original_value" => "cairns",
          "corrected_value" => "cairn",
          "note" => "stale client"
        }
      })

      assert Chronicle.corrections(room.id) == []
      refute has_element?(view, "[data-role=correction-form]")
    end
  end
end
