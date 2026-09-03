defmodule MeaningGameWeb.CheckLiveTest do
  use MeaningGameWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the dead render says the socket is not connected yet", %{conn: conn} do
    conn = get(conn, ~p"/check")
    html = html_response(conn, 200)

    assert html =~ "Socket not connected"
    refute html =~ "Socket connected"
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

  test "falling back to long polling is named as the broken thing it is", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/check")

    html = render_hook(live, "browser_reported", %{"transport" => "LongPoll"})

    assert html =~ "Transport: LongPoll (the websocket upgrade is not working)"
  end
end
