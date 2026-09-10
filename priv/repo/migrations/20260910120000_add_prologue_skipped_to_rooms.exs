defmodule Thereish.Repo.Migrations.AddPrologueSkippedToRooms do
  use Ecto.Migration

  def up do
    alter table(:rooms) do
      add :prologue_skipped, :boolean, default: false, null: false
    end
  end

  def down do
    alter table(:rooms) do
      remove :prologue_skipped
    end
  end
end
