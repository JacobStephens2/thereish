defmodule MeaningGameWeb.ChronicleLiveTest do
  @moduledoc """
  The Chronicle as a book read on a phone (ticket 08).
  """
  use MeaningGameWeb.ConnCase, async: false

  import MeaningGame.RoomFixtures
  import Phoenix.LiveViewTest

  alias MeaningGame.Chronicle
  alias MeaningGame.Rooms
  alias MeaningGame.Repo
  alias MeaningGame.Rooms.Room

  setup do
    slug = open_room()
    {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    %{slug: slug, melissa: melissa, jacob: jacob}
  end

  defp play(ctx, melissa_bridge, jacob_bridge) do
    :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, melissa_bridge)
    :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, jacob_bridge)

    await_reveal(ctx.slug)
  end

  describe "the Chronicle book page" do
    test "shows empty state when no pages have closed", %{conn: conn, slug: slug} do
      {:ok, view, html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert html =~ "The Chronicle"
      assert html =~ "empty" or has_element?(view, "[data-role=empty-chronicle]")
    end

    test "reads pages in reverse chronological order with anchors, attempts, bridges, and verdicts",
         %{conn: conn, slug: slug} = ctx do
      # Play first page: melded
      play(ctx, "cairn", "cairo")

      # Play second page: two attempts
      attempt_cap(2)
      :ok = Rooms.next_page(slug, ctx.melissa.id)
      play(ctx, "mirage", "oasis")
      :ok = Rooms.next_attempt(slug, ctx.melissa.id)
      play(ctx, "sand", "dune")

      {:ok, view, html} = live(conn, ~p"/r/#{slug}/chronicle")

      assert html =~ "The Chronicle"

      # Both pages rendered
      assert has_element?(view, "[data-role=chronicle-page]", "lantern")

      assert has_element?(view, "[data-role=chronicle-page]", "sand") or
               has_element?(view, "[data-role=chronicle-page]", "mirage")

      # Reverse chronological order: newest page (second page) appears before first page in HTML
      rendered_html = render(view)
      assert rendered_html =~ "lantern"
      assert rendered_html =~ "harbour"
      assert rendered_html =~ "Melissa"
      assert rendered_html =~ "cairn"
      assert rendered_html =~ "Jacob"
      assert rendered_html =~ "cairo"
      assert rendered_html =~ "80"

      {p2_pos, _} = :binary.match(rendered_html, "sand")
      {p1_pos, _} = :binary.match(rendered_html, "lantern")
      assert p2_pos < p1_pos

      # The Code opens it in whatever case it was typed in.
      {:ok, _shouted, shouted_html} = live(conn, "/r/#{String.upcase(slug)}/chronicle")
      assert shouted_html =~ "The Chronicle"
    end

    test "shows overrules and player corrections, and allows recording an edit",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairo")

      room = Repo.get_by!(Room, slug: slug)
      [page] = Chronicle.pages(room.id)

      # Record an overrule
      {:ok, _overrule} =
        Chronicle.record_overrule(room.id, %{
          page_id: page.id,
          attempt_number: 1,
          proposer_seat_id: ctx.melissa.id,
          anchors: ["lantern", "harbour"],
          bridges: ["cairn", "cairo"],
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
          "original_value" => "cairo",
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
      assert rendered =~ "(cairo)"

      # Database verifies it appended rather than mutating
      assert [correction] = Chronicle.corrections(room.id)
      assert correction.page_id == page.id
      assert correction.attempt_number == 1
      assert correction.corrected_value == "cairn"
      assert correction.original_value == "cairo"
    end

    test "shows fairness taps alongside the page and attempt they judge",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairo")

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

    test "experiment is blinded until deliberately unblinded, then reveals qualitative readout",
         %{conn: conn, slug: slug} = ctx do
      play(ctx, "cairn", "cairo")

      {:ok, view, _html} = live(conn, ~p"/r/#{slug}/chronicle")

      # Experiment card is visible with blinded banner
      assert has_element?(view, "[data-role=experiment-card]")
      assert has_element?(view, "[data-role=blinded-banner]")
      assert has_element?(view, "[data-role=unblind-button]")

      # While blinded, no arm tag appears on the page
      refute has_element?(view, "[data-role=arm-tag]")
      refute has_element?(view, "[data-role=experiment-readout]")

      # Deliberate unblinding
      view |> element("[data-role=unblind-button]") |> render_click()

      # Now unblinded banner is shown
      assert has_element?(view, "[data-role=unblinded-banner]")
      refute has_element?(view, "[data-role=unblind-button]")

      # Arm tag is now displayed on the played page
      assert has_element?(view, "[data-role=arm-tag]")

      # Qualitative readout is displayed
      assert has_element?(view, "[data-role=experiment-readout]")
      assert has_element?(view, "[data-role=readout-narrative]")
      readout_text = element(view, "[data-role=experiment-readout]") |> render()
      assert readout_text =~ "Bait-scored Pages"
      assert readout_text =~ "Plain Pages"

      # No p-values
      refute readout_text =~ ~r/p\s*<\s*0\.05/i
      refute readout_text =~ "p-value"
    end
  end
end
