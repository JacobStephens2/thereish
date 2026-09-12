defmodule Thereish.Repo.Migrations.AddFullTableToRooms do
  use Ecto.Migration

  def up do
    alter table(:rooms) do
      add :full_table, :boolean, default: true, null: false
    end
  end

  def down do
    alter table(:rooms) do
      remove :full_table
    end
  end
end
