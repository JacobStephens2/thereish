defmodule ThereishWeb.AdminAuth do
  @moduledoc """
  Session plug and LiveView mount for the operator identity.
  """
  use ThereishWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Thereish.Admin

  def fetch_current_admin(conn, _opts) do
    admin =
      case get_session(conn, "admin_token") do
        token when is_binary(token) -> Admin.get_identity_by_session_token(token)
        _ -> nil
      end

    assign(conn, :current_admin, admin)
  end

  def require_authenticated_admin(conn, _opts) do
    if conn.assigns[:current_admin] do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> put_flash(:error, "Sign in to continue.")
      |> redirect(to: ~p"/admin/sign-in")
      |> halt()
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    socket = assign_admin(socket, session)

    if socket.assigns.current_admin do
      {:cont, recheck_admin_on_event(socket, session)}
    else
      {:halt, deny_admin(socket)}
    end
  end

  def on_mount(:redirect_if_admin, _params, session, socket) do
    socket = assign_admin(socket, session)

    if socket.assigns.current_admin do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/admin")}
    else
      {:cont, socket}
    end
  end

  def signed_in_path(conn) do
    get_session(conn, "admin_return_to") || ~p"/admin"
  end

  def renew_session(conn, keep) do
    preserved = Map.new(keep, fn key -> {to_string(key), get_session(conn, key)} end)

    conn =
      conn
      |> configure_session(renew: true)
      |> clear_session()

    Enum.reduce(preserved, conn, fn
      {_key, nil}, conn -> conn
      {key, value}, conn -> put_session(conn, key, value)
    end)
  end

  defp recheck_admin_on_event(socket, session) do
    Phoenix.LiveView.attach_hook(socket, :recheck_admin, :handle_event, fn _event,
                                                                           _params,
                                                                           socket ->
      socket = refresh_admin(socket, session)

      if socket.assigns.current_admin do
        {:cont, socket}
      else
        {:halt, deny_admin(socket)}
      end
    end)
  end

  defp deny_admin(socket) do
    socket
    |> Phoenix.LiveView.put_flash(:error, "Sign in to continue.")
    |> Phoenix.LiveView.redirect(to: ~p"/admin/sign-in")
  end

  defp assign_admin(socket, session) do
    Phoenix.Component.assign_new(socket, :current_admin, fn ->
      identity_from_session(session)
    end)
  end

  defp refresh_admin(socket, session) do
    Phoenix.Component.assign(socket, :current_admin, identity_from_session(session))
  end

  defp identity_from_session(%{"admin_token" => token}) do
    Admin.get_identity_by_session_token(token)
  end

  defp identity_from_session(_session), do: nil

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, "admin_return_to", current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
