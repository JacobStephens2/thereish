defmodule ThereishWeb.AdminAuthTest do
  @moduledoc """
  Password setup, reset, sign-in, and the operator access boundary (ticket 09).
  """
  use ThereishWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Thereish.AdminFixtures
  import Thereish.RoomFixtures

  alias ThereishWeb.DeviceToken

  @password valid_admin_password()

  describe "password setup and sign-in" do
    test "an unauthenticated visitor is sent to sign-in from operator routes", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin")
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/spend")
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/experiments")
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/media")
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/rooms")
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/timing")

      conn = get(conn, ~p"/calibration.json")
      assert redirected_to(conn) == "/admin/sign-in"

      conn = get(build_conn(), ~p"/r/couch/chronicle.md")
      assert redirected_to(conn) == "/admin/sign-in"

      conn = get(build_conn(), ~p"/r/couch/calibration.json")
      assert redirected_to(conn) == "/admin/sign-in"
    end

    test "Jacob sets a password from the mailed link, signs in, and can sign out", %{conn: conn} do
      {:ok, request, _html} = live(conn, ~p"/admin/reset-password")

      request
      |> form("#reset-request-form", %{email: admin_email()})
      |> render_submit()

      token = reset_token_from_mailbox()

      {:ok, reset, _html} = live(conn, ~p"/admin/reset-password/#{token}")

      form =
        form(reset, "#reset-form", %{
          "identity" => %{
            "password" => @password,
            "password_confirmation" => @password
          }
        })

      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = render_submit(form)

      {:ok, sign_in, _html} = live(conn, ~p"/admin/sign-in")

      conn =
        sign_in
        |> form("#sign-in-form", admin: %{email: admin_email(), password: @password})
        |> submit_form(conn)

      assert redirected_to(conn) == "/admin"

      conn = get(recycle(conn), ~p"/admin")
      {:ok, overview, html} = live(conn, ~p"/admin")
      assert html =~ "Spend"
      assert has_element?(overview, "a[href='/spend']")
      assert has_element?(overview, "a[href='/admin/experiments']")
      assert has_element?(overview, "a[href='/admin/media']")
      assert has_element?(overview, "a[href='/admin/rooms']")
      assert has_element?(overview, "a[href='/admin/timing']")
      assert has_element?(overview, "a[href='/calibration.json']")
      assert has_element?(overview, "a[href='/calibration.jsonl']")

      conn = delete(recycle(conn), ~p"/admin/sign-out")
      assert redirected_to(conn) == "/admin/sign-in"
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(recycle(conn), ~p"/spend")
    end

    test "a wrong password does not sign in", %{conn: conn} do
      identity_with_password(@password)

      {:ok, sign_in, _html} = live(conn, ~p"/admin/sign-in")

      html =
        sign_in
        |> form("#sign-in-form", admin: %{email: admin_email(), password: "not-the-password-1"})
        |> render_submit()

      assert html =~ "Invalid email or password"
    end

    test "a reset request for an unknown email still says the link is on its way", %{conn: conn} do
      {:ok, request, _html} = live(conn, ~p"/admin/reset-password")

      html =
        request
        |> form("#reset-request-form", %{email: "stranger@example.com"})
        |> render_submit()

      assert html =~ "If that email is the operator, a link is on its way"
      refute_email_sent()
    end

    test "signing in keeps the device token that finds a Seat", %{conn: conn} do
      identity_with_password(@password)
      conn = Plug.Test.init_test_session(conn, %{"device_token" => "keep-this-device"})

      {:ok, sign_in, _html} = live(conn, ~p"/admin/sign-in")

      conn =
        sign_in
        |> form("#sign-in-form", admin: %{email: admin_email(), password: @password})
        |> submit_form(conn)

      assert redirected_to(conn) == "/admin"
      assert get_session(conn, "device_token") == "keep-this-device"
    end
  end

  describe "operator routes once signed in" do
    setup %{conn: conn} do
      %{conn: log_in_admin(conn)}
    end

    test "spend and calibration exports are reachable", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/spend")
      assert has_element?(view, "[data-role=spend-heading]")
      assert html =~ ~r/<meta[^>]*robots[^>]*noindex/i

      conn = get(conn, ~p"/calibration.json")
      assert response(conn, 200)
      assert response_content_type(conn, :json) =~ "application/json"
    end

    test "ordinary joining and Chronicle reading stay account-free" do
      slug = open_room()
      {:ok, mara} = Thereish.Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Thereish.Rooms.join(slug, "Jacob", device_token())
      :ok = Thereish.Rooms.give(slug, mara.id, "setting one")
      :ok = Thereish.Rooms.give(slug, jacob.id, "setting two")
      await_phase(slug, :bridging)

      {:ok, _front, html} = live(build_conn(), ~p"/")
      assert html =~ "Thereish"
      refute html =~ "Sign in"

      {:ok, room, html} = live(build_conn(), ~p"/r/#{slug}")
      refute html =~ "Operator sign-in"
      assert has_element?(room, "form")

      {:ok, chronicle, html} = live(build_conn(), ~p"/r/#{slug}/chronicle")
      refute html =~ "Export Markdown"
      refute html =~ "Export Calibration"
      refute has_element?(chronicle, "[data-role=experiment-card]")
      refute has_element?(chronicle, "[data-role=chronicle-spend]")
    end
  end

  describe "DeviceToken.from_session/1" do
    test "still finds a token after an admin session is opened", %{conn: conn} do
      conn = conn |> log_in_admin() |> get(~p"/admin")
      session = Plug.Conn.get_session(conn)
      assert is_binary(DeviceToken.from_session(session))
    end
  end

  defp reset_token_from_mailbox do
    assert_email_sent(fn email ->
      assert email.to == [{"", admin_email()}]
      assert email.subject =~ "password"
      refute email.text_body =~ @password

      case Regex.run(~r{/admin/reset-password/([^\s]+)}, email.text_body) do
        [_, token] -> token
        _ -> flunk("reset email had no token URL:\n#{email.text_body}")
      end
    end)
  end
end
