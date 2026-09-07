defmodule Thereish.Repo.Migrations.AddMusicToRooms do
  use Ecto.Migration

  def up do
    alter table(:rooms) do
      add :music, :string, default: "page", null: false
    end

    execute(
      "UPDATE rooms SET music = 'house' WHERE house_loop_only = true",
      "UPDATE rooms SET house_loop_only = true WHERE music = 'house'"
    )
  end

  def down do
    alter table(:rooms) do
      remove :music
    end
  end
end
