defmodule MeaningGame.Rooms.Room do
  @moduledoc """
  A Room as Postgres holds it: a slug people can type and the number of Seats it
  holds.

  The live Room is `MeaningGame.Rooms.Server`; this row is what it is restored
  from when that process restarts. `seat_limit` is a column rather than a
  constant so that N is a property of a Room, not of the codebase.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # A slug is typed into a phone, so it is lowercase and short enough to type.
  @slug_format ~r/^[a-z0-9][a-z0-9-]{0,39}$/

  schema "rooms" do
    field :slug, :string
    field :seat_limit, :integer

    has_many :seats, MeaningGame.Rooms.Seat

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The shape a slug has to have, so a mistyped URL can be turned away early."
  def slug_format, do: @slug_format

  @doc false
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:slug, :seat_limit])
    |> validate_required([:slug, :seat_limit])
    |> validate_format(:slug, @slug_format)
    # Two is the smallest number of Seats that is still a Room. It is not the
    # default, which is configuration; it is the floor.
    #
    # The ceiling is the Assayer's, not the rules': every attempt is graded as
    # N choose 2 pairs, so six Seats is fifteen live gradings inside one reveal
    # beat. The rules themselves are written for a list of any length
    # (ADR-0007), and this is the number the couch can afford in v1.
    |> validate_number(:seat_limit,
      greater_than_or_equal_to: 2,
      less_than_or_equal_to: MeaningGame.Steward.seat_cap()
    )
    |> unique_constraint(:slug)
  end
end
