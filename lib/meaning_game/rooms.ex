defmodule MeaningGame.Rooms do
  @moduledoc """
  The Room's interface: open it, join, rejoin, snapshot, subscribe.

  Everything the game does to a Room goes through here, and the LiveViews are
  written against nothing else. The process, the registry, the supervisor, and
  Postgres are all behind it.

  **Reconnect is a snapshot, never a replay.** A phone that locked, a tab that
  was closed, a laptop that slept — each comes back by asking for the whole
  current view, so there is no missed-message log to catch up on and no
  reconnect path separate from the ordinary one.

  Joining takes a name and nothing else: no account, no password, no email
  (ADR-0007). The name is the identity inside the Room and the device token is
  the shortcut that skips retyping it.
  """

  alias MeaningGame.Rooms.NoSuchRoomError
  alias MeaningGame.Rooms.Room
  alias MeaningGame.Rooms.Seat
  alias MeaningGame.Rooms.Server

  @doc "The Room the bare URL opens — the couch."
  def default_slug, do: Application.fetch_env!(:meaning_game, :default_room_slug)

  @doc """
  How many Seats a Room holds when it is first opened.

  Configuration rather than a constant: the two-player couch is the first Room
  this game has, not the only shape it can take.
  """
  def default_seat_limit, do: Application.fetch_env!(:meaning_game, :seats_per_room)

  @doc """
  Opens the Room with this slug, and returns the slug.

  Raises `MeaningGame.Rooms.NoSuchRoomError`, which Phoenix renders as a 404, if
  the slug is not one a Room could have — a mistyped URL should find nothing
  rather than conjure a Room out of whatever was typed.
  """
  @spec open!(String.t()) :: String.t()
  def open!(slug) do
    case ensure_started(slug) do
      {:ok, _pid} -> slug
      {:error, _reason} -> raise NoSuchRoomError, slug: slug
    end
  end

  @doc """
  Starts the Room with this slug if it is not already running, and returns its
  process either way.

  A Room that has never been opened is created holding `default_seat_limit/0`
  Seats; one that already exists keeps the number of Seats it was opened with.
  """
  @spec ensure_started(String.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(slug) do
    if is_binary(slug) and Regex.match?(Room.slug_format(), slug) do
      start_room(slug)
    else
      {:error, :bad_slug}
    end
  end

  defp start_room(slug) do
    DynamicSupervisor.start_child(
      MeaningGame.Rooms.Supervisor,
      {Server, slug: slug, seat_limit: default_seat_limit()}
    )
    |> case do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Takes a Seat in the Room under `name`, for the browser holding `device_token`.

  Returns the Seat that browser already holds if it has one, or the Seat held
  under that name if someone is coming back on a browser that forgot its token.
  Only a genuinely new player can be turned away for want of a Seat.
  """
  @spec join(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :name_required | :name_too_long | :room_full | :could_not_join}
  def join(slug, name, device_token) do
    with {:ok, name} <- check_name(name) do
      call(slug, {:join, name, device_token})
    end
  end

  @doc """
  Writes one Seat's Bridge into the Page, for good.

  A Bridge is private until every Seat has committed one, and the last commit is
  what sets the reveal going — the Assayer is asked about every pair at once and
  the beat starts alongside it. Neither happens here: they are the Room's to
  perform, and this call returns the moment the rules have accepted the word.
  """
  @spec commit_bridge(String.t(), String.t(), String.t()) ::
          :ok
          | {:error, :not_bridging | :no_such_seat | :already_committed | :bridge_required}
  def commit_bridge(slug, seat_id, bridge), do: call(slug, {:commit_bridge, seat_id, bridge})

  @doc """
  Carries the failed Bridges forward and starts the next attempt at the same
  Page.

  Any Seat may tap it, because the couple are on one couch and the reveal is
  over for both of them at once. A Page that has closed refuses: five attempts
  is five attempts.
  """
  @spec next_attempt(String.t(), String.t()) ::
          :ok | {:error, :not_revealed | :page_closed | :no_such_seat}
  def next_attempt(slug, seat_id), do: call(slug, {:next_attempt, seat_id})

  @doc """
  Proposes an overrule of the current reveal from one Seat.
  """
  @spec propose_overrule(String.t(), String.t(), keyword()) ::
          :ok | {:error, :not_revealed | :no_such_seat | :proposal_pending | :already_overruled}
  def propose_overrule(slug, seat_id, opts \\ []),
    do: call(slug, {:propose_overrule, seat_id, opts})

  @doc """
  Agrees to a pending overrule proposal from one Seat.
  """
  @spec agree_overrule(String.t(), String.t()) ::
          :ok | {:error, :no_such_seat | :no_proposal_pending}
  def agree_overrule(slug, seat_id), do: call(slug, {:agree_overrule, seat_id})

  @doc """
  Declines a pending overrule proposal from one Seat.
  """
  @spec decline_overrule(String.t(), String.t()) ::
          :ok | {:error, :no_such_seat | :no_proposal_pending}
  def decline_overrule(slug, seat_id), do: call(slug, {:decline_overrule, seat_id})

  @doc """
  "One more?" — a fresh Page in the same Room, with the same Seats.

  Only from a Page that has closed, so that the tap can never take a Page away
  from the couple in the middle of one.
  """
  @spec next_page(String.t(), String.t()) :: :ok | {:error, :page_open | :no_such_seat}
  def next_page(slug, seat_id), do: call(slug, {:next_page, seat_id})

  @doc "The Seat this browser already holds in the Room, without typing a name."
  @spec rejoin(String.t(), String.t()) :: {:ok, map()} | :error
  def rejoin(slug, device_token), do: call(slug, {:rejoin, device_token})

  @doc """
  The whole current view for one viewer — a Seat id, or `nil` for a viewer that
  holds no Seat, such as the stage.

  This is the reconnect mechanism. A view that has been away for any reason asks
  for this and is caught up.
  """
  @spec snapshot(String.t(), String.t() | nil) :: map()
  def snapshot(slug, viewer), do: call(slug, {:snapshot, viewer})

  @doc "Subscribes the caller to `:room_changed` messages for this Room."
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(slug), do: Phoenix.PubSub.subscribe(MeaningGame.PubSub, topic(slug))

  @doc false
  def topic(slug), do: "room:" <> slug

  defp check_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> {:error, :name_required}
      String.length(trimmed) > Seat.name_max() -> {:error, :name_too_long}
      true -> {:ok, trimmed}
    end
  end

  defp check_name(_name), do: {:error, :name_required}

  # Every call starts the Room first, so a Room that crashed between one request
  # and the next is simply back rather than an error the caller has to handle.
  defp call(slug, message) do
    {:ok, _pid} = ensure_started(slug)
    GenServer.call(Server.via(slug), message)
  end
end
