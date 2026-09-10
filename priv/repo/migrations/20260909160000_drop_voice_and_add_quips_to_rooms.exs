defmodule Thereish.Repo.Migrations.DropVoiceAndAddQuipsToRooms do
  use Ecto.Migration

  def up do
    alter table(:rooms) do
      remove :voice
      add :quips, :boolean, default: true, null: false
    end
  end

  def down do
    alter table(:rooms) do
      add :voice, :boolean, default: false, null: false
      remove :quips
    end
  end
end
