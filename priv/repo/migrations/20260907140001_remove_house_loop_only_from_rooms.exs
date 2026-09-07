defmodule Thereish.Repo.Migrations.RemoveHouseLoopOnlyFromRooms do
  use Ecto.Migration

  def up do
    alter table(:rooms) do
      remove :house_loop_only
    end
  end

  def down do
    alter table(:rooms) do
      add :house_loop_only, :boolean, default: false, null: false
    end

    execute(
      "UPDATE rooms SET house_loop_only = true WHERE music = 'house'",
      "UPDATE rooms SET music = 'house' WHERE house_loop_only = true"
    )
  end
end
