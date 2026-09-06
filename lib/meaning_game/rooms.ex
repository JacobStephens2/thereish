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

  # How many times a Code is drawn before creation gives up.
  @code_draws 20

  alias MeaningGame.Chronicle
  alias MeaningGame.Rooms.Code
  alias MeaningGame.Rooms.NoSuchRoomError
  alias MeaningGame.Rooms.Room
  alias MeaningGame.Rooms.Seat
  alias MeaningGame.Rooms.Server
  alias MeaningGame.Rooms.Store
  alias MeaningGame.Steward

  @doc """
  The Room the exports and the mix tasks mean when nobody names one.

  The couch is a Room like any other now that the bare URL is the front page;
  this is only the answer to "which Room did you mean" on the command line.
  """
  def default_slug, do: Application.fetch_env!(:meaning_game, :default_room_slug)

  @doc "The Room with this Code, or nil."
  @spec get_room(String.t()) :: Room.t() | nil
  def get_room(code) do
    with normalised when is_binary(normalised) <- Code.normalise(code) do
      Store.get_room(normalised)
    end
  end

  @doc "Every Room in the database."
  @spec list_rooms() :: [Room.t()]
  def list_rooms, do: Store.list_rooms()

  @doc """
  How many Seats the New Room form offers by default.

  Configuration rather than a constant: the two-player couch is the first Room
  this game has, not the only shape it can take. It is a default on a form and
  nothing else — a Room's Seats are chosen by whoever creates it.
  """
  def default_seat_limit, do: Application.fetch_env!(:meaning_game, :seats_per_room)

  @doc """
  The Seat counts a Room may be created with: two at the least, and at most what
  one reveal can hold on a phone.
  """
  @spec seat_counts() :: Range.t()
  def seat_counts, do: 2..MeaningGame.Steward.seat_cap()

  @doc """
  Opens a new Room of `player_count` Seats and returns its Code.

  Rooms are created, never conjured. Nothing else in this interface brings one
  into being: every other call finds a Room that somebody made here, which is
  why a mistyped Code is a 404 rather than an empty Room nobody meant.

  `device_token` is the creating phone's, which is what the Scribe will read to
  name the Room after the Rooms that phone has played in. A phone with no
  history draws a random word.
  """
  @spec create(pos_integer(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def create(player_count, device_token)

  def create(player_count, device_token) when is_integer(player_count) do
    if player_count in seat_counts() do
      case digests_for_device(device_token) do
        [] ->
          # No history: makes no model call and draws a random word
          insert_with_a_free_code(player_count, @code_draws)

        digests ->
          name_with_scribe_or_fallback(player_count, digests)
      end
    else
      {:error, :bad_player_count}
    end
  end

  def create(_player_count, _device_token), do: {:error, :bad_player_count}

  defp digests_for_device(nil), do: []

  defp digests_for_device(device_token) do
    device_token
    |> Store.rooms_for_device()
    |> Enum.map(fn %{room: room} -> Chronicle.digest(room.id) end)
    |> Enum.reject(&String.starts_with?(&1, "Nothing yet"))
  end

  defp name_with_scribe_or_fallback(player_count, digests) do
    taken = Store.taken_codes()

    case Steward.name_room(digests, taken) do
      {:ok, code} when is_binary(code) ->
        case Store.insert_room(code, player_count) do
          {:ok, room} ->
            with {:ok, _pid} <- start_room(room.slug), do: {:ok, room.slug}

          {:error, _changeset} ->
            insert_with_a_free_code(player_count, @code_draws)
        end

      _ ->
        insert_with_a_free_code(player_count, @code_draws)
    end
  end

  # A drawn word that somebody else already took is drawn again, and nothing
  # else is. There are thousands of four-letter words and a household will never
  # crowd them, so a handful of draws is a ceiling that exists only so a bug
  # cannot spin here.
  defp insert_with_a_free_code(_player_count, 0), do: {:error, :no_free_code}

  defp insert_with_a_free_code(player_count, draws_left) do
    case Store.insert_room(Code.draw(), player_count) do
      {:ok, room} ->
        with {:ok, _pid} <- start_room(room.slug), do: {:ok, room.slug}

      {:error, changeset} ->
        if code_taken?(changeset) do
          insert_with_a_free_code(player_count, draws_left - 1)
        else
          {:error, changeset}
        end
    end
  end

  defp code_taken?(%Ecto.Changeset{errors: errors}), do: Keyword.has_key?(errors, :slug)

  @doc """
  Opens the Room with this Code, and returns the Code in its stored form.

  Raises `MeaningGame.Rooms.NoSuchRoomError`, which Phoenix renders as a 404, if
  no Room has it — a Code nobody created should find nothing rather than conjure
  a Room out of whatever was typed.
  """
  @spec open!(String.t()) :: String.t()
  def open!(code) do
    case ensure_started(code) do
      {:ok, code, _pid} -> code
      {:error, _reason} -> raise NoSuchRoomError, slug: code
    end
  end

  @doc """
  Starts the Room with this Code if it is not already running, and returns its
  stored Code and its process.

  A Code that no Room has is `{:error, :no_such_room}`, and a Code no Room could
  have is `{:error, :bad_code}`. Neither creates anything.
  """
  @spec ensure_started(term()) :: {:ok, String.t(), pid()} | {:error, :bad_code | :no_such_room}
  def ensure_started(code) do
    case Code.normalise(code) do
      nil ->
        {:error, :bad_code}

      code ->
        # A Room already running is a Room that exists, so the every-event path
        # through `call/2` costs a registry lookup rather than a query.
        case GenServer.whereis(Server.via(code)) do
          pid when is_pid(pid) -> {:ok, code, pid}
          nil -> start_if_it_exists(code)
        end
    end
  end

  defp start_if_it_exists(code) do
    if Store.get_room(code) do
      with {:ok, pid} <- start_room(code), do: {:ok, code, pid}
    else
      {:error, :no_such_room}
    end
  end

  @doc """
  Every Room this browser holds a Seat in, newest first, each with the Seat.

  The front page's one-tap way back in.
  """
  @spec for_device(String.t()) :: [%{room: Room.t(), seat: Seat.t()}]
  def for_device(device_token), do: Store.rooms_for_device(device_token)

  defp start_room(code) do
    DynamicSupervisor.start_child(MeaningGame.Rooms.Supervisor, {Server, slug: code})
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
  what sets the reveal going — the Assayer is asked about every Bridge at once,
  and the beat starts alongside it. Neither happens here: they are the Room's to
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
  Records one player fairness tap for the current reveal.
  """
  @spec record_fairness_tap(String.t(), String.t(), String.t() | atom()) ::
          :ok | {:error, term()}
  def record_fairness_tap(slug, seat_id, label),
    do: call(slug, {:record_fairness_tap, seat_id, label})

  @doc """
  "One more?" — a fresh Page in the same Room, with the same Seats.

  Only from a Page that has closed, so that the tap can never take a Page away
  from the couple in the middle of one.
  """
  @spec next_page(String.t(), String.t()) :: :ok | {:error, :page_open | :no_such_seat}
  def next_page(slug, seat_id), do: call(slug, {:next_page, seat_id})

  @doc """
  Commits a setting (Give) for the upcoming Page.
  """
  @spec give(String.t(), String.t(), String.t()) ::
          :ok | {:error, :give_required | :no_such_seat | term()}
  def give(slug, seat_id, give), do: call(slug, {:give, seat_id, give})

  @doc """
  Retries writing the Page through the Author after a failure.
  """
  @spec retry_author(String.t(), String.t()) :: :ok | {:error, term()}
  def retry_author(slug, seat_id), do: call(slug, {:retry_author, seat_id})

  @doc """
  Resets Gives so players can enter new settings after an Author failure.
  """
  @spec reset_gives(String.t(), String.t()) :: :ok | {:error, term()}
  def reset_gives(slug, seat_id), do: call(slug, {:reset_gives, seat_id})

  @doc """
  Deliberately unblinds an experiment in the Room (ticket 13).
  """
  @spec unblind_experiment(String.t(), String.t() | nil, String.t()) :: :ok | {:error, term()}
  def unblind_experiment(slug, seat_id, experiment_id \\ "bait_against_plain") do
    call(slug, {:unblind_experiment, seat_id, experiment_id})
  end

  @doc """
  Claims the speaker for `device_token`.

  A claim from the current speaker is a no-op.
  """
  @spec claim_speaker(String.t(), String.t()) :: :ok | {:error, term()}
  def claim_speaker(code, device_token), do: call(code, {:claim_speaker, device_token})

  @doc """
  Releases the speaker.

  Releasing with a token other than the current speaker is a no-op.
  """
  @spec release_speaker(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def release_speaker(code, device_token \\ nil), do: call(code, {:release_speaker, device_token})

  @doc "Sets the voice on/off switch."
  @spec set_voice(String.t(), boolean()) :: :ok | {:error, term()}
  def set_voice(code, enabled), do: call(code, {:set_voice, enabled})

  @doc "Sets the house-loop-only on/off switch."
  @spec set_house_loop_only(String.t(), boolean()) :: :ok | {:error, term()}
  def set_house_loop_only(code, enabled), do: call(code, {:set_house_loop_only, enabled})

  @doc """
  Fetches the voice audio bytes and format for `attempt` from the Room.
  Answers `{:ok, audio, format}` or `{:error, :not_found}`.
  """
  @spec voice_audio(String.t(), integer()) ::
          {:ok, binary(), atom() | String.t()} | {:error, :not_found}
  def voice_audio(code, attempt) when is_integer(attempt) do
    case ensure_started(code) do
      {:ok, normalised, _pid} ->
        GenServer.call(Server.via(normalised), {:voice_audio, attempt})

      {:error, _} ->
        {:error, :not_found}
    end
  end

  @doc "The Seat this browser already holds in the Room, without typing a name."
  @spec rejoin(String.t(), String.t()) :: {:ok, map()} | :error
  def rejoin(slug, device_token), do: call(slug, {:rejoin, device_token})

  @doc """
  The whole current view for one viewer — a Seat id, or `nil` for a viewer that
  holds no Seat, such as the stage. Takes an optional `device_token` so the
  snapshot can answer whether this viewer is the Room's speaker.

  This is the reconnect mechanism. A view that has been away for any reason asks
  for this and is caught up.
  """
  @spec snapshot(String.t(), String.t() | nil, String.t() | nil) :: map()
  def snapshot(slug, viewer, device_token \\ nil),
    do: call(slug, {:snapshot, viewer, device_token})

  @doc """
  Subscribes the caller to this Room's messages.

  Two of them: `:room_changed`, which every screen showing the Room redraws on,
  and `:chronicle_changed`, which only the book has anything to do with.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(slug), do: Phoenix.PubSub.subscribe(MeaningGame.PubSub, topic(slug))

  @doc """
  Tells everyone watching this Room that something happened to it.

  For the things that happen to a Room from outside its own process — the
  Scribe filing a recap, minutes after the Room stopped thinking about that
  Page.
  """
  @spec broadcast(String.t(), atom()) :: :ok | {:error, term()}
  def broadcast(slug, message),
    do: Phoenix.PubSub.broadcast(MeaningGame.PubSub, topic(slug), message)

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
  defp call(code, message) do
    {:ok, code, _pid} = ensure_started(code)
    GenServer.call(Server.via(code), message)
  end
end
