defmodule ThereishWeb.AdminExperimentsTest do
  @moduledoc """
  Experiment readout and unblinding live behind the admin boundary (ticket 09).
  """
  use ThereishWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Thereish.RoomFixtures

  alias Thereish.Chronicle
  alias Thereish.Repo
  alias Thereish.Rooms
  alias Thereish.Rooms.Room

  setup %{conn: conn} do
    slug = open_room()
    {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    %{conn: log_in_admin(conn), slug: slug, melissa: melissa, jacob: jacob}
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

  defp record_assignment(room_id, experiment_id, arm) do
    {:ok, _} =
      Chronicle.record_experiment_assignment(room_id, %{
        page_identifier: "#{experiment_id}-#{System.unique_integer([:positive])}",
        experiment_id: experiment_id,
        arm: arm,
        chapter: "harbour",
        assigned_at: DateTime.utc_now()
      })
  end

  defp record_completed_outcomes(room_id, experiment_id, count, opts \\ []) when count > 0 do
    arm = Keyword.get(opts, :arm, default_experiment_arm(experiment_id))

    for i <- 1..count do
      {:ok, _} =
        Chronicle.record_experiment_outcome(room_id, %{
          page_identifier: "#{experiment_id}-#{i}-#{System.unique_integer([:positive])}",
          experiment_id: experiment_id,
          arm: arm,
          melded: true,
          closeness: 80,
          attempts_count: 1,
          closed_because: "meld"
        })
    end
  end

  defp default_experiment_arm("bait_against_plain"), do: "bait"
  defp default_experiment_arm(_experiment_id), do: "flash"

  defp unblind_button(view, experiment_id) do
    element(view, "[data-experiment=#{experiment_id}] [data-role=unblind-button]")
  end

  test "unauthenticated visitors cannot unblind from the ordinary Chronicle",
       %{
         conn: _conn,
         slug: slug
       } = ctx do
    play(ctx, "cairn", "cairns")
    room = Repo.get_by!(Room, slug: slug)
    [page] = Chronicle.pages(room.id)

    {:ok, _} =
      Chronicle.record_experiment_assignment(room.id, %{
        page_id: page.id,
        page_identifier: page.id,
        experiment_id: "bait_against_plain",
        arm: "bait",
        chapter: "harbour",
        assigned_at: DateTime.utc_now()
      })

    {:ok, _} =
      Chronicle.record_experiment_outcome(room.id, %{
        page_id: page.id,
        page_identifier: page.id,
        experiment_id: "bait_against_plain",
        arm: "bait",
        melded: true,
        closeness: 80,
        attempts_count: 1,
        closed_because: "meld",
        trap_converged: false
      })

    {:ok, chronicle, _html} = live(build_conn(), ~p"/r/#{slug}/chronicle")
    refute has_element?(chronicle, "[data-role=experiment-card]")
    refute has_element?(chronicle, "[data-role=unblind-button]")
    refute has_element?(chronicle, "[data-role=arm-tag]")
    refute Chronicle.experiment_unblinded?(room.id, "bait_against_plain")
  end

  test "experiment is blinded until deliberately unblinded, then reveals qualitative readout",
       %{conn: conn, slug: slug} = ctx do
    play(ctx, "cairn", "cairns")

    room = Repo.get_by!(Room, slug: slug)
    [page] = Chronicle.pages(room.id)

    {:ok, _} =
      Chronicle.record_experiment_assignment(room.id, %{
        page_id: page.id,
        page_identifier: page.id,
        experiment_id: "bait_against_plain",
        arm: "bait",
        chapter: "harbour",
        assigned_at: DateTime.utc_now()
      })

    {:ok, _} =
      Chronicle.record_experiment_outcome(room.id, %{
        page_id: page.id,
        page_identifier: page.id,
        experiment_id: "bait_against_plain",
        arm: "bait",
        melded: true,
        closeness: 80,
        attempts_count: 1,
        closed_because: "meld",
        trap_converged: false
      })

    record_completed_outcomes(room.id, "bait_against_plain", 19)

    {:ok, view, _html} = live(conn, ~p"/admin/experiments")

    assert has_element?(view, "[data-role=experiment-card][data-experiment=bait_against_plain]")
    assert has_element?(view, "[data-experiment=bait_against_plain] [data-role=blinded-banner]")
    assert has_element?(view, "[data-experiment=bait_against_plain] [data-role=unblind-button]")
    refute has_element?(view, "[data-role=experiment-readout]")

    unblind_button(view, "bait_against_plain") |> render_click()

    assert has_element?(view, "[data-experiment=bait_against_plain] [data-role=unblinded-banner]")
    refute has_element?(view, "[data-experiment=bait_against_plain] [data-role=unblind-button]")
    assert has_element?(view, "[data-role=experiment-readout]")
    assert has_element?(view, "[data-role=readout-narrative]")
    readout_text = element(view, "[data-role=experiment-readout]") |> render()
    assert readout_text =~ "Bait-scored Pages"
    assert readout_text =~ "Plain Pages"
    refute readout_text =~ ~r/p\s*<\s*0\.05/i
    refute readout_text =~ "p-value"

    {:ok, chronicle, _html} = live(build_conn(), ~p"/r/#{slug}/chronicle")
    refute has_element?(chronicle, "[data-role=arm-tag]")
    refute has_element?(chronicle, "[data-role=experiment-card]")
  end

  test "author_model experiment is blinded until unblinded, showing Flash and Astra readout",
       %{conn: conn} = ctx do
    play(ctx, "cairn", "cairns")

    room = Repo.get_by!(Room, slug: ctx.slug)
    [page] = Chronicle.pages(room.id)

    {:ok, _} =
      Chronicle.record_experiment_assignment(room.id, %{
        page_id: page.id,
        page_identifier: page.id,
        experiment_id: "author_model",
        arm: "flash",
        chapter: "table",
        assigned_at: DateTime.utc_now()
      })

    {:ok, _} =
      Chronicle.record_experiment_outcome(room.id, %{
        page_id: page.id,
        page_identifier: page.id,
        experiment_id: "author_model",
        arm: "flash",
        melded: true,
        closeness: 80,
        closing_band: "meld",
        attempts_count: 1,
        closed_because: "meld"
      })

    {:ok, _} =
      Chronicle.record_bookends_tap(room.id, %{
        page_id: page.id,
        page_identifier: page.id,
        seat_id: ctx.melissa.id,
        label: "great",
        bookends: page.document["bookends"],
        arm: "flash"
      })

    record_completed_outcomes(room.id, "author_model", 19)

    {:ok, view, html} = live(conn, ~p"/admin/experiments")

    assert html =~ "Flash against Astra"
    assert has_element?(view, "[data-experiment=author_model] [data-role=blinded-banner]")
    assert has_element?(view, "[data-experiment=author_model] [data-role=unblind-button]")
    refute has_element?(view, "[data-role=experiment-readout]")

    unblind_button(view, "author_model") |> render_click()

    assert has_element?(view, "[data-role=unblinded-banner]")
    assert has_element?(view, "[data-role=experiment-readout]")
    assert has_element?(view, "[data-role=readout-arm-flash]")
    assert has_element?(view, "[data-role=readout-arm-astra]")

    readout_text = element(view, "[data-role=experiment-readout]") |> render()
    assert readout_text =~ "Gemini 3.8 Flash"
    assert readout_text =~ "GPT-6 Astra"
    assert readout_text =~ "1 great"
    assert readout_text =~ "meld:"
    refute readout_text =~ "p-value"
  end

  test "shows blinded progress and rejects unblinding below the sample minimum", %{conn: conn} do
    slug = open_room()
    room = Repo.get_by!(Room, slug: slug)

    record_assignment(room.id, "author_model", "flash")
    record_completed_outcomes(room.id, "author_model", 10, arm: "flash")
    record_completed_outcomes(room.id, "author_model", 9, arm: "astra")

    {:ok, view, _html} = live(conn, ~p"/admin/experiments")

    card = "[data-role=experiment-card][data-experiment=author_model]"
    card_html = element(view, card) |> render()

    assert has_element?(view, "#{card} [data-role=experiment-progress]")
    assert card_html =~ "19 / 20"
    assert has_element?(view, "#{card} [data-role=unblind-button][disabled]")
    refute has_element?(view, "[data-role=experiment-readout]")
    refute card_html =~ "Pages played:"
    refute card_html =~ "Mean attempts:"

    render_click(view, "unblind_experiment", %{
      "room-id" => room.id,
      "experiment-id" => "author_model"
    })

    refute Chronicle.experiment_unblinded?(room.id, "author_model")
    refute has_element?(view, "[data-role=unblinded-banner]")
    refute has_element?(view, "[data-role=experiment-readout]")
    assert has_element?(view, "#{card} [data-role=blinded-banner]")
  end

  test "permits unblinding from the admin view once the declared minimum is reached",
       %{conn: conn} do
    slug = open_room()
    room = Repo.get_by!(Room, slug: slug)

    record_assignment(room.id, "author_model", "flash")
    record_completed_outcomes(room.id, "author_model", 10, arm: "flash")
    record_completed_outcomes(room.id, "author_model", 10, arm: "astra")

    {:ok, view, _html} = live(conn, ~p"/admin/experiments")

    card = "[data-role=experiment-card][data-experiment=author_model]"
    card_html = element(view, card) |> render()
    assert card_html =~ "20 / 20"
    refute has_element?(view, "#{card} [data-role=unblind-button][disabled]")

    unblind_button(view, "author_model") |> render_click()

    assert Chronicle.experiment_unblinded?(room.id, "author_model")
    assert has_element?(view, "#{card} [data-role=unblinded-banner]")
    assert has_element?(view, "#{card} [data-role=experiment-readout]")
  end

  test "progress stays per Room and per experiment without leaking another experiment's results",
       %{conn: conn} do
    slug_a = open_room()
    slug_b = open_room()
    room_a = Repo.get_by!(Room, slug: slug_a)
    room_b = Repo.get_by!(Room, slug: slug_b)

    record_assignment(room_a.id, "author_model", "flash")
    record_assignment(room_a.id, "bait_against_plain", "bait")
    record_assignment(room_b.id, "author_model", "flash")
    record_completed_outcomes(room_a.id, "author_model", 20, arm: "flash")
    record_completed_outcomes(room_a.id, "bait_against_plain", 3, arm: "bait")
    record_completed_outcomes(room_b.id, "author_model", 4, arm: "astra")

    {:ok, view, _html} = live(conn, ~p"/admin/experiments")

    author_a = "[data-slug=#{slug_a}][data-experiment=author_model]"
    bait_a = "[data-slug=#{slug_a}][data-experiment=bait_against_plain]"
    author_b = "[data-slug=#{slug_b}][data-experiment=author_model]"

    assert render(element(view, author_a)) =~ "20 / 20"
    assert render(element(view, bait_a)) =~ "3 / 20"
    assert render(element(view, author_b)) =~ "4 / 20"

    refute has_element?(view, "#{author_a} [data-role=unblind-button][disabled]")
    assert has_element?(view, "#{bait_a} [data-role=unblind-button][disabled]")
    assert has_element?(view, "#{author_b} [data-role=unblind-button][disabled]")

    element(view, "#{author_a} [data-role=unblind-button]") |> render_click()

    assert Chronicle.experiment_unblinded?(room_a.id, "author_model")
    refute Chronicle.experiment_unblinded?(room_a.id, "bait_against_plain")
    refute Chronicle.experiment_unblinded?(room_b.id, "author_model")
    assert has_element?(view, "#{author_a} [data-role=experiment-readout]")
    refute has_element?(view, "#{bait_a} [data-role=experiment-readout]")
    refute has_element?(view, "#{author_b} [data-role=experiment-readout]")
  end
end
