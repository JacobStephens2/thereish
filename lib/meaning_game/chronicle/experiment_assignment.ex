defmodule MeaningGame.Chronicle.ExperimentAssignment do
  @moduledoc """
  A recorded arm assignment for a Page within an experiment (ticket 13).

  Append-only event table (ADR-0003, design law 5): no updated_at.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_experiment_assignments" do
    field :page_identifier, :string
    field :experiment_id, :string
    field :arm, :string
    field :chapter, :string
    field :assigned_at, :utc_datetime_usec

    belongs_to :room, MeaningGame.Rooms.Room
    belongs_to :page, MeaningGame.Chronicle.Page

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [
      :room_id,
      :page_id,
      :page_identifier,
      :experiment_id,
      :arm,
      :chapter,
      :assigned_at
    ])
    |> validate_required([
      :room_id,
      :page_identifier,
      :experiment_id,
      :arm,
      :chapter,
      :assigned_at
    ])
    |> validate_inclusion(:arm, ["bait", "plain", "flash", "astra"])
  end
end
