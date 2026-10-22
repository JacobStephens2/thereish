defmodule ThereishWeb.AdminResetPasswordLive do
  @moduledoc """
  Initial password setup and later reset for the operator identity (ticket 09).
  """
  use ThereishWeb, :live_view

  alias Thereish.Admin

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if identity = Admin.get_identity_by_reset_password_token(token) do
      {:ok,
       socket
       |> assign(:page_title, "Set password")
       |> assign(:robots, "noindex")
       |> assign(:token, token)
       |> assign(:form, to_form(Admin.change_password(identity), as: :identity))}
    else
      {:ok, invalid_reset_link(socket)}
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Set up or reset password")
     |> assign(:robots, "noindex")
     |> assign(:sent, false)
     |> assign(:form, to_form(%{"email" => ""}))}
  end

  @impl true
  def handle_event("send", %{"email" => email}, socket) do
    if identity = Admin.get_identity_by_email(email) do
      Admin.deliver_reset_password_instructions(
        identity,
        &url(~p"/admin/reset-password/#{&1}")
      )
    end

    {:noreply,
     socket
     |> put_flash(:info, "If that email is the operator, a link is on its way.")
     |> assign(:sent, true)}
  end

  def handle_event("reset", %{"identity" => params}, socket) do
    case Admin.get_identity_by_reset_password_token(socket.assigns.token) do
      nil ->
        {:noreply, invalid_reset_link(socket)}

      identity ->
        case Admin.reset_password(identity, params) do
          {:ok, _identity} ->
            {:noreply,
             socket
             |> put_flash(:info, "Password set. Sign in.")
             |> redirect(to: ~p"/admin/sign-in")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset, as: :identity))}
        end
    end
  end

  defp invalid_reset_link(socket) do
    socket
    |> put_flash(:error, "Reset link is invalid or it has expired.")
    |> redirect(to: ~p"/admin/reset-password")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main class="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-8 px-6 py-12">
      <%= if assigns[:token] do %>
        <h1 class="text-2xl font-semibold">Set password</h1>
        <.form
          for={@form}
          id="reset-form"
          phx-submit="reset"
          class="flex flex-col gap-3"
        >
          <.input
            field={@form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm password"
            autocomplete="new-password"
            required
          />
          <.button variant="primary">Save password</.button>
        </.form>
      <% else %>
        <h1 class="text-2xl font-semibold">Set up or reset password</h1>
        <p :if={@sent} data-role="reset-sent" class="text-sm">
          If that email is the operator, a link is on its way.
        </p>
        <.form
          for={@form}
          id="reset-request-form"
          phx-submit="send"
          class="flex flex-col gap-3"
        >
          <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
          <.button variant="primary">Send link</.button>
        </.form>
        <.link navigate={~p"/admin/sign-in"} class="text-sm underline opacity-70 hover:opacity-100">
          Back to sign-in
        </.link>
      <% end %>
    </main>
    """
  end
end
