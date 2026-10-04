defmodule Thereish.Foley.Row do
  @moduledoc """
  The flat row a Page's `Thereish.Foley.Track` and `Thereish.Foley.Vamp` are
  stored as: the Foley provenance beside the record's own fields, with string
  keys. Both types dump, load and encode through it.
  """

  @doc """
  A map with string keys, from one with string keys, atom keys or both. Where
  a key is there both ways, the string one wins. nil is the empty map.
  """
  @spec string_keys(map() | nil) :: %{String.t() => term()}
  def string_keys(nil), do: %{}

  def string_keys(map) when is_map(map) do
    {strings, atoms} = Enum.split_with(map, fn {key, _value} -> is_binary(key) end)
    Map.merge(Map.new(atoms, fn {key, value} -> {to_string(key), value} end), Map.new(strings))
  end

  @doc "The row for a record's own fields and its `meta`, omitting any field that is nil."
  @spec dump(%{String.t() => term()}, %{String.t() => term()}) :: %{String.t() => term()}
  def dump(own, meta) do
    present = for {key, value} <- own, not is_nil(value), into: %{}, do: {key, value}
    meta |> Map.drop(Map.keys(own)) |> Map.merge(present)
  end

  @doc "Splits a stored row into the record's own `fields` and everything else, its meta."
  @spec load(map(), [String.t()]) :: {%{String.t() => term()}, %{String.t() => term()}}
  def load(row, fields), do: row |> string_keys() |> Map.split(fields)
end

# A Room's snapshot carries its Track and Vamp as JSON in the shape they are stored in.
defimpl Jason.Encoder, for: [Thereish.Foley.Track, Thereish.Foley.Vamp] do
  def encode(record, opts) do
    {:ok, row} = @for.dump(record)
    Jason.Encode.map(row, opts)
  end
end
