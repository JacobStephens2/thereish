defmodule ThereishWeb.AdminRoomsTest do
  @moduledoc """
  Authenticated Room discovery and Page timing (ticket 10).
  """
  use ThereishWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Thereish.RoomFixtures

  alias Thereish.Chronicle
  alias Thereish.Repo
  alias Thereish.Rooms
  alias Thereish.Rooms.Room

  describe "operator access" do
    test "an unauthenticated visitor is sent to sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/rooms")
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/timing")
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/timing/dust")
    end

    test "the overview links through to Rooms and Timing", %{conn: conn} do
      conn = log_in_admin(conn)
      {:ok, overview, html} = live(conn, ~p"/admin")

      assert has_element?(overview, "a[href='/admin/rooms']", "Rooms")
      assert has_element?(overview, "a[href='/admin/timing']", "Timing")
      refute html =~ "coming soon"

      {:ok, rooms, rooms_html} = live(conn, ~p"/admin/rooms")
      assert has_element?(rooms, "[data-role=admin-rooms]")
      assert rooms_html =~ ~r/<meta[^>]*robots[^>]*noindex/i
      assert has_element?(rooms, "a[href='/admin']")

      {:ok, timing, timing_html} = live(conn, ~p"/admin/timing")
      assert has_element?(timing, "[data-role=admin-timing]")
      assert timing_html =~ ~r/<meta[^>]*robots[^>]*noindex/i
      assert has_element?(timing, "a[href='/admin']")
    end
  end

  describe "Room discovery" do
    setup %{conn: conn} do
      %{conn: log_in_admin(conn)}
    end

    test "lists every Room with its Chronicle and timing, without needing the Code in advance",
         %{conn: conn} do
      slug = open_room()
      {:ok, _mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, _jacob} = Rooms.join(slug, "Jacob", device_token())

      {:ok, view, _html} = live(conn, ~p"/admin/rooms")

      refute has_element?(view, "[data-role=rooms-empty]")
      assert has_element?(view, "[data-role=admin-room][data-slug=#{slug}]")
      assert has_element?(view, "a[href='/r/#{slug}/chronicle']", "Chronicle")
      assert has_element?(view, "a[href='/admin/timing/#{slug}']", "Timing")
    end

    test "an empty operator list says so honestly", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/rooms")

      assert has_element?(view, "[data-role=rooms-empty]")
      refute has_element?(view, "[data-role=admin-room]")
    end
  end

  describe "Page timing" do
    setup %{conn: conn} do
      slug = open_room()
      token = device_token()
      {:ok, mara} = Rooms.join(slug, "Mara", token)
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      %{
        conn: log_in_admin(conn),
        slug: slug,
        token: token,
        mara: mara,
        jacob: jacob
      }
    end

    test "an early Meld records exact occurrence times and a phase breakdown", ctx do
      play_meld(ctx, "cairn", "cairns")

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/timing/#{ctx.slug}")

      assert has_element?(
               view,
               "[data-role=page-timing][data-kind=exact][data-outcome=early-meld]"
             )

      assert has_element?(
               view,
               "[data-role=page-timing] [data-phase=give-entry][data-kind=exact]"
             )

      assert has_element?(
               view,
               "[data-role=page-timing] [data-phase=generation][data-kind=exact]"
             )

      assert has_element?(
               view,
               "[data-role=page-timing] [data-phase=bridge-writing][data-kind=exact]"
             )

      assert has_element?(
               view,
               "[data-role=page-timing] [data-phase=assayer-beat][data-kind=exact]"
             )

      assert has_element?(
               view,
               "[data-role=page-timing] [data-phase=reveal-pauses][data-kind=exact]"
             )

      refute has_element?(view, "[data-kind=estimate]")
      refute has_element?(view, "[data-kind=unavailable]")

      [page] = chronicled(ctx.slug)
      assert [give_a, give_b] = Enum.sort_by(page.gives, & &1.order)
      assert %DateTime{} = give_a.arrived_at
      assert %DateTime{} = give_b.arrived_at
      assert [attempt] = page.attempts
      assert %DateTime{} = attempt.started_at
      assert %DateTime{} = attempt.assaying_started_at
      assert %DateTime{} = attempt.revealed_at
      assert %DateTime{} = page.revealed_at
      assert DateTime.compare(page.opened_at, give_a.arrived_at) in [:lt, :eq]
      assert DateTime.compare(give_a.arrived_at, attempt.started_at) in [:lt, :eq]
      assert DateTime.compare(attempt.started_at, attempt.assaying_started_at) in [:lt, :eq]
      assert DateTime.compare(attempt.assaying_started_at, attempt.revealed_at) in [:lt, :eq]
      assert DateTime.compare(page.revealed_at, page.closed_at) in [:lt, :eq]
    end

    test "resetting Gives reopens Give entry so a failed Author wait is not billed there", ctx do
      steward(author_mode: :unavailable)

      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      eventually(fn -> Rooms.snapshot(ctx.slug, ctx.mara.id).author_failure end)

      Process.sleep(120)
      marker = DateTime.utc_now()
      :ok = Rooms.reset_gives(ctx.slug, ctx.mara.id)

      steward(author_mode: :ok)
      play_meld(ctx, "cairn", "cairns")

      [page] = chronicled(ctx.slug)
      assert DateTime.compare(page.opened_at, marker) in [:gt, :eq]

      {:ok, view, _} = live(ctx.conn, ~p"/admin/timing/#{ctx.slug}")

      assert has_element?(
               view,
               "[data-role=page-timing][data-kind=exact][data-outcome=early-meld]"
             )
    end

    test "a fifth-Attempt Meld is distinct from an earlier Meld, and exhaustion is distinct from either",
         ctx do
      play_misses(ctx, 4)
      play_meld(ctx, "stone", "stones")

      exhausted_slug = open_room()
      {:ok, mara} = Rooms.join(exhausted_slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(exhausted_slug, "Jacob", device_token())
      exhausted = %{slug: exhausted_slug, mara: mara, jacob: jacob}
      play_misses(exhausted, 5)

      {:ok, fifth, _} = live(ctx.conn, ~p"/admin/timing/#{ctx.slug}")

      assert has_element?(
               fifth,
               "[data-role=page-timing][data-outcome=fifth-attempt-meld][data-kind=exact]"
             )

      refute has_element?(fifth, "[data-outcome=early-meld]")
      refute has_element?(fifth, "[data-outcome=exhausted]")

      assert has_element?(
               fifth,
               "[data-role=page-timing] [data-phase=reveal-pauses][data-kind=exact]"
             )

      [fifth_page] = chronicled(ctx.slug)
      assert Enum.map(fifth_page.attempts, & &1.number) == [1, 2, 3, 4, 5]

      for attempt <- Enum.take(fifth_page.attempts, 4) do
        assert %DateTime{} = attempt.started_at
        assert %DateTime{} = attempt.assaying_started_at
        assert %DateTime{} = attempt.revealed_at
        assert %DateTime{} = attempt.advanced_at
      end

      last = List.last(fifth_page.attempts)
      assert %DateTime{} = last.started_at
      assert %DateTime{} = last.revealed_at
      assert is_nil(last.advanced_at)

      {:ok, spent, _} = live(ctx.conn, ~p"/admin/timing/#{exhausted_slug}")

      assert has_element?(
               spent,
               "[data-role=page-timing][data-outcome=exhausted][data-kind=exact]"
             )

      refute has_element?(spent, "[data-outcome=early-meld]")
      refute has_element?(spent, "[data-outcome=fifth-attempt-meld]")
    end

    test "delayed Chronicle writing and Voice metadata do not move occurrence times", ctx do
      :ok = Rooms.claim_speaker(ctx.slug, ctx.token)
      delay_voice(200)

      play_meld(ctx, "cairn", "cairns")
      await_reveal(ctx.slug)

      assert chronicled(ctx.slug) == []

      page =
        eventually(
          fn ->
            case chronicled(ctx.slug) do
              [written] -> written
              _ -> false
            end
          end,
          "the delayed Chronicle write never landed"
        )

      assert %DateTime{} = page.revealed_at
      lag_ms = DateTime.diff(page.closed_at, page.revealed_at, :millisecond)
      assert lag_ms >= 100

      {:ok, view, _} = live(ctx.conn, ~p"/admin/timing/#{ctx.slug}")
      html = render(element(view, "[data-role=page-timing]"))
      assert html =~ ~s(data-kind="exact")
      total_ms = timing_total_ms(html)
      opened_to_closed_ms = DateTime.diff(page.closed_at, page.opened_at, :millisecond)
      assert total_ms < opened_to_closed_ms

      {:ok, again, _} = live(ctx.conn, ~p"/admin/timing/#{ctx.slug}")
      again_html = render(element(again, "[data-role=page-timing]"))
      assert timing_total_ms(again_html) == total_ms
    end

    test "legacy opened-to-closed duration is an estimate and the breakdown is unavailable",
         %{conn: conn} = ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      opened = DateTime.utc_now() |> DateTime.add(-45, :second)

      {:ok, _} =
        Chronicle.write(
          room.id,
          %{
            page: %{"bookends" => ["lantern", "harbour"]},
            closed_because: :meld,
            melded?: true,
            closeness: 80,
            attempts: [
              %{
                number: 1,
                bookends: ["lantern", "harbour"],
                closeness: 80,
                melded?: true,
                bridges: [
                  %{seat_id: ctx.mara.id, bridge: "cairn"},
                  %{seat_id: ctx.jacob.id, bridge: "cairns"}
                ],
                verdicts: []
              }
            ]
          },
          opened
        )

      {:ok, view, html} = live(conn, ~p"/admin/timing/#{ctx.slug}")

      assert has_element?(view, "[data-role=page-timing][data-kind=estimate]")
      assert html =~ "estimate"
      assert has_element?(view, "[data-phase=give-entry][data-kind=unavailable]")
      assert has_element?(view, "[data-phase=generation][data-kind=unavailable]")
      assert has_element?(view, "[data-phase=bridge-writing][data-kind=unavailable]")
      assert has_element?(view, "[data-phase=assayer-beat][data-kind=unavailable]")
      refute has_element?(view, "[data-kind=exact]")
    end
  end

  defp play_meld(ctx, left, right) do
    give_if_needed(ctx)
    :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, left)
    :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, right)
    await_reveal(ctx.slug)
  end

  @misses [
    {"cairn", "beacon"},
    {"wharf", "gantry"},
    {"quay", "quiet"},
    {"torch", "lamp"},
    {"ridge", "cliff"}
  ]

  defp play_misses(ctx, count) when count > 0 do
    give_if_needed(ctx)

    @misses
    |> Enum.take(count)
    |> Enum.each(fn {left, right} ->
      :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, left)
      :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, right)
      await_reveal(ctx.slug)

      if Rooms.snapshot(ctx.slug, nil).phase == :reveal do
        :ok = Rooms.next_attempt(ctx.slug, ctx.mara.id)
      end
    end)
  end

  defp give_if_needed(ctx) do
    if Rooms.snapshot(ctx.slug, nil).phase == :giving do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)
    end
  end

  defp chronicled(slug) do
    Chronicle.pages(Repo.get_by!(Room, slug: slug).id)
  end

  defp timing_total_ms(html) do
    [ms] = Regex.run(~r/data-total-ms="(\d+)"/, html, capture: :all_but_first)
    String.to_integer(ms)
  end

  defp delay_voice(ms) do
    steward_env = Application.get_env(:thereish, :steward, [])
    fake_env = Keyword.get(steward_env, :fake, [])

    Application.put_env(
      :thereish,
      :steward,
      Keyword.put(steward_env, :fake, Keyword.put(fake_env, :voice_delay_ms, ms))
    )

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:thereish, :steward, steward_env)
    end)
  end
end
