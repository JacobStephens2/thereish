defmodule MeaningGame.Repo.Migrations.AddTitleToTrackCache do
  use Ecto.Migration

  def change do
    alter table(:track_cache) do
      add :title, :text
    end
  end
end
