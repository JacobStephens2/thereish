defmodule Thereish.Rooms.Seat do
  @moduledoc """
  A place in a Room, held under a name.

  Its `id` is stable and permanent: Chronicle rows will reference it, an Account
  may claim it later (ADR-0007), and nothing in this system ever deletes one. A
  Seat outlives the browser tab, the Room process, and the evening.

  `device_tokens` are the browsers this Seat has been held from, and it is a
  list rather than a column because a Seat is a person. Melissa reaching her
  Seat from the iPad must not knock her Pixel out of it, so claiming a Seat
  remembers a device instead of replacing the one it had.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @name_max 24

  schema "seats" do
    field :name, :string
    field :device_tokens, {:array, :string}, default: []

    belongs_to :room, Thereish.Rooms.Room

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The longest name a Seat may be held under."
  def name_max, do: @name_max

  @doc false
  def changeset(seat, attrs) do
    seat
    |> cast(attrs, [:id, :room_id, :name, :device_tokens])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:room_id, :name])
    |> validate_length(:name, min: 1, max: @name_max)
    |> unique_constraint([:room_id, :name])
  end

  @doc "Remembers one more browser this Seat is reachable from."
  def remember_device_changeset(%__MODULE__{device_tokens: tokens} = seat, device_token) do
    if device_token in tokens do
      change(seat)
    else
      change(seat, device_tokens: tokens ++ [device_token])
    end
  end
end
