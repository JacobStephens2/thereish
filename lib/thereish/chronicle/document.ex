defmodule Thereish.Chronicle.Document do
  @moduledoc """
  A Page's Document: the Page as it was written at the table. Its opening
  Bookends and where each came from, the Gives, the Author's meta, and the Full
  table rule it was written under.

  One shape from the Game to every reader. The Game builds one when the
  Author's Bookends land, `Thereish.Chronicle.Entry` carries it, and the
  Chronicle Page keeps it as JSONB (ADR-0003).

  - `bookends` are the first Attempt's Bookends.
  - `origins` say where each of them came from (`Thereish.Bookends.origin/0`).
  - `gives` are the Gives as the Game held them, Seat id to text.
  - `meta` is the Author's meta, opaque.
  - `full_table` is the rule the Page was written under, nil for a Page from
    before the rule.
  - `give` is legacy: the one Give a Page kept before there were Give rows.
  - `identifier` is legacy: the id the Author gave a Page written ahead of
    play, which Bait-era experiment outcomes name.

  It is also the `Ecto.Type` of the Chronicle Page's `document` column. Load
  reads every row the Chronicle has stored: string or atom keys, the legacy
  `bookend_gives` beside `bookend_origins`, and `id` as `identifier`. Dump
  writes only a Document, with the keys a Page written today stores.
  """
  use Ecto.Type

  alias Thereish.Bookends

  defstruct [:full_table, :give, :identifier, bookends: [], origins: [], gives: %{}, meta: %{}]

  @type t :: %__MODULE__{
          bookends: [String.t()],
          origins: [Bookends.origin()],
          gives: %{String.t() => String.t()},
          meta: map(),
          full_table: boolean() | nil,
          give: String.t() | nil,
          identifier: String.t() | nil
        }

  @impl Ecto.Type
  def type, do: :map

  @impl Ecto.Type
  def cast(document), do: load(document)

  @impl Ecto.Type
  def dump(%__MODULE__{} = document) do
    row = %{
      "bookends" => document.bookends,
      "bookend_origins" => document.origins,
      "gives" => document.gives,
      "meta" => document.meta,
      "full_table" => document.full_table
    }

    {:ok,
     row
     |> put_set("give", document.give)
     |> put_set("id", document.identifier)}
  end

  def dump(_other), do: :error

  @impl Ecto.Type
  def load(%__MODULE__{} = document), do: {:ok, document}

  def load(row) when is_map(row) do
    {:ok,
     %__MODULE__{
       bookends: field(row, :bookends) || [],
       origins:
         Enum.map(field(row, :bookend_origins) || field(row, :bookend_gives) || [], &origin/1),
       gives: field(row, :gives) || %{},
       meta: field(row, :meta) || %{},
       full_table: if(is_boolean(field(row, :full_table)), do: field(row, :full_table)),
       give: field(row, :give),
       identifier: field(row, :id)
     }}
  end

  def load(_other), do: :error

  defp origin(origin) do
    %{
      word: field(origin, :word),
      seat_id: field(origin, :seat_id),
      seat_name: field(origin, :seat_name),
      give: field(origin, :give)
    }
  end

  # A stored key is a string; one written before the Page was a Document may be
  # an atom. `false` is a value, so this does not fall through on it.
  defp field(map, key) do
    case Map.fetch(map, Atom.to_string(key)) do
      {:ok, value} when not is_nil(value) -> value
      _missing -> Map.get(map, key)
    end
  end

  defp put_set(row, _key, nil), do: row
  defp put_set(row, key, value), do: Map.put(row, key, value)
end
