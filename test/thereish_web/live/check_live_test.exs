defmodule ThereishWeb.CheckLiveTest do
  use ThereishWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the dead render says the socket is not connected yet", %{conn: conn} do
    conn = get(conn, ~p"/check")
    html = html_response(conn, 200)

    assert html =~ "Socket not connected"
    refute html =~ "Socket connected"
    assert html =~ "Thereish"
  end

  test "the live render says the socket is connected", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/check")

    assert html =~ "Socket connected"
    refute html =~ "Socket not connected"
  end

  test "browser capabilities read as unknown until the browser reports them", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/check")
    html = render(live)

    assert html =~ "Transport: unknown"
    assert html =~ "Secure context: unknown"
    assert html =~ "Screen Wake Lock: unknown"
  end

  test "the browser's report of a secure context with wake lock is rendered", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/check")

    html =
      render_hook(live, "browser_reported", %{
        "transport" => "WebSocket",
        "secure_context" => true,
        "wake_lock" => true
      })

    assert html =~ "Transport: WebSocket"
    assert html =~ "Secure context: yes"
    assert html =~ "Screen Wake Lock: available"
  end

  test "an insecure context without wake lock is rendered as such", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/check")

    html =
      render_hook(live, "browser_reported", %{
        "transport" => "WebSocket",
        "secure_context" => false,
        "wake_lock" => false
      })

    assert html =~ "Secure context: no"
    assert html =~ "Screen Wake Lock: unavailable"
  end

  test "a deployment without the Scribe's prose gate says so", %{conn: conn} do
    # A missing `vale` serves every page perfectly and writes no recaps at all,
    # which is exactly the kind of quiet breakage this page is for.
    {:ok, _live, html} = live(conn, ~p"/check")

    assert html =~ "Prose gate: installed"
  end

  test "falling back to long polling is named as the broken thing it is", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/check")

    html = render_hook(live, "browser_reported", %{"transport" => "LongPoll"})

    assert html =~ "Transport: LongPoll (the websocket upgrade is not working)"
  end

  test "the database status is rendered as connected when migrated", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/check")

    assert html =~ ~s(data-check="database")
    assert html =~ "Database: connected"
  end

  test "the dead render reports database connected", %{conn: conn} do
    conn = get(conn, ~p"/check")
    html = html_response(conn, 200)

    assert html =~ ~s(data-check="database")
    assert html =~ "Database: connected"
  end
end
