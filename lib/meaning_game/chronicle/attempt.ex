defmodule MeaningGame.Chronicle.Attempt do
  @moduledoc """
  One try at a Page: the two words it hung between, and how close the Room got.

  `bookends` is the Page's own on the first attempt and the previous attempt's
  failed Bridges on every one after it, so the carry-forward is legible from the
  rows alone — reading a Page's attempts in order is reading the arc.

  `closeness` is the number the players were shown, stored rather than
  recomputed: the grade that was shown is the record of what happened
  (ADR-0006).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_attempts" do
    field :number, :integer
    field :bookends, {:array, :string}
    field :closeness, :integer
    field :melded, :boolean

    belongs_to :page, MeaningGame.Chronicle.Page
    has_many :bridges, MeaningGame.Chronicle.Bridge, preload_order: [asc: :position]
    has_many :verdicts, MeaningGame.Chronicle.Verdict, preload_order: [asc: :position]

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:page_id, :number, :bookends, :closeness, :melded])
    |> validate_required([:page_id, :number, :bookends, :melded])
    |> unique_constraint([:page_id, :number])
  end
end
