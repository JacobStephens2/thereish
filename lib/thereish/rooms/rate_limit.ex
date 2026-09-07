defmodule Thereish.Rooms.RateLimit do
  @moduledoc """
  In-memory sliding hour rate limiter for Room creation.

  Room creation is limited per device token and per remote address, in memory,
  using a small ETS counter with a sliding hour. Over the limit creation is refused
  with `{:error, :rate_limited}` and creates nothing. Limits are configuration.
  A restart forgets the counter.
  """
  use GenServer

  @table :room_creation_rate_limit

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks and records a creation attempt for `device_token` and `remote_address`.
  Returns `:ok` if within limits, or `{:error, :rate_limited}` if the limit was reached.
  """
  def hit(device_token, remote_address, now_seconds \\ nil) do
    now = now_seconds || System.system_time(:second)
    GenServer.call(__MODULE__, {:hit, device_token, remote_address, now})
  end

  @doc """
  Resets the rate limit table (used in tests).
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :duplicate_bag, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:hit, device_token, remote_address, now}, _from, state) do
    config = Application.get_env(:thereish, :room_creation_rate_limit, [])
    per_device = Keyword.get(config, :per_device, 10)
    per_address = Keyword.get(config, :per_address, 30)
    window = Keyword.get(config, :window_seconds, 3600)
    cutoff = now - window

    # Prune old records
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])

    device_key = if present?(device_token), do: {:device, to_string(device_token)}
    address_key = if present?(remote_address), do: {:address, normalise_address(remote_address)}

    device_count = count_key(device_key, cutoff)
    address_count = count_key(address_key, cutoff)

    cond do
      device_key != nil and device_count + 1 >= per_device ->
        {:reply, {:error, :rate_limited}, state}

      address_key != nil and address_count + 1 >= per_address ->
        {:reply, {:error, :rate_limited}, state}

      true ->
        if device_key, do: :ets.insert(@table, {device_key, now})
        if address_key, do: :ets.insert(@table, {address_key, now})
        {:reply, :ok, state}
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp normalise_address(ip) when is_tuple(ip), do: :inet.ntoa(ip) |> to_string()
  defp normalise_address(ip) when is_binary(ip), do: ip
  defp normalise_address(other), do: to_string(other)

  defp count_key(nil, _cutoff), do: 0

  defp count_key(key, cutoff) do
    :ets.select_count(@table, [{{key, :"$1"}, [{:>=, :"$1", cutoff}], [true]}])
  end
end
