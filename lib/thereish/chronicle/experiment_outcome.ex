defmodule Thereish.Chronicle.ExperimentOutcome do
  @moduledoc """
  A recorded outcome for a Page within an experiment (ticket 13).

  Append-only event table (ADR-0003, design law 5): no updated_at.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_experiment_outcomes" do
    field :page_identifier, :string
    field :experiment_id, :string
    field :arm, :string
    field :melded, :boolean
    field :closeness, :integer
    field :attempts_count, :integer
    field :closed_because, :string
    field :trap_converged, :boolean, default: false
    field :deep_converged, :boolean, default: false
    field :closing_band, :string
    field :taps, :map, default: %{}

    belongs_to :room, Thereish.Rooms.Room
    belongs_to :page, Thereish.Chronicle.Page

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(outcome, attrs) do
    outcome
    |> cast(attrs, [
      :room_id,
      :page_id,
      :page_identifier,
      :experiment_id,
      :arm,
      :melded,
      :closeness,
      :closing_band,
      :taps,
      :attempts_count,
      :closed_because,
      :trap_converged,
      :deep_converged
    ])
    |> validate_required([
      :room_id,
      :page_identifier,
      :experiment_id,
      :arm,
      :melded,
      :attempts_count,
      :closed_because
    ])
    # Every Arm any Experiment has declared, the retired ones included: a row
    # outlives its Experiment and still has to read back (ADR-0003).
    |> validate_inclusion(:arm, [
      "bait",
      "plain",
      "flash",
      "astra",
      "nudge_on",
      "nudge_off"
    ])
  end
end
