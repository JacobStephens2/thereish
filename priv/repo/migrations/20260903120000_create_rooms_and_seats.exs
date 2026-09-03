defmodule MeaningGame.Repo.Migrations.CreateRoomsAndSeats do
  use Ecto.Migration

  # Seats never expire, so there is no expiry column and nothing ever deletes a
  # row here. A Seat outlives the Room process, the browser tab, and the evening;
  # a Chronicle row will reference this id and expect it to still be there.
  def change do
    create table(:rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :citext, null: false
      add :seat_limit, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rooms, [:slug])

    create table(:seats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :restrict), null: false
      add :name, :citext, null: false
      add :device_tokens, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    # A name is the identity inside a Room, so it is unique there and compared
    # case-insensitively — "melissa" reclaims Melissa's Seat.
    create unique_index(:seats, [:room_id, :name])

    # Device tokens are a list because a Seat is a person, and a person may come
    # back on a second browser without the first one losing its place. Nothing
    # here enforces that one token holds one Seat per Room; the Room process is
    # the only writer, so it enforces that by being the only writer.
    create index(:seats, [:device_tokens], using: :gin)
  end
end
