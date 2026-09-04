defmodule MeaningGame.Repo.Migrations.CreateTheCorrections do
  use Ecto.Migration

  # The couple can correct an entry in the Chronicle, and the correction is
  # recorded as another append-only event rather than by mutating history
  # (design law 5, ticket 08).
  #
  # No table here has an `updated_at` — nothing in the application writes an
  # UPDATE or DELETE against them.
  def change do
    create table(:chronicle_corrections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :restrict), null: false

      add :page_id, references(:chronicle_pages, type: :binary_id, on_delete: :restrict),
        null: false

      add :seat_id, references(:seats, type: :binary_id, on_delete: :restrict)

      add :attempt_number, :integer
      add :target, :text, null: false
      add :original_value, :text
      add :corrected_value, :text, null: false
      add :note, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_corrections, [:room_id])
    create index(:chronicle_corrections, [:page_id])
    create index(:chronicle_corrections, [:seat_id])
  end
end
