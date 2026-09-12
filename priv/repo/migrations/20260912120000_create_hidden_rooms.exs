defmodule Thereish.Repo.Migrations.CreateHiddenRooms do
  use Ecto.Migration

  # A hide is this browser's choice not to list a Room it still holds a Seat in.
  # The Seat, the Chronicle, and the device association stay; only the shortcut
  # on the front page goes. Another browser's list is a different device token.
  def change do
    create table(:hidden_rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_token, :text, null: false
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:hidden_rooms, [:device_token, :room_id])
    create index(:hidden_rooms, [:device_token])
  end
end
