defmodule Thereish.Chronicle.Attempt do
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
    field :started_at, :utc_datetime_usec
    field :assaying_started_at, :utc_datetime_usec
    field :revealed_at, :utc_datetime_usec
    field :advanced_at, :utc_datetime_usec

    belongs_to :page, Thereish.Chronicle.Page
    has_many :bridges, Thereish.Chronicle.Bridge, preload_order: [asc: :position]
    has_many :verdicts, Thereish.Chronicle.Verdict, preload_order: [asc: :position]

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :page_id,
      :number,
      :bookends,
      :closeness,
      :melded,
      :started_at,
      :assaying_started_at,
      :revealed_at,
      :advanced_at
    ])
    |> validate_required([:page_id, :number, :bookends, :melded])
    |> unique_constraint([:page_id, :number])
  end
end
