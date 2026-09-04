defmodule MeaningGame.Chronicle.Verdict do
  @moduledoc """
  What the Assayer said about one pair of Bridges, and who said it.

  The grade is stored exactly as the players saw it, because the grade that was
  shown is the precedent (ADR-0006). A pair the Assayer could not grade is a row
  too, with `graded` false and no number — the game admitting it had no verdict
  is a thing that happened and belongs in the record.

  `model`, `prompt_version`, `latency_ms` and `cost_usd` are what keep the model
  policy measured rather than remembered. They are null on a verdict that never
  arrived, because nothing came back to attribute it to.
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
    field :model, :string
    field :prompt_version, :string
    field :latency_ms, :integer
    field :cost_usd, :decimal
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
      :model,
      :prompt_version,
      :latency_ms,
      :cost_usd,
      :position
    ])
    |> validate_required([:attempt_id, :seat_ids, :bridges, :graded, :position])
  end
end
