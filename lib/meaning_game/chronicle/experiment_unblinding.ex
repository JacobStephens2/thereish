defmodule MeaningGame.Chronicle.ExperimentUnblinding do
  @moduledoc """
  A recorded unblinding event for an experiment (ticket 13).

  Unblinding is a deliberate action, recorded in the Chronicle with the time it happened.
  Append-only event table (ADR-0003, design law 5): no updated_at.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_experiment_unblindings" do
    field :experiment_id, :string
    field :unblinded_at, :utc_datetime_usec
    field :notes, :string

    belongs_to :room, MeaningGame.Rooms.Room
    belongs_to :seat, MeaningGame.Rooms.Seat

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(unblinding, attrs) do
    unblinding
    |> cast(attrs, [:room_id, :experiment_id, :seat_id, :unblinded_at, :notes])
    |> validate_required([:room_id, :experiment_id, :unblinded_at])
  end
end
