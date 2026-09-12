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

    {:ok, view, _html} = live(conn, ~p"/admin/experiments")

    assert has_element?(view, "[data-role=experiment-card]")
    assert has_element?(view, "[data-role=blinded-banner]")
    assert has_element?(view, "[data-role=unblind-button]")
    refute has_element?(view, "[data-role=experiment-readout]")

    view |> element("[data-role=unblind-button]") |> render_click()

    assert has_element?(view, "[data-role=unblinded-banner]")
    refute has_element?(view, "[data-role=unblind-button]")
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

    {:ok, view, html} = live(conn, ~p"/admin/experiments")

    assert html =~ "Flash against Astra"
    assert has_element?(view, "[data-role=blinded-banner]")
    assert has_element?(view, "[data-role=unblind-button]")
    refute has_element?(view, "[data-role=experiment-readout]")

    view |> element("[data-role=unblind-button]") |> render_click()

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
end
