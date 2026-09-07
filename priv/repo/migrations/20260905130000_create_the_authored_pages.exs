defmodule Thereish.Repo.Migrations.CreateTheAuthoredPages do
  use Ecto.Migration

  def change do
    create table(:authored_pages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :page_id, :text, null: false
      add :chapter, :text, null: false
      add :give, :text
      add :theme, :text, null: false
      add :anchors, {:array, :text}, null: false
      add :bait, :text, null: false
      add :deep_bridges, {:array, :text}, null: false
      add :likely_bridges, {:array, :text}, null: false
      add :why_these, :text, null: false
      add :band_scripts, :map, null: false
      add :meta, :map, null: false

      # When the page was drawn by a Room. Nil while in the unplayed pool.
      add :played_at, :utc_datetime_usec
      add :played_room_id, :binary_id

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:authored_pages, [:played_at, :inserted_at])
    create index(:authored_pages, [:chapter, :played_at])
    create unique_index(:authored_pages, [:page_id])
  end
end
