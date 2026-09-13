defmodule ThereishWeb.AdminOverviewTest do
  @moduledoc """
  The signed-in operator overview (ticket 09).
  """
  use ThereishWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{conn: log_in_admin(conn)}
  end

  test "lists operator tools without placeholder copy", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin")

    assert has_element?(view, "[data-role=admin-overview]")
    assert html =~ ~r/<meta[^>]*robots[^>]*noindex/i
    assert has_element?(view, "a[href='/spend']", "Spend")
    assert has_element?(view, "a[href='/admin/experiments']", "Experiments")
    assert has_element?(view, "a[href='/admin/media']", "Media")
    assert has_element?(view, "a[href='/admin/rooms']", "Rooms")
    assert has_element?(view, "a[href='/admin/timing']", "Timing")
    assert has_element?(view, "a[href='/calibration.json']")
    assert has_element?(view, "a[href='/calibration.jsonl']")
    refute html =~ "coming soon"
  end
end
