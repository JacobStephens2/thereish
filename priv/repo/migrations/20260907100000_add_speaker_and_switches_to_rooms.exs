defmodule MeaningGame.Repo.Migrations.AddSpeakerAndSwitchesToRooms do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :speaker, :string
      add :voice, :boolean, default: false, null: false
      add :house_loop_only, :boolean, default: false, null: false
    end
  end
end
