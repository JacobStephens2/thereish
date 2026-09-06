defmodule MeaningGame.Repo.Migrations.CreateTheTrackCacheAndAddMusicMeta do
  use Ecto.Migration

  def change do
    alter table(:chronicle_pages) do
      add :music_meta, :map
    end

    create table(:track_cache, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :text, null: false
      add :gives, {:array, :text}, null: false
      add :path, :text, null: false
      add :duration, :integer
      add :format, :text, default: "mp3"
      add :meta, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:track_cache, [:key])
    create index(:track_cache, [:inserted_at])
  end
end
