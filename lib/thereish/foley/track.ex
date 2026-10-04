defmodule Thereish.Foley.Track do
  @moduledoc """
  The Track a Page keeps: what Foley scored for it, its title, or why it failed.

  One shape from the moment Foley's result lands to every reader. A landed
  Track has a path and, once the Scribe answers, a title. A Track that failed
  or never finished has a `failure` and no path. Either way `meta` is the Foley
  provenance (provider, model, cost, latency, title cost), always with string
  keys, so a record built in the Room equals the same record read back.

  A Page kept its Track only when `kept?/1` says so.

  It is also the `Ecto.Type` a Chronicle Page stores its Track with. A row is
  flat: the provenance beside the path, title and failure. Load reads every
  row stored before there was a type: string keys, atom keys, or both.
  """
  use Ecto.Type

  alias Thereish.Foley.Row

  alias Thereish.Steward

  defstruct [:path, :title, :failure, meta: %{}]

  @type t :: %__MODULE__{
          path: String.t() | nil,
          title: String.t() | nil,
          failure: String.t() | nil,
          meta: %{String.t() => term()}
        }

  @fields ["path", "title", "failure"]

  @doc """
  The record of a Track that landed: a Steward score result or a TrackCache
  hit, with its title and the title's cost when a title is known.
  """
  @spec landed(map(), String.t() | nil, map() | nil) :: t()
  def landed(%{path: path} = result, title, title_meta) do
    meta = result |> Map.get(:meta) |> Row.string_keys() |> Map.drop(@fields)
    titled(%__MODULE__{path: path, meta: meta}, title, title_meta)
  end

  @doc "Adds a title, and its cost, that arrived after the Track."
  @spec titled(t(), String.t() | nil, map() | nil) :: t()
  def titled(%__MODULE__{} = track, nil, _title_meta), do: track

  def titled(%__MODULE__{meta: meta} = track, title, title_meta) do
    cost = Row.string_keys(title_meta)["cost_usd"] || 0.0
    %{track | title: title, meta: Map.put(meta, "title_cost_usd", cost)}
  end

  @doc """
  The record of a Track that failed or never finished. `reason` is kept as a
  string, beside the provenance of the Foley role that was asked.
  """
  @spec failed(term()) :: t()
  def failed(reason) do
    {failure, meta} = reason |> Steward.score_failure() |> Row.string_keys() |> Map.pop("failure")
    %__MODULE__{failure: failure, meta: meta}
  end

  @doc "Whether this is a Track the Page kept: it has a path and did not fail."
  @spec kept?(t() | nil) :: boolean()
  def kept?(%__MODULE__{path: path, failure: nil}), do: is_binary(path) and path != ""
  def kept?(_other), do: false

  @impl Ecto.Type
  def type, do: :map

  @impl Ecto.Type
  def cast(%__MODULE__{} = track), do: {:ok, track}
  def cast(_other), do: :error

  @impl Ecto.Type
  def dump(%__MODULE__{path: path, title: title, failure: failure, meta: meta}) do
    {:ok, Row.dump(%{"path" => path, "title" => title, "failure" => failure}, meta)}
  end

  def dump(_other), do: :error

  # An empty row holds no record.
  @impl Ecto.Type
  def load(row) when row == %{}, do: {:ok, nil}

  def load(row) when is_map(row) do
    {own, meta} = Row.load(row, @fields)

    {:ok,
     %__MODULE__{path: own["path"], title: own["title"], failure: own["failure"], meta: meta}}
  end

  def load(_other), do: :error
end
