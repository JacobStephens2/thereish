defmodule MeaningGame.Repo.Migrations.ThePageIsWrittenAtTheTable do
  use Ecto.Migration

  def change do
    drop_if_exists table(:authored_pages)

    alter table(:chronicle_pages) do
      add :author_meta, :map
    end

    create table(:chronicle_gives, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :page_id, references(:chronicle_pages, type: :binary_id, on_delete: :restrict),
        null: false

      add :seat_id, references(:seats, type: :binary_id, on_delete: :restrict), null: false
      add :text, :text, null: false
      add :order, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_gives, [:page_id, :order])
    create unique_index(:chronicle_gives, [:page_id, :seat_id])
    create index(:chronicle_gives, [:seat_id])
  end
end
