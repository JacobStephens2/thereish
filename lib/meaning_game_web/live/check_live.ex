defmodule MeaningGameWeb.CheckLive do
  @moduledoc """
  The deployment's proof of life, and nothing game-shaped.

  It answers the three questions ticket 01 asks of the real deployment: does a
  page reach a phone, does the live socket come up through Apache's websocket
  upgrade, and is the browser in a secure context — the precondition for the
  Screen Wake Lock the stage view needs in ticket 02.

  The socket answer is the server's own: `connected?/1` is false in the dead
  render and true when mount runs again over the socket. The other two are facts
  only the browser knows, so the `BrowserReport` hook pushes them back.
  """
  use MeaningGameWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:connected, connected?(socket))
     |> assign(:secure_context, :unknown)
     |> assign(:wake_lock, :unknown)}
  end

  @impl true
  def handle_event("browser_reported", params, socket) do
    {:noreply,
     socket
     |> assign(:secure_context, answer(params["secure_context"]))
     |> assign(:wake_lock, answer(params["wake_lock"]))}
  end

  defp answer(true), do: :yes
  defp answer(false), do: :no
  defp answer(_), do: :unknown

  defp secure_context_label(:yes), do: "yes"
  defp secure_context_label(:no), do: "no"
  defp secure_context_label(:unknown), do: "unknown"

  defp wake_lock_label(:yes), do: "available"
  defp wake_lock_label(:no), do: "unavailable"
  defp wake_lock_label(:unknown), do: "unknown"

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="check"
      phx-hook=".BrowserReport"
      class="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-8 px-6 py-12"
    >
      <h1 class="text-2xl font-semibold">Meaning Game</h1>

      <dl class="flex flex-col gap-4 text-lg">
        <div>
          <dt class="sr-only">Live socket</dt>
          <dd data-check="socket">
            {if @connected, do: "Socket connected", else: "Socket not connected"}
          </dd>
        </div>
        <div>
          <dt class="sr-only">Secure context</dt>
          <dd data-check="secure-context">
            Secure context: {secure_context_label(@secure_context)}
          </dd>
        </div>
        <div>
          <dt class="sr-only">Screen Wake Lock</dt>
          <dd data-check="wake-lock">
            Screen Wake Lock: {wake_lock_label(@wake_lock)}
          </dd>
        </div>
      </dl>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".BrowserReport">
        export default {
          mounted() {
            this.pushEvent("browser_reported", {
              secure_context: window.isSecureContext === true,
              wake_lock: "wakeLock" in navigator
            })
          }
        }
      </script>
    </main>
    """
  end
end
