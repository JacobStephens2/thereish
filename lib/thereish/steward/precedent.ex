defmodule Thereish.Steward.Precedent do
  @moduledoc """
  The verdict cache that lives behind the Steward.

  When the couple plays the same Bookends and writes the same Bridges a month
  later, the game grades exactly as it graded the first time (design law 1). The
  cache settles the grade shown to every table writing those words (ADR-0006).
  A hit skips grading. An Assay that starts grading resolves to the row visible
  after its insert attempt, including any competing Verdict or joint Overrule.

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
  Attempt's Bookends (ADR-0010). An overrule rewrites what the players argued
  about — the grade, the reasoning, the quip — and leaves the furthest pair
  alone: the couple ruled on how close the words were, not on which two of them
  were the far ones.

  Nothing silently rewrites a precedent: offline annotations never touch the
  cache. Only a joint player overrule (design law 3) will rewrite it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Thereish.Repo
  alias Thereish.Steward
  alias Thereish.Steward.Precedent

  @primary_key {:id, :binary_id, autogenerate: true}

  @type t :: %__MODULE__{}

  schema "precedents" do
    field :key, :string
    field :model, :string
    field :prompt_version, :string
    field :bookends, {:array, :string}
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

  defp changeset(precedent, attrs) do
    precedent
    |> cast(attrs, [
      :key,
      :model,
      :prompt_version,
      :bookends,
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
      :bookends,
      :bridges,
      :closeness,
      :reasoning,
      :quip
    ])
    |> unique_constraint(:key)
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
  Resolves the stored Verdict for the model, prompt version and Assay request.

  An initial hit returns `{:ok, :hit, verdict}` without invoking `grade`.
  On a miss, `grade` runs before any write. The cold resolution returns
  `{:ok, :cold, verdict}` with the stored grade and Quip and this Assay's own
  grading provenance. A grading error or an unsuccessful write or readback
  returns an error.
  """
  @spec resolve(String.t(), String.t(), Steward.request(), (-> {:ok, Steward.verdict()}
                                                               | {:error, term()})) ::
          {:ok, :hit | :cold, Steward.verdict()} | {:error, term()}
  def resolve(model, prompt_version, %{bookends: bookends, bridges: bridges}, grade) do
    attrs = precedent_attrs(model, prompt_version, bookends, bridges)

    case Repo.get_by(Precedent, key: attrs.key) do
      nil -> resolve_cold(attrs, grade)
      %Precedent{} = stored -> {:ok, :hit, to_verdict(stored)}
    end
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, error}
  end

  defp resolve_cold(attrs, grade) do
    with {:ok, candidate} <- grade.(),
         id = Ecto.UUID.generate(),
         {:ok, _} <- insert_candidate(attrs, id, candidate) do
      # A separate statement sees the row that beat an ON CONFLICT insert.
      case Repo.get_by(Precedent, key: attrs.key) do
        %Precedent{} = stored ->
          verdict = to_verdict(stored)

          provenance =
            candidate.meta
            |> Map.take([:model, :prompt_version, :cost_usd])
            |> Map.put(:precedent_hit, stored.id != id)

          {:ok, :cold, %{verdict | meta: Map.merge(verdict.meta, provenance)}}

        nil ->
          {:error, :precedent_missing}
      end
    end
  end

  defp insert_candidate(attrs, id, verdict) do
    fields = %{
      closeness: verdict.closeness,
      reasoning: verdict.reasoning,
      quip: verdict.quip,
      forward: get_in(verdict, [:meta, :forward]),
      reverse: get_in(verdict, [:meta, :reverse]),
      reasoning_reverse: get_in(verdict, [:meta, :reasoning_reverse]),
      # Verbatim, and neither normalised nor sorted like the key's inputs: these
      # two words are about to be shown as the next Attempt's Bookends, so they
      # are kept as the players wrote them.
      furthest: Map.get(verdict, :furthest),
      cost_usd: get_in(verdict, [:meta, :cost_usd])
    }

    %Precedent{id: id}
    |> changeset(Map.merge(attrs, fields))
    |> Repo.insert(on_conflict: :nothing, conflict_target: :key)
  end

  @doc """
  Rewrites an existing precedent (or inserts a new one) with the table's ruling:
  its closeness, reasoning and Quip.

  A joint player overrule is the only thing in the system that rewrites
  precedent (ADR-0006, design law 3).
  """
  @spec overrule(String.t(), String.t(), [String.t()], [String.t()], map()) ::
          {:ok, Precedent.t()} | {:error, Ecto.Changeset.t()}
  def overrule(model, prompt_version, bookends, bridges, ruling) do
    attrs = precedent_attrs(model, prompt_version, bookends, bridges)
    fields = Map.take(ruling, [:closeness, :reasoning, :quip])

    %Precedent{}
    |> changeset(Map.merge(attrs, fields))
    |> Repo.insert(
      on_conflict: {:replace, [:closeness, :reasoning, :quip, :updated_at]},
      conflict_target: :key
    )
  end

  defp precedent_attrs(model, prompt_version, bookends, bridges) do
    bookends = bookends |> Enum.map(&normalize/1) |> Enum.sort()

    bridges =
      bridges
      |> Enum.map(&Thereish.Steward.Legality.bridge_text/1)
      |> Enum.map(&normalize/1)
      |> Enum.sort()

    %{
      key: hash(model, prompt_version, bookends, bridges),
      model: model,
      prompt_version: prompt_version,
      bookends: bookends,
      bridges: bridges
    }
  end

  defp hash(model, prompt_version, bookends, bridges) do
    canonical = [model, prompt_version, bookends, bridges]

    :crypto.hash(:sha256, Jason.encode!(canonical))
    |> Base.encode16(case: :lower)
  end

  defp to_verdict(%Precedent{} = precedent) do
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
        reasoning_reverse: precedent.reasoning_reverse,
        spread: spread(precedent)
      }
    }
  end

  # The disagreement is not a column, because it is the two readings subtracted:
  # a row that kept both keeps it. An inherited grade has to carry it, or the
  # second table to write these Bridges would be shown a settled grade where the
  # first was shown an argument (ADR-0006).
  defp spread(%Precedent{forward: forward, reverse: reverse})
       when is_integer(forward) and is_integer(reverse),
       do: abs(forward - reverse)

  defp spread(_precedent), do: nil
end
