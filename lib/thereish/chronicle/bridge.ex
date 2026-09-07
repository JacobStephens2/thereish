defmodule Thereish.Chronicle.Bridge do
  @moduledoc """
  What one Seat wrote on one attempt.

  A row of its own rather than a field on the attempt, because the question
  "what has Melissa written across every Page we have played?" is the one the
  calibration set and the book are both going to ask, and it should be a query
  rather than a scan. It references the Seat, never an Account (ADR-0007).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_bridges" do
    field :bridge, :string
    field :position, :integer

    belongs_to :attempt, Thereish.Chronicle.Attempt
    belongs_to :seat, Thereish.Rooms.Seat

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:attempt_id, :seat_id, :bridge, :position])
    |> validate_required([:attempt_id, :seat_id, :bridge, :position])
    |> unique_constraint([:attempt_id, :seat_id])
  end
end
