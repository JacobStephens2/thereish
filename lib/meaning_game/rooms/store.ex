defmodule MeaningGame.Rooms.Store do
  @moduledoc """
  Where a Room's queries live, so `MeaningGame.Rooms.Server` reads as process
  logic rather than as SQL.

  Tests run against real Postgres with the Ecto sandbox (ADR-0003), so nothing
  here is a seam and nothing stands in for it.
  """

  import Ecto.Query

  alias MeaningGame.Repo
  alias MeaningGame.Rooms.Room
  alias MeaningGame.Rooms.Seat

  @doc """
  The Room with this slug, created with `seat_limit` Seats if it is new.

  An existing Room keeps the `seat_limit` it was created with; the argument is a
  default for a first visit, not a setting a visitor can change.
  """
  @spec get_or_create_room(String.t(), pos_integer()) ::
          {:ok, Room.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_room(slug, seat_limit) do
    case Repo.get_by(Room, slug: slug) do
      %Room{} = room -> {:ok, room}
      nil -> create_room(slug, seat_limit)
    end
  end

  defp create_room(slug, seat_limit) do
    %Room{}
    |> Room.changeset(%{slug: slug, seat_limit: seat_limit})
    |> Repo.insert()
    |> case do
      {:ok, room} ->
        {:ok, room}

      {:error, changeset} ->
        # Either someone opened the same Room between the read and the write, or
        # the slug is not one a Room can have. Only the first has a Room to
        # return.
        case Repo.get_by(Room, slug: slug) do
          %Room{} = room -> {:ok, room}
          nil -> {:error, changeset}
        end
    end
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
          {:ok, Seat.t()} | {:error, Ecto.Changeset.t()}
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
end
