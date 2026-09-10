defmodule Thereish.Foley.ScoreQueue do
  @moduledoc """
  Application-wide single-worker queue for Foley score requests.

  Mureka allows at most one concurrent job per key. Score requests go through
  this queue so that at most one score job runs at any time across all Rooms.
  A Page has at most one score in flight; duplicate enqueue requests for the same
  Page reference while in-flight or queued are ignored.
  """

  use GenServer

  alias Thereish.Steward

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Enqueues a score request for `room` with `page_ref` and `gives`.
  Delivers `{:scored, page_ref, result}` to `room` when complete.
  """
  def enqueue(room, page_ref, gives, opts \\ []) do
    GenServer.call(__MODULE__, {:enqueue, room, page_ref, gives, opts})
  end

  @doc """
  Resets the queue and current job (used in tests).
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    {:ok, %{queue: :queue.new(), current_job: nil, in_flight: MapSet.new()}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    if state.current_job && state.current_job.task do
      Task.shutdown(state.current_job.task, :brutal_kill)
    end

    if state.current_job && state.current_job[:room_ref] do
      Process.demonitor(state.current_job.room_ref, [:flush])
    end

    state.queue
    |> :queue.to_list()
    |> Enum.each(fn job ->
      if job[:room_ref], do: Process.demonitor(job.room_ref, [:flush])
    end)

    {:reply, :ok, %{queue: :queue.new(), current_job: nil, in_flight: MapSet.new()}}
  end

  @impl true
  def handle_call({:enqueue, room, page_ref, gives, opts}, _from, state) do
    if MapSet.member?(state.in_flight, page_ref) or not room_alive?(room) do
      {:reply, :ok, state}
    else
      room_ref = monitor_room(room)
      job = %{room: room, room_ref: room_ref, page_ref: page_ref, gives: gives, opts: opts}
      in_flight = MapSet.put(state.in_flight, page_ref)

      state =
        if state.current_job == nil do
          start_job(job, %{state | in_flight: in_flight})
        else
          %{state | queue: :queue.in(job, state.queue), in_flight: in_flight}
        end

      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({ref, result}, %{current_job: %{task: %Task{ref: ref}}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_current_job(state, result)}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current_job: %{task: %Task{ref: ref}}} = state
      ) do
    {:noreply, finish_current_job(state, {:error, reason})}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {remaining_jobs, dropped_jobs} =
      state.queue
      |> :queue.to_list()
      |> Enum.split_with(fn job -> job.room_ref != ref and room_alive?(job.room) end)

    Enum.each(dropped_jobs, fn job ->
      if job[:room_ref] && job.room_ref != ref do
        Process.demonitor(job.room_ref, [:flush])
      end
    end)

    in_flight =
      Enum.reduce(dropped_jobs, state.in_flight, fn job, acc ->
        MapSet.delete(acc, job.page_ref)
      end)

    state = %{state | queue: :queue.from_list(remaining_jobs), in_flight: in_flight}

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp finish_current_job(state, result) do
    if state.current_job[:room_ref] do
      Process.demonitor(state.current_job.room_ref, [:flush])
    end

    if room_alive?(state.current_job.room) do
      send(state.current_job.room, {:scored, state.current_job.page_ref, result})
    end

    in_flight = MapSet.delete(state.in_flight, state.current_job.page_ref)
    state = %{state | current_job: nil, in_flight: in_flight}
    maybe_start_next_job(state)
  end

  defp start_job(job, state) do
    task =
      Task.Supervisor.async_nolink(Thereish.Steward.Tasks, fn ->
        if on_start = Keyword.get(job.opts, :on_start) do
          on_start.()
        end

        on_playable =
          case Keyword.get(job.opts, :on_playable) do
            cb when is_function(cb, 1) ->
              cb

            _ ->
              fn playable ->
                send(job.room, {:playable, job.page_ref, {:ok, playable}})
              end
          end

        opts = Keyword.put(job.opts, :on_playable, on_playable)
        Steward.score(job.gives, opts)
      end)

    %{state | current_job: Map.put(job, :task, task)}
  end

  defp maybe_start_next_job(state) do
    case :queue.out(state.queue) do
      {{:value, next_job}, remaining} ->
        state = %{state | queue: remaining}

        if room_alive?(next_job.room) do
          start_job(next_job, state)
        else
          if next_job[:room_ref], do: Process.demonitor(next_job.room_ref, [:flush])
          in_flight = MapSet.delete(state.in_flight, next_job.page_ref)
          maybe_start_next_job(%{state | in_flight: in_flight})
        end

      {:empty, _} ->
        state
    end
  end

  defp monitor_room(pid) when is_pid(pid), do: Process.monitor(pid)
  defp monitor_room(atom) when is_atom(atom), do: Process.monitor(atom)
  defp monitor_room(_), do: nil

  defp room_alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp room_alive?(atom) when is_atom(atom), do: Process.whereis(atom) != nil
  defp room_alive?(_), do: true
end
