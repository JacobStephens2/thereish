defmodule Thereish.Foley.Vamp do
  @moduledoc """
  The Vamp a Page keeps: the short loop Foley played while its Track was being
  scored.

  One shape from the moment Foley's result lands to every reader. `meta` is the
  Foley provenance (provider, model, cost, latency), always with string keys,
  so a record built in the Room equals the same record read back. A Vamp that
  failed records nothing, so there is no failed Vamp.

  It is also the `Ecto.Type` a Chronicle Page stores its Vamp with. A row is
  flat: the provenance beside the path, duration, format and loop. Load reads
  every row stored before there was a type: string keys, atom keys, or both.
  """
  use Ecto.Type

  defstruct [:path, :duration, :format, :loop, meta: %{}]

  @type t :: %__MODULE__{
          path: String.t() | nil,
          duration: number() | nil,
          format: String.t() | nil,
          loop: boolean() | nil,
          meta: %{String.t() => term()}
        }

  @fields ["path", "duration", "format", "loop"]

  @doc "The record of a Steward Vamp result. It loops unless the result says it does not."
  @spec landed(map()) :: t()
  def landed(%{path: path} = result) do
    format = Map.get(result, :format)

    %__MODULE__{
      path: path,
      duration: Map.get(result, :duration),
      format: if(is_nil(format), do: nil, else: to_string(format)),
      loop: Map.get(result, :loop, true),
      meta: result |> Map.get(:meta) |> provenance() |> Map.drop(@fields)
    }
  end

  @doc "Whether this is a Vamp the Page kept: it has a path."
  @spec kept?(t() | nil) :: boolean()
  def kept?(%__MODULE__{path: path}), do: is_binary(path) and path != ""
  def kept?(_other), do: false

  @impl Ecto.Type
  def type, do: :map

  @impl Ecto.Type
  def cast(%__MODULE__{} = vamp), do: {:ok, vamp}
  def cast(_other), do: :error

  @impl Ecto.Type
  def dump(%__MODULE__{} = vamp) do
    own =
      for {key, value} <- [
            {"path", vamp.path},
            {"duration", vamp.duration},
            {"format", vamp.format},
            {"loop", vamp.loop}
          ],
          not is_nil(value),
          into: %{},
          do: {key, value}

    {:ok, vamp.meta |> Map.drop(@fields) |> Map.merge(own)}
  end

  def dump(_other), do: :error

  @impl Ecto.Type
  def load(row) when is_map(row) do
    {own, meta} = row |> provenance() |> Map.split(@fields)

    {:ok,
     %__MODULE__{
       path: own["path"],
       duration: own["duration"],
       format: own["format"],
       loop: own["loop"],
       meta: meta
     }}
  end

  def load(_other), do: :error

  # A map with string keys. Where a row has a key both ways, the string wins.
  defp provenance(nil), do: %{}

  defp provenance(map) when is_map(map) do
    {strings, atoms} = Enum.split_with(map, fn {key, _value} -> is_binary(key) end)
    Map.merge(Map.new(atoms, fn {key, value} -> {to_string(key), value} end), Map.new(strings))
  end
end

# A Room's snapshot carries the Vamp as JSON in the same flat shape it is stored in.
defimpl Jason.Encoder, for: Thereish.Foley.Vamp do
  def encode(vamp, opts) do
    {:ok, row} = Thereish.Foley.Vamp.dump(vamp)
    Jason.Encode.map(row, opts)
  end
end
