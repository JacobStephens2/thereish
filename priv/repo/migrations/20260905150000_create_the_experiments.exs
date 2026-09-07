defmodule Thereish.Repo.Migrations.CreateTheExperiments do
  use Ecto.Migration

  # Every Page is an experiment, starting with Bait against plain (ADR-0004, ticket 13).
  #
  # Append-only event tables (ADR-0003, design law 5):
  # - Assignments record arm allocation at Page start, stratified by Chapter.
  # - Outcomes record results when a Page closes.
  # - Unblindings record when the deliberate action to unblind occurred.
  def change do
    create table(:chronicle_experiment_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :restrict), null: false
      add :page_id, references(:chronicle_pages, type: :binary_id, on_delete: :restrict)
      add :page_identifier, :text, null: false
      add :experiment_id, :text, null: false
      add :arm, :text, null: false
      add :chapter, :text, null: false
      add :assigned_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_experiment_assignments, [:room_id])
    create index(:chronicle_experiment_assignments, [:page_identifier])
    create index(:chronicle_experiment_assignments, [:experiment_id, :chapter])

    create table(:chronicle_experiment_outcomes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :restrict), null: false
      add :page_id, references(:chronicle_pages, type: :binary_id, on_delete: :restrict)
      add :page_identifier, :text, null: false
      add :experiment_id, :text, null: false
      add :arm, :text, null: false
      add :melded, :boolean, null: false
      add :closeness, :integer
      add :attempts_count, :integer, null: false
      add :closed_because, :text, null: false
      add :trap_converged, :boolean, default: false, null: false
      add :deep_converged, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_experiment_outcomes, [:room_id])
    create index(:chronicle_experiment_outcomes, [:experiment_id, :arm])

    create table(:chronicle_experiment_unblindings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :restrict), null: false
      add :experiment_id, :text, null: false
      add :seat_id, references(:seats, type: :binary_id, on_delete: :restrict)
      add :unblinded_at, :utc_datetime_usec, null: false
      add :notes, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_experiment_unblindings, [:room_id, :experiment_id])
  end
end
