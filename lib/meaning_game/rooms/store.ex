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
  @spec insert_room(String.t(), pos_integer()) :: {:ok, Room.t()} | {:error, Ecto.Changeset.t()}
  def insert_room(code, seat_limit) do
    %Room{}
    |> Room.changeset(%{slug: code, seat_limit: seat_limit})
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
  Writes a new Seat with an id the caller already minted, optionally paired with
  an existing Seat in the same Room.

  The id is the caller's because the rules decide whether the Seat may exist
  before Postgres hears about it, and the rules need something to decide about.
  """
  @spec insert_seat(
          Ecto.UUID.t(),
          Ecto.UUID.t(),
          String.t(),
          String.t(),
          Ecto.UUID.t() | nil
        ) ::
          {:ok, Seat.t()} | {:error, Ecto.Changeset.t() | term()}
  def insert_seat(room_id, id, name, device_token, partner_id \\ nil) do
    Repo.transaction(fn ->
      seat_attrs = %{
        id: id,
        room_id: room_id,
        name: name,
        device_tokens: [device_token],
        partner_id: partner_id
      }

      case %Seat{} |> Seat.changeset(seat_attrs) |> Repo.insert() do
        {:ok, seat} ->
          if partner_id do
            case Repo.get_by(Seat, id: partner_id, room_id: room_id) do
              nil ->
                Repo.rollback(:no_such_partner)

              partner_seat ->
                if partner_seat.partner_id && partner_seat.partner_id != id do
                  clear_partner(room_id, partner_seat.partner_id)
                end

                partner_seat
                |> Seat.pair_changeset(id)
                |> Repo.update!()

                seat
            end
          else
            seat
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
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

  @doc "Updates Room facts (speaker, voice, music)."
  @spec update_room(Room.t(), map()) :: {:ok, Room.t()} | {:error, Ecto.Changeset.t()}
  def update_room(%Room{} = room, attrs) do
    room
    |> Room.facts_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Pairs two seats together as partners in a Side.
  In a 4-seat room, automatically pairs the remaining two seats into the other Side.
  If seat_id_2 is nil, unpairs seat_id_1.
  """
  @spec pair_seats(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t() | nil) ::
          {:ok, term()} | {:error, term()}
  def pair_seats(room_id, seat_id_1, seat_id_2 \\ nil) do
    if seat_id_1 == seat_id_2 and not is_nil(seat_id_2) do
      {:error, :cannot_pair_self}
    else
      Repo.transaction(fn ->
        seat_1 = Repo.get_by(Seat, id: seat_id_1, room_id: room_id)

        if is_nil(seat_1) do
          Repo.rollback(:no_such_seat)
        end

        if is_nil(seat_id_2) do
          clear_partner(room_id, seat_1.partner_id)

          updated_seat_1 = seat_1 |> Seat.pair_changeset(nil) |> Repo.update!()
          {updated_seat_1, nil}
        else
          seat_2 = Repo.get_by(Seat, id: seat_id_2, room_id: room_id)

          if is_nil(seat_2) do
            Repo.rollback(:no_such_seat)
          end

          from(s in Seat,
            where:
              s.room_id == ^room_id and (s.partner_id == ^seat_id_1 or s.partner_id == ^seat_id_2)
          )
          |> Repo.update_all(set: [partner_id: nil])

          {:ok, updated_seat_1} =
            seat_1 |> Seat.changeset(%{partner_id: seat_id_2}) |> Repo.update()

          {:ok, updated_seat_2} =
            seat_2 |> Seat.changeset(%{partner_id: seat_id_1}) |> Repo.update()

          all_seats = Repo.all(from(s in Seat, where: s.room_id == ^room_id))

          other_paired =
            if length(all_seats) == 4 do
              other_seats = Enum.reject(all_seats, &(&1.id in [seat_id_1, seat_id_2]))

              if length(other_seats) == 2 do
                [other_seat_1, other_seat_2] = other_seats

                {:ok, updated_other_1} =
                  other_seat_1 |> Seat.changeset(%{partner_id: other_seat_2.id}) |> Repo.update()

                {:ok, updated_other_2} =
                  other_seat_2 |> Seat.changeset(%{partner_id: other_seat_1.id}) |> Repo.update()

                [updated_other_1, updated_other_2]
              else
                []
              end
            else
              []
            end

          [updated_seat_1, updated_seat_2 | other_paired]
        end
      end)
    end
  end

  @doc """
  Unpairs a seat from its partner.
  """
  @spec unpair_seat(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, [Seat.t()]} | {:error, term()}
  def unpair_seat(room_id, _seat_id) do
    Repo.transaction(fn ->
      from(s in Seat, where: s.room_id == ^room_id)
      |> Repo.update_all(set: [partner_id: nil])

      Repo.all(from(s in Seat, where: s.room_id == ^room_id))
    end)
  end

  defp clear_partner(_room_id, nil), do: :ok

  defp clear_partner(room_id, partner_id) do
    from(s in Seat, where: s.id == ^partner_id and s.room_id == ^room_id)
    |> Repo.update_all(set: [partner_id: nil])
  end
end
