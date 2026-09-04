defmodule MeaningGame.Chronicle.Verdict do
  @moduledoc """
  What the Assayer said about an Attempt's Bridges, and who said it.

  The grade is stored exactly as the players saw it, because the grade that was
  shown is the precedent (ADR-0006). Bridges the Assayer could not grade are a
  row too, with `graded` false and no number — the game admitting it had no
  verdict is a thing that happened and belongs in the record.

  `furthest` is the two Bridges the Assayer named as landing furthest apart, and
  it is in the book because those two words became the next Attempt's Anchors
  (ADR-0010). Without it a reader could see an Attempt converge and not see why
  it converged there. It is null on a Verdict that never arrived, and on every
  row written before the Assayer was asked the question.

  `model`, `prompt_version`, `latency_ms` and `cost_usd` are what keep the model
  policy measured rather than remembered. `forward`, `reverse` and
  `reasoning_reverse` are the two orderings the grade was the mean of, kept so
  that a grade the couple want to argue with can be argued with in detail. All
  of them are null on a verdict that never arrived, because nothing came back to
  attribute it to.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_verdicts" do
    field :seat_ids, {:array, Ecto.UUID}
    field :bridges, {:array, :string}
    field :graded, :boolean
    field :closeness, :integer
    field :band, :string
    field :reasoning, :string
    field :quip, :string
    field :model, :string
    field :prompt_version, :string
    field :latency_ms, :integer
    field :cost_usd, :decimal
    field :forward, :integer
    field :reverse, :integer
    field :reasoning_reverse, :string
    field :furthest, {:array, :string}
    field :overruled, :boolean, default: false
    field :position, :integer

    belongs_to :attempt, MeaningGame.Chronicle.Attempt

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(verdict, attrs) do
    verdict
    |> cast(attrs, [
      :attempt_id,
      :seat_ids,
      :bridges,
      :graded,
      :closeness,
      :band,
      :reasoning,
      :quip,
      :model,
      :prompt_version,
      :latency_ms,
      :cost_usd,
      :forward,
      :reverse,
      :reasoning_reverse,
      :furthest,
      :overruled,
      :position
    ])
    |> validate_required([:attempt_id, :seat_ids, :bridges, :graded, :position])
  end
end
