defmodule MeaningGame.Steward.Precedent do
  @moduledoc """
  The verdict cache that lives behind the Steward.

  When the couple plays the same Anchors and writes the same Bridges a month
  later, the game grades exactly as it graded the first time (design law 1). The
  cache stores exactly what the players were shown, and returns exactly that on a
  later hit, skipping the provider entirely (ADR-0006).

  Keyed by model, prompt version, and normalized inputs:
  - Every ordering of an Attempt's Bridges collapses to a single key: one Seat
    bridging "beacon" and the other "cairn" hits the same precedent as the
    reverse, and a table of four hits the same one whichever order the Seats
    were filled in.
  - Normalization is deterministic and documented: NFC unicode normalization,
    downcasing, and collapsing whitespace, so a trailing space or a capital
    letter does not fork a key.

  A row carries the two Bridges the Assayer named as furthest apart, because a
  cache hit has to replay the whole Verdict and those two words are the next
  Attempt's Anchors (ADR-0010). An overrule rewrites what the players argued
  about — the grade, the reasoning, the quip — and leaves the furthest pair
  alone: the couple ruled on how close the words were, not on which two of them
  were the far ones.

  Nothing silently rewrites a precedent: offline annotations never touch the
  cache. Only a joint player overrule (design law 3) will rewrite it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MeaningGame.Steward.Precedent
  alias MeaningGame.Repo

  @primary_key {:id, :binary_id, autogenerate: true}

  @type t :: %__MODULE__{}

  schema "precedents" do
    field :key, :string
    field :model, :string
    field :prompt_version, :string
    field :anchors, {:array, :string}
    field :bridges, {:array, :string}
    field :closeness, :integer
    field :reasoning, :string
    field :quip, :string
    field :forward, :integer
    field :reverse, :integer
    field :reasoning_reverse, :string
    field :furthest, {:array, :string}
    field :cost_usd, :decimal

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(precedent, attrs) do
    precedent
    |> cast(attrs, [
      :key,
      :model,
      :prompt_version,
      :anchors,
      :bridges,
      :closeness,
      :reasoning,
      :quip,
      :forward,
      :reverse,
      :reasoning_reverse,
      :furthest,
      :cost_usd
    ])
    |> validate_required([
      :key,
      :model,
      :prompt_version,
      :anchors,
      :bridges,
      :closeness,
      :reasoning,
      :quip
    ])
    |> unique_constraint(:key)
  end

  @doc """
  Deterministic cache key for a grading request.

  Keyed by model, prompt version, and normalized inputs. Both orderings of
  bridges and anchors sort to the same canonical representation.
  """
  @spec key(String.t(), String.t(), [String.t()], [String.t()]) :: String.t()
  def key(model, prompt_version, anchors, bridges) do
    {sorted_anchors, sorted_bridges} = canonical_inputs(anchors, bridges)
    hash(model, prompt_version, sorted_anchors, sorted_bridges)
  end

  @doc """
  Normalizes a word or phrase deterministically:
  1. Unicode NFC normalization
  2. Lowercase
  3. Trim and collapse internal whitespace
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(word) when is_binary(word) do
    word
    |> String.normalize(:nfc)
    |> String.downcase()
    |> String.split()
    |> Enum.join(" ")
  end

  @doc """
  Fetches a precedent by model, prompt version, anchors, and bridges.

  Returns `{:ok, verdict}` if found, or `:miss` if not.
  """
  @spec get(String.t(), String.t(), [String.t()], [String.t()]) ::
          {:ok, MeaningGame.Steward.verdict()} | :miss
  def get(model, prompt_version, anchors, bridges) do
    cache_key = key(model, prompt_version, anchors, bridges)

    case Repo.get_by(Precedent, key: cache_key) do
      nil -> :miss
      %Precedent{} = precedent -> {:ok, to_verdict(precedent)}
    end
  end

  @doc """
  Stores a verdict as precedent.

  If a precedent already exists for this key, it is left untouched: nothing
  silently rewrites a grade (ADR-0006).
  """
  @spec put(String.t(), String.t(), [String.t()], [String.t()], MeaningGame.Steward.verdict()) ::
          {:ok, Precedent.t()} | {:error, Ecto.Changeset.t()}
  def put(model, prompt_version, anchors, bridges, verdict) do
    {normalized_anchors, normalized_bridges} = canonical_inputs(anchors, bridges)
    cache_key = key(model, prompt_version, anchors, bridges)

    attrs = %{
      key: cache_key,
      model: model,
      prompt_version: prompt_version,
      anchors: normalized_anchors,
      bridges: normalized_bridges,
      closeness: verdict.closeness,
      reasoning: verdict.reasoning,
      quip: verdict.quip,
      forward: get_in(verdict, [:meta, :forward]),
      reverse: get_in(verdict, [:meta, :reverse]),
      reasoning_reverse: get_in(verdict, [:meta, :reasoning_reverse]),
      # Verbatim, and neither normalised nor sorted like the key's inputs: these
      # two words are about to be shown as the next Attempt's Anchors, so they
      # are kept as the players wrote them.
      furthest: Map.get(verdict, :furthest),
      cost_usd: get_in(verdict, [:meta, :cost_usd])
    }

    %Precedent{}
    |> changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :key)
  end

  @doc """
  Rewrites an existing precedent (or inserts a new one) with the couple's ruling.

  A joint player overrule is the only thing in the system that rewrites
  precedent (ADR-0006, design law 3).
  """
  @spec overrule(String.t(), String.t(), [String.t()], [String.t()], map()) ::
          {:ok, Precedent.t()} | {:error, Ecto.Changeset.t()}
  def overrule(model, prompt_version, anchors, bridges, ruling) do
    {normalized_anchors, normalized_bridges} = canonical_inputs(anchors, bridges)
    cache_key = key(model, prompt_version, anchors, bridges)

    attrs = %{
      key: cache_key,
      model: model,
      prompt_version: prompt_version,
      anchors: normalized_anchors,
      bridges: normalized_bridges,
      closeness: ruling.closeness,
      reasoning: ruling.reasoning,
      quip: Map.get(ruling, :quip, "House law.")
    }

    %Precedent{}
    |> changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:closeness, :reasoning, :quip, :updated_at]},
      conflict_target: :key
    )
  end

  defp canonical_inputs(anchors, bridges) do
    {
      anchors |> Enum.map(&normalize/1) |> Enum.sort(),
      bridges |> Enum.map(&normalize/1) |> Enum.sort()
    }
  end

  defp hash(model, prompt_version, anchors, bridges) do
    canonical = [model, prompt_version, anchors, bridges]

    :crypto.hash(:sha256, Jason.encode!(canonical))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Reconstitutes a Steward verdict from a stored Precedent row.
  """
  @spec to_verdict(Precedent.t()) :: MeaningGame.Steward.verdict()
  def to_verdict(%Precedent{} = precedent) do
    %{
      closeness: precedent.closeness,
      reasoning: precedent.reasoning,
      quip: precedent.quip,
      furthest: precedent.furthest,
      meta: %{
        model: precedent.model,
        prompt_version: precedent.prompt_version,
        cost_usd: precedent.cost_usd && Decimal.to_float(precedent.cost_usd),
        forward: precedent.forward,
        reverse: precedent.reverse,
        reasoning_reverse: precedent.reasoning_reverse
      }
    }
  end
end
