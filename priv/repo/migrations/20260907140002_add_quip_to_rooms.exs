defmodule MeaningGame.Repo.Migrations.AddQuipToRooms do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :quip, :text
    end
  end
end
