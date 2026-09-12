defmodule ThereishWeb.AdminSessionController do
  @moduledoc """
  Writes and clears the operator session. LiveView cannot set the cookie.
  """
  use ThereishWeb, :controller

  alias Thereish.Admin
  alias ThereishWeb.AdminAuth

  def create(conn, %{"admin" => %{"email" => email, "password" => password}}) do
    if identity = Admin.get_identity_by_email_and_password(email, password) do
      token = Admin.generate_session_token(identity)
      return_to = AdminAuth.signed_in_path(conn)

      conn
      |> AdminAuth.renew_session(["device_token", "remote_ip"])
      |> put_session("admin_token", token)
      |> redirect(to: return_to)
    else
      conn
      |> put_flash(:error, "Invalid email or password")
      |> redirect(to: ~p"/admin/sign-in")
    end
  end

  def delete(conn, _params) do
    if token = get_session(conn, "admin_token") do
      Admin.delete_session_token(token)
    end

    conn
    |> AdminAuth.renew_session(["device_token", "remote_ip"])
    |> redirect(to: ~p"/admin/sign-in")
  end
end
