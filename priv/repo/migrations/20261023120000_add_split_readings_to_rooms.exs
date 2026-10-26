defmodule Thereish.Repo.Migrations.AddSplitReadingsToRooms do
  use Ecto.Migration

  def up do
    alter table(:rooms) do
      add :split_readings, :boolean, default: true, null: false
    end
  end

  def down do
    alter table(:rooms) do
      remove :split_readings
    end
  end
end
