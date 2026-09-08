defmodule Thereish.Repo.Migrations.CreateRoomNevers do
  use Ecto.Migration

  def change do
    create table(:room_nevers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :path, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:room_nevers, [:room_id, :path])
    create index(:room_nevers, [:room_id])
  end
end
