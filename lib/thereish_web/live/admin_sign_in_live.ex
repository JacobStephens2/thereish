defmodule ThereishWeb.AdminSignInLive do
  @moduledoc """
  Email/password sign-in for the operator identity (ticket 09).
  """
  use ThereishWeb, :live_view

  alias Thereish.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign in")
     |> assign(:robots, "noindex")
     |> assign(:trigger_submit, false)
     |> assign(:form, to_form(%{"email" => "", "password" => ""}, as: :admin))}
  end

  @impl true
  def handle_event("submit", %{"admin" => params}, socket) do
    %{"email" => email, "password" => password} = params

    if Admin.get_identity_by_email_and_password(email, password) do
      {:noreply, assign(socket, trigger_submit: true, form: to_form(params, as: :admin))}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Invalid email or password")
       |> assign(:form, to_form(params, as: :admin))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main class="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-8 px-6 py-12">
      <h1 class="text-2xl font-semibold">Operator sign-in</h1>

      <.form
        for={@form}
        id="sign-in-form"
        action={~p"/admin/sign-in"}
        method="post"
        phx-submit="submit"
        phx-trigger-action={@trigger_submit}
        class="flex flex-col gap-3"
      >
        <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="current-password"
          required
        />
        <.button variant="primary">Sign in</.button>
      </.form>

      <.link
        navigate={~p"/admin/reset-password"}
        class="text-sm underline opacity-70 hover:opacity-100"
      >
        Set up or reset password
      </.link>
    </main>
    """
  end
end
