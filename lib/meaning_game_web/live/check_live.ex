defmodule MeaningGameWeb.CheckLive do
  @moduledoc """
  The deployment's proof of life, and nothing game-shaped.

  It answers the three questions ticket 01 asks of the real deployment: does a
  page reach a phone, does the live socket come up through Apache's websocket
  upgrade, and is the browser in a secure context — the precondition for the
  Screen Wake Lock `MeaningGameWeb.StageLive` takes.

  The socket answer is the server's own: `connected?/1` is false in the dead
  render and true when mount runs again over the socket. The other facts are
  ones only the browser knows, so the `BrowserReport` hook pushes them back.

  The transport is reported because `connected?/1` cannot tell a working
  websocket upgrade from LiveView's silent long-poll fallback, and the fallback
  is exactly what a missing `upgrade=websocket` in the Apache vhost produces —
  a working page hiding a broken deployment. See `deploy/apache/proxy.conf`.
  """
  use MeaningGameWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:connected, connected?(socket))
     |> assign(:transport, nil)
     |> assign(:secure_context, :unknown)
     |> assign(:wake_lock, :unknown)}
  end

  @impl true
  def handle_event("browser_reported", params, socket) do
    {:noreply,
     socket
     |> assign(:transport, transport(params["transport"]))
     |> assign(:secure_context, reported(params["secure_context"]))
     |> assign(:wake_lock, reported(params["wake_lock"]))}
  end

  # Only the two transports LiveView actually uses are named, so a surprise
  # value shows up as a surprise rather than being rendered as if expected.
  defp transport("WebSocket"), do: "WebSocket"
  defp transport("LongPoll"), do: "LongPoll (the websocket upgrade is not working)"
  defp transport(other) when is_binary(other), do: other
  defp transport(_), do: nil

  # Tri-state, not a boolean: "the browser has not told us yet" is a distinct
  # answer from "no", and only one of the two is a problem.
  defp reported(true), do: :yes
  defp reported(false), do: :no
  defp reported(_), do: :unknown

  defp label(:yes, yes_word, _no_word), do: yes_word
  defp label(:no, _yes_word, no_word), do: no_word
  defp label(:unknown, _yes_word, _no_word), do: "unknown"

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
          <dt class="sr-only">Transport</dt>
          <dd data-check="transport">
            Transport: {@transport || "unknown"}
          </dd>
        </div>
        <div>
          <dt class="sr-only">Secure context</dt>
          <dd data-check="secure-context">
            Secure context: {label(@secure_context, "yes", "no")}
          </dd>
        </div>
        <div>
          <dt class="sr-only">Screen Wake Lock</dt>
          <dd data-check="wake-lock">
            Screen Wake Lock: {label(@wake_lock, "available", "unavailable")}
          </dd>
        </div>
      </dl>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".BrowserReport">
        export default {
          mounted() {
            const transport = this.liveSocket.getSocket().transport
            this.pushEvent("browser_reported", {
              transport: transport && transport.name,
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
