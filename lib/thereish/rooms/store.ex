defmodule Thereish.Rooms.Store do
  @moduledoc """
  Where a Room's queries live, so `Thereish.Rooms.Server` reads as process
  logic rather than as SQL.

  Tests run against real Postgres with the Ecto sandbox (ADR-0003), so nothing
  here is a seam and nothing stands in for it.
  """

  import Ecto.Query

  alias Thereish.Repo
  alias Thereish.Rooms.Never
  alias Thereish.Rooms.Room
  alias Thereish.Rooms.Seat

  @doc "The Room with this Code, or nil."
  @spec get_room(String.t()) :: Room.t() | nil
  def get_room(code), do: Repo.get_by(Room, slug: code)

  @doc "Every Code currently taken by a Room."
  @spec taken_codes() :: [String.t()]
  def taken_codes do
    Repo.all(from r in Room, select: r.slug)
  end

  @doc "Every Room in the database."
  @spec list_rooms() :: [Room.t()]
  def list_rooms, do: Repo.all(Room)

  @doc """
  Writes a new Room down.

  A Code someone else took between the draw and the write comes back as a
  changeset error, which is the caller's cue to draw another word rather than a
  reason to fail.
  """
  @spec insert_room(String.t(), pos_integer(), String.t() | nil) ::
          {:ok, Room.t()} | {:error, Ecto.Changeset.t()}
  def insert_room(code, seat_limit, quip \\ nil) do
    %Room{}
    |> Room.changeset(%{slug: code, seat_limit: seat_limit, quip: quip})
    |> Repo.insert()
  end

  @doc """
  Every Room this browser holds a Seat in, newest Seat first, each with the Seat
  it holds.

  This is what the front page's rejoin links are made of: a phone that has been
  in a Room is one tap from its own Seat, without remembering a Code.
  """
  @spec rooms_for_device(String.t()) :: [%{room: Room.t(), seat: Seat.t()}]
  def rooms_for_device(device_token) do
    Repo.all(
      from s in Seat,
        join: r in assoc(s, :room),
        where: ^device_token in s.device_tokens,
        order_by: [desc: s.inserted_at, desc: s.id],
        preload: [room: r]
    )
    |> Enum.map(&%{room: &1.room, seat: &1})
  end

  @doc "Every Seat in the Room, in the order they were first taken."
  @spec list_seats(Ecto.UUID.t()) :: [Seat.t()]
  def list_seats(room_id) do
    Repo.all(
      from s in Seat, where: s.room_id == ^room_id, order_by: [asc: s.inserted_at, asc: s.id]
    )
  end

  @doc "The Seat this browser holds in the Room, or nil."
  @spec seat_by_device_token(Ecto.UUID.t(), String.t()) :: Seat.t() | nil
  def seat_by_device_token(room_id, device_token) do
    Repo.one(
      from s in Seat,
        where: s.room_id == ^room_id and ^device_token in s.device_tokens,
        order_by: [asc: s.inserted_at, asc: s.id],
        limit: 1
    )
  end

  @doc """
  The Seat held under this name, or nil.

  The column is `citext`, so "mara" finds Mara's Seat. A name is the
  identity inside a Room, which is how a browser that has forgotten its device
  token gets its own Seat back rather than a fresh one.
  """
  @spec seat_by_name(Ecto.UUID.t(), String.t()) :: Seat.t() | nil
  def seat_by_name(room_id, name) do
    Repo.get_by(Seat, room_id: room_id, name: name)
  end

  @doc """
  Writes a new Seat with an id the caller already minted.

  The id is the caller's because the rules decide whether the Seat may exist
  before Postgres hears about it, and the rules need something to decide about.
  """
  @spec insert_seat(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), String.t()) ::
          {:ok, Seat.t()} | {:error, Ecto.Changeset.t() | term()}
  def insert_seat(room_id, id, name, device_token) do
    %Seat{}
    |> Seat.changeset(%{
      id: id,
      room_id: room_id,
      name: name,
      device_tokens: [device_token]
    })
    |> Repo.insert()
  end

  @doc """
  Adds a browser to the ones a Seat can be reached from.

  It adds rather than replaces, so a player coming back on a second browser
  leaves the first one still holding their Seat.
  """
  @spec remember_device(Seat.t(), String.t()) :: {:ok, Seat.t()} | {:error, Ecto.Changeset.t()}
  def remember_device(%Seat{} = seat, device_token) do
    seat
    |> Seat.remember_device_changeset(device_token)
    |> Repo.update()
  end

  @doc "Updates Room facts (speaker, quips, music, Full table)."
  @spec update_room(Room.t(), map()) :: {:ok, Room.t()} | {:error, Ecto.Changeset.t()}
  def update_room(%Room{} = room, attrs) do
    room
    |> Room.facts_changeset(attrs)
    |> Repo.update()
  end

  @doc "Records a Repertoire member path as Never in this Room."
  @spec record_never(Ecto.UUID.t(), String.t()) :: {:ok, Never.t()} | {:error, term()}
  def record_never(room_id, path) do
    %Never{}
    |> Never.changeset(%{room_id: room_id, path: path})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:room_id, :path])
  end

  @doc "Lists all paths marked Never in this Room."
  @spec list_nevers(Ecto.UUID.t() | String.t()) :: [String.t()]
  def list_nevers(room_id) do
    from(n in Never,
      where: n.room_id == ^room_id,
      select: n.path
    )
    |> Repo.all()
  end
end
