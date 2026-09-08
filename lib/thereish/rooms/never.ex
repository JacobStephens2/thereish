defmodule Thereish.Rooms.Never do
  @moduledoc """
  A Room's verdict that one Repertoire member will not be drawn again in that Room.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "room_nevers" do
    field :path, :string

    belongs_to :room, Thereish.Rooms.Room

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(never, attrs) do
    never
    |> cast(attrs, [:room_id, :path])
    |> validate_required([:room_id, :path])
    |> unique_constraint([:room_id, :path])
  end
end
