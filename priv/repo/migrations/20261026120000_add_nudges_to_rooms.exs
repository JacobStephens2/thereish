defmodule Thereish.Repo.Migrations.AddNudgesToRooms do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :nudges, :boolean, default: true, null: false
    end
  end
end
