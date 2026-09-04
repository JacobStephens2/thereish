defmodule MeaningGame.Chronicle.Correction do
  @moduledoc """
  A player correction recorded in the Chronicle.

  Nothing in the Chronicle is ever mutated or deleted (ADR-0003, design law 5).
  When players correct an entry — fixing a typo, correcting a bridge, or adding
  a note — the correction is recorded here as an append-only event.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_corrections" do
    field :attempt_number, :integer
    field :target, :string
    field :original_value, :string
    field :corrected_value, :string
    field :note, :string

    belongs_to :room, MeaningGame.Rooms.Room
    belongs_to :page, MeaningGame.Chronicle.Page
    belongs_to :seat, MeaningGame.Rooms.Seat

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(correction, attrs) do
    correction
    |> cast(attrs, [
      :room_id,
      :page_id,
      :seat_id,
      :attempt_number,
      :target,
      :original_value,
      :corrected_value,
      :note
    ])
    |> validate_required([:room_id, :page_id, :target, :corrected_value])
  end
end
