defmodule Keeper.Cache do
  @moduledoc """
  The consistency mechanism (design laws 1 and 11): key = kind + model + prompt version + normalized inputs,
  with both player orderings normalized to one key. ETS in memory; optionally persisted to PROTOTYPE-cache.json.
  """

  @table :keeper_cache
  @cache_file "PROTOTYPE-cache.json"

  def start(opts \\ []) do
    if :ets.whereis(@table) == :undefined, do: :ets.new(@table, [:named_table, :public, :set])

    if opts[:persist] do
      :ets.insert(@table, {:__persist__, true})
      load()
    end

    :ok
  end

  def key(model, prompt_version, kind, inputs), do: "#{kind}::#{model}::#{prompt_version}::" <> normalize(inputs)

  defp normalize(%{anchors: [a, b], words: words}) do
    norm = fn w -> w |> to_string() |> String.trim() |> String.downcase() end
    "#{norm.(a)}+#{norm.(b)}::" <> (words |> Enum.map(norm) |> Enum.sort() |> Enum.join("+"))
  end

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, v}] -> {:ok, v}
      [] -> :miss
    end
  end

  def put(key, value) do
    :ets.insert(@table, {key, value})
    if persist?(), do: save()
    value
  end

  def size, do: :ets.tab2list(@table) |> Enum.count(fn {k, _} -> k != :__persist__ end)

  defp persist?, do: :ets.lookup(@table, :__persist__) != []

  defp load do
    with {:ok, bin} <- File.read(@cache_file), {:ok, map} when is_map(map) <- Jason.decode(bin) do
      Enum.each(map, fn {k, v} -> :ets.insert(@table, {k, v}) end)
      IO.puts("cache: loaded #{map_size(map)} verdicts from #{@cache_file}")
    end

    :ok
  end

  defp save do
    map = :ets.tab2list(@table) |> Enum.reject(fn {k, _} -> k == :__persist__ end) |> Map.new()
    File.write!(@cache_file, Jason.encode!(map, pretty: true))
  end
end
