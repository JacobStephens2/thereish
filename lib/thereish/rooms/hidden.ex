defmodule Thereish.Rooms.Hidden do
  @moduledoc """
  A browser's choice to drop a Room from its home list.

  The Seat and the device token that finds it stay. Hiding is the shortcut
  going away, not the identity: the Code still opens the same Seat, and
  another browser's list is a different token.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "hidden_rooms" do
    field :device_token, :string

    belongs_to :room, Thereish.Rooms.Room

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(hidden, attrs) do
    hidden
    |> cast(attrs, [:device_token, :room_id])
    |> validate_required([:device_token, :room_id])
    |> unique_constraint([:device_token, :room_id])
  end
end
