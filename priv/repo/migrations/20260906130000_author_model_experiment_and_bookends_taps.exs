defmodule Thereish.Repo.Migrations.AuthorModelExperimentAndBookendsTaps do
  use Ecto.Migration

  def change do
    create table(:chronicle_bookends_taps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :restrict), null: false
      add :page_id, references(:chronicle_pages, type: :binary_id, on_delete: :restrict)
      add :page_identifier, :text, null: false
      add :seat_id, references(:seats, type: :binary_id, on_delete: :restrict), null: false

      add :label, :text, null: false
      add :bookends, {:array, :text}
      add :gives, :map
      add :author_meta, :map
      add :arm, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_bookends_taps, [:room_id])
    create index(:chronicle_bookends_taps, [:seat_id])
    create index(:chronicle_bookends_taps, [:page_id])
    create index(:chronicle_bookends_taps, [:page_identifier])

    alter table(:chronicle_experiment_outcomes) do
      add :closing_band, :text
      add :taps, :map, default: %{}
    end
  end
end
