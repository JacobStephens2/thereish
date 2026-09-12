defmodule ThereishWeb.AdminExperimentsLive do
  @moduledoc """
  Experiment readout and unblinding, moved off the ordinary Chronicle (ticket 09).
  """
  use ThereishWeb, :live_view

  import ThereishWeb.AdminComponents

  alias Thereish.Chronicle

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Experiments")
     |> assign(:robots, "noindex")
     |> load_experiments()}
  end

  @impl true
  def handle_event("unblind_experiment", %{"room-id" => room_id}, socket) do
    experiment_id = Chronicle.active_experiment_id(room_id)

    {:ok, _} =
      Chronicle.record_experiment_unblinding(room_id, %{
        experiment_id: experiment_id,
        unblinded_at: DateTime.utc_now(),
        notes: "Deliberate unblinding from admin"
      })

    {:noreply, load_experiments(socket)}
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
        unblinded={entry.unblinded}
        readout={entry.readout}
      />
    </main>
    """
  end

  defp load_experiments(socket) do
    rooms =
      Enum.map(Chronicle.experiment_rooms(), fn room ->
        experiment_id = Chronicle.active_experiment_id(room.id)

        %{
          room: room,
          unblinded: Chronicle.experiment_unblinded?(room.id, experiment_id),
          readout: Chronicle.experiment_readout(room.id, experiment_id)
        }
      end)

    assign(socket, :rooms, rooms)
  end
end
