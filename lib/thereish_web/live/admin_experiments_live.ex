defmodule ThereishWeb.AdminExperimentsLive do
  @moduledoc """
  Experiment readout and unblinding, moved off the ordinary Chronicle (ticket 09).
  """
  use ThereishWeb, :live_view

  import ThereishWeb.AdminComponents

  alias Thereish.Experiments

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Experiments")
     |> assign(:robots, "noindex")
     |> load_experiments()}
  end

  @impl true
  def handle_event("unblind_experiment", params, socket) do
    room_id = params["room-id"]
    experiment_id = params["experiment-id"]

    case Experiments.unblind(room_id, experiment_id, %{
           unblinded_at: DateTime.utc_now(),
           notes: "Deliberate unblinding from admin"
         }) do
      {:ok, _} ->
        {:noreply, load_experiments(socket)}

      {:error, :sample_incomplete} ->
        required = Experiments.progress(room_id, experiment_id).required

        {:noreply,
         put_flash(
           socket,
           :error,
           "Unblinding waits until #{required} completed Pages are recorded."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not unblind this experiment.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main class="mx-auto flex min-h-screen max-w-xl flex-col gap-8 px-4 py-8">
      <header class="flex items-center justify-between border-b border-base-300 pb-4">
        <h1 class="text-3xl font-bold tracking-tight">Experiments</h1>
        <.link navigate={~p"/admin"} class="text-sm underline opacity-70 hover:opacity-100">
          ← Admin
        </.link>
      </header>

      <p :if={@rooms == []} class="text-sm opacity-70">No experiment Pages recorded yet.</p>

      <.experiment_card
        :for={entry <- @rooms}
        room={entry.room}
        unblinded={entry.unblinded?}
        progress={entry.progress}
        readout={entry.readout || %{experiment: entry.experiment}}
      />
    </main>
    """
  end

  defp load_experiments(socket), do: assign(socket, :rooms, Experiments.overview())
end
