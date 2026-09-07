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
    field :speaker, :string
    field :voice, :boolean, default: false
    field :music, :string, default: "page"

    has_many :seats, MeaningGame.Rooms.Seat

    timestamps(type: :utc_datetime_usec)
  end

  @music_modes ~w(off house page)

  @doc "The valid music modes for a Room."
  def music_modes, do: @music_modes

  @doc "The shape a slug has to have, so a mistyped URL can be turned away early."
  def slug_format, do: @slug_format

  @doc false
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:slug, :seat_limit, :speaker, :voice, :music])
    |> validate_required([:slug, :seat_limit])
    |> validate_format(:slug, @slug_format)
    |> validate_inclusion(:music, @music_modes)
    # Two is the smallest number of Seats that is still a Room. It is not the
    # default, which is configuration; it is the floor.
    #
    # The ceiling is the reveal's, not the rules' and no longer the bill's: an
    # Attempt is one grading request however many Seats wrote into it
    # (ADR-0010), so six is what a phone can show at once and what one reading
    # can hold one opinion about. The rules themselves are written for a list of
    # any length (ADR-0007).
    |> validate_number(:seat_limit,
      greater_than_or_equal_to: 2,
      less_than_or_equal_to: MeaningGame.Steward.seat_cap()
    )
    |> unique_constraint(:slug)
  end

  @doc "Changeset for Room facts that can be changed during or across Pages."
  def facts_changeset(room, attrs) do
    room
    |> cast(attrs, [:speaker, :voice, :music])
    |> validate_inclusion(:music, @music_modes)
  end
end
