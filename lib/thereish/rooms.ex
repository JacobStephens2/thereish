defmodule Thereish.Rooms do
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

  alias Thereish.Chronicle
  alias Thereish.Rooms.Code
  alias Thereish.Rooms.NoSuchRoomError
  alias Thereish.Rooms.RateLimit
  alias Thereish.Rooms.Room
  alias Thereish.Rooms.Seat
  alias Thereish.Rooms.Server
  alias Thereish.Rooms.Store
  alias Thereish.Steward

  @doc """
  The Room the exports and the mix tasks mean when nobody names one.

  The couch is a Room like any other now that the bare URL is the front page;
  this is only the answer to "which Room did you mean" on the command line.
  """
  def default_slug, do: Application.fetch_env!(:thereish, :default_room_slug)

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
  def default_seat_limit, do: Application.fetch_env!(:thereish, :seats_per_room)

  @doc """
  The Seat counts a Room may be created with: two at the least, and at most the
  seat cap a reveal can hold on a phone.
  """
  @spec seat_counts() :: Range.t()
  def seat_counts, do: 2..Thereish.Steward.seat_cap()

  @doc """
  Opens a new count-free Room at the seat cap and returns its Code.
  """
  @spec create(String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def create(device_token) when is_binary(device_token) or is_nil(device_token) do
    create(Thereish.Steward.seat_cap(), device_token, [])
  end

  @spec create(String.t() | nil, keyword()) :: {:ok, String.t()} | {:error, term()}
  def create(device_token, opts)
      when (is_binary(device_token) or is_nil(device_token)) and is_list(opts) do
    create(Thereish.Steward.seat_cap(), device_token, opts)
  end

  @spec create(pos_integer(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def create(seat_count, device_token) when is_integer(seat_count) do
    create(seat_count, device_token, [])
  end

  def create(_seat_count, _device_token), do: {:error, :bad_seat_count}

  @spec create(pos_integer(), String.t() | nil, keyword()) :: {:ok, String.t()} | {:error, term()}
  def create(seat_count, device_token, opts)
      when is_integer(seat_count) and is_list(opts) do
    if seat_count in seat_counts() do
      address = Keyword.get(opts, :address)

      with :ok <- RateLimit.hit(device_token, address) do
        device_rooms =
          if is_binary(device_token), do: Store.rooms_for_device(device_token), else: []

        case digests_for_rooms(device_rooms) do
          [] ->
            # No history: draws a random word and makes one quip-only request under naming deadline
            with {:ok, code} <- create_without_history(seat_count) do
              if is_binary(device_token) and device_rooms == [] do
                Thereish.Notice.notify_new_room(code, seat_count)
              end

              {:ok, code}
            end

          digests ->
            name_with_scribe_or_fallback(seat_count, digests)
        end
      end
    else
      {:error, :bad_seat_count}
    end
  end

  def create(_seat_count, _device_token, _opts), do: {:error, :bad_seat_count}

  defp digests_for_rooms(rooms) do
    rooms
    |> Enum.uniq_by(fn %{room: room} -> room.id end)
    |> Enum.map(fn %{room: room} -> Chronicle.history_digest(room.id) end)
    |> Enum.reject(&is_nil/1)
  end

  defp name_with_scribe_or_fallback(seat_count, digests) do
    taken = Store.taken_codes()

    case Steward.name_room(digests, taken) do
      {:ok, %{word: code, quip: quip}} when is_binary(code) ->
        insert_or_fallback(code, seat_count, quip)

      {:ok, code} when is_binary(code) ->
        insert_or_fallback(code, seat_count, nil)

      _ ->
        insert_with_a_free_code(seat_count, @code_draws)
    end
  end

  # A drawn word with no history makes one quip-only request under the naming deadline
  defp create_without_history(seat_count) do
    case draw_untaken_code(@code_draws) do
      {:ok, code} ->
        quip =
          case Steward.quip_code(code) do
            {:ok, q} when is_binary(q) -> q
            _ -> nil
          end

        insert_or_fallback(code, seat_count, quip)

      {:error, :no_free_code} ->
        {:error, :no_free_code}
    end
  end

  defp insert_or_fallback(code, seat_count, quip) do
    case insert_and_start(code, seat_count, quip) do
      {:ok, code} -> {:ok, code}
      {:error, _changeset} -> insert_with_a_free_code(seat_count, @code_draws)
    end
  end

  defp draw_untaken_code(0), do: {:error, :no_free_code}

  defp draw_untaken_code(draws_left) do
    code = Code.draw()
    taken = Store.taken_codes()

    if code in taken do
      draw_untaken_code(draws_left - 1)
    else
      {:ok, code}
    end
  end

  # A drawn word that somebody else already took is drawn again, and nothing
  # else is. There are thousands of four-letter words and a household will never
  # crowd them, so a handful of draws is a ceiling that exists only so a bug
  # cannot spin here.
  defp insert_with_a_free_code(_seat_count, 0), do: {:error, :no_free_code}

  defp insert_with_a_free_code(seat_count, draws_left) do
    case insert_and_start(Code.draw(), seat_count, nil) do
      {:ok, code} ->
        {:ok, code}

      {:error, changeset} ->
        if code_taken?(changeset) do
          insert_with_a_free_code(seat_count, draws_left - 1)
        else
          {:error, changeset}
        end
    end
  end

  defp insert_and_start(code, seat_count, quip) do
    with normalized when is_binary(normalized) <- Code.normalise(code),
         {:ok, room} <- Store.insert_room(normalized, seat_count, quip) do
      case start_room(room.slug) do
        {:ok, _pid} ->
          {:ok, normalized}

        error ->
          Thereish.Repo.delete(room)
          error
      end
    end
  end

  defp code_taken?(%Ecto.Changeset{errors: errors}), do: Keyword.has_key?(errors, :slug)

  @doc """
  Opens the Room with this Code, and returns the Code in its stored form.

  Raises `Thereish.Rooms.NoSuchRoomError`, which Phoenix renders as a 404, if
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

  Identity, not the home list. A Room this browser has hidden is still here:
  the Seat and the device association that finds it have not gone anywhere.
  """
  @spec for_device(String.t()) :: [%{room: Room.t(), seat: Seat.t()}]
  def for_device(device_token), do: Store.rooms_for_device(device_token)

  @doc """
  Every Room this browser holds a Seat in that it has not hidden, newest first.

  The front page's one-tap way back in. Hiding a Room drops it from this list
  without touching `for_device/1`.
  """
  @spec listed_for_device(String.t()) :: [%{room: Room.t(), seat: Seat.t()}]
  def listed_for_device(device_token), do: Store.rooms_listed_for_device(device_token)

  @doc """
  Hides a Room from this browser's home list.

  The Seat, the Chronicle, and the device association stay. The Code still
  opens the same Seat. Another browser's list is a different token.
  """
  @spec hide(String.t(), String.t()) :: :ok | {:error, :no_such_room | term()}
  def hide(slug, device_token) when is_binary(device_token) do
    with normalised when is_binary(normalised) <- Code.normalise(slug),
         %Room{} = room <- Store.get_room(normalised) do
      case Store.hide_from_device(room.id, device_token) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :no_such_room}
    end
  end

  defp start_room(code) do
    DynamicSupervisor.start_child(Thereish.Rooms.Supervisor, {Server, slug: code})
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
  is five attempts. A reveal that is still being absorbed refuses until the
  Room's shared hold has elapsed.
  """
  @spec next_attempt(String.t(), String.t()) ::
          :ok | {:error, :not_revealed | :page_closed | :no_such_seat | :reveal_held}
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
  Taps bookends at closed phase (flat, fine, or great).
  """
  @spec tap_bookends(String.t(), String.t(), String.t() | atom()) ::
          :ok | {:error, term()}
  def tap_bookends(code, seat_id, label),
    do: call(code, {:tap_bookends, seat_id, label})

  @doc """
  "One more?" — a fresh Page in the same Room, with the same Seats.

  Only from a Page that has closed, so that the tap can never take a Page away
  from the couple in the middle of one. A closing reveal that is still being
  absorbed refuses until the Room's shared hold has elapsed.
  """
  @spec next_page(String.t(), String.t()) ::
          :ok | {:error, :page_open | :no_such_seat | :reveal_held}
  def next_page(slug, seat_id), do: call(slug, {:next_page, seat_id})

  @doc """
  Commits a setting (Give) for the upcoming Page.
  """
  @spec give(String.t(), String.t(), String.t()) ::
          :ok | {:error, :give_required | :no_such_seat | term()}
  def give(slug, seat_id, give), do: call(slug, {:give, seat_id, give})

  @doc """
  Starts the Page with the Gives committed so far.
  """
  @spec start_page(String.t(), String.t()) :: :ok | {:error, term()}
  def start_page(code, seat_id), do: call(code, {:start_page, seat_id})

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
  Claims the speaker for `device_token`.

  A claim from the current speaker is a no-op.
  """
  @spec claim_speaker(String.t(), String.t()) :: :ok | {:error, term()}
  def claim_speaker(code, device_token),
    do: call(code, {:room_fact, {:claim_speaker, device_token}})

  @doc """
  Starts sound on the Stage's opening tap, claiming the speaker and,
  on a Room with no Chronicle behind it, beginning the Prologue.
  """
  @spec start_sound(String.t(), String.t()) :: :ok | {:error, term()}
  def start_sound(code, device_token), do: call(code, {:room_fact, {:start_sound, device_token}})

  @doc """
  Releases the speaker.

  Releasing with a token other than the current speaker is a no-op.
  """
  @spec release_speaker(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def release_speaker(code, device_token \\ nil),
    do: call(code, {:room_fact, {:release_speaker, device_token}})

  @doc "Sets the quips on/off switch."
  @spec set_quips(String.t(), boolean()) :: :ok | {:error, term()}
  def set_quips(code, enabled) when is_boolean(enabled),
    do: call(code, {:room_fact, {:set, :quips, enabled}})

  @doc "Sets the Full table on/off switch."
  @spec set_full_table(String.t(), boolean()) :: :ok | {:error, term()}
  def set_full_table(code, enabled) when is_boolean(enabled),
    do: call(code, {:room_fact, {:set, :full_table, enabled}})

  @doc """
  Flips the Quips or Full table switch from the Room's own value, so two
  devices tapping at once land where they started rather than cancelling out.
  """
  @spec toggle(String.t(), :quips | :full_table) :: :ok | {:error, term()}
  def toggle(code, switch) when switch in [:quips, :full_table],
    do: call(code, {:room_fact, {:toggle, switch}})

  @doc "Skips the Prologue for this Room, remembering the skip as a Room fact."
  @spec skip_prologue(String.t()) :: :ok | {:error, term()}
  def skip_prologue(code), do: call(code, {:room_fact, :skip_prologue})

  @doc "Plays the Prologue on demand for this Room."
  @spec play_prologue(String.t()) :: :ok | {:error, term()}
  def play_prologue(code), do: call(code, {:room_fact, :play_prologue})

  @doc "Sets the music switch: 'off', 'house', or 'page'."
  @spec set_music(String.t(), String.t() | atom()) :: :ok | {:error, term()}
  def set_music(code, music), do: call(code, {:room_fact, {:set_music, music}})

  @doc """
  Skips the current wait music (Repertoire draw or holdover) and advances the deal.
  No-op from a non-speaking device, if only one member remains, or refused if
  this Page's Track is on the Speaker.
  """
  @spec next(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def next(code, device_token \\ nil), do: call(code, {:next, device_token})

  @doc """
  Refuses the current Repertoire member (wait music, holdover, or this Page's Track) forever in this Room.
  No-op from a non-speaking device; refused if it is the last remaining playable member.
  """
  @spec never(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def never(code, device_token \\ nil), do: call(code, {:never, device_token})

  @doc """
  Fetches the voice audio bytes and format for `attempt` from the Room.

  `kind` is `:bookends` (the Attempt's announcement) or `:verdict` (the Assayer
  at the reveal). Answers `{:ok, audio, format}` or `{:error, :not_found}`.
  """
  @spec voice_audio(String.t(), integer(), atom()) ::
          {:ok, binary(), atom() | String.t()} | {:error, :not_found}
  def voice_audio(code, attempt, kind \\ :verdict) when is_integer(attempt) do
    case ensure_started(code) do
      {:ok, normalised, _pid} ->
        GenServer.call(Server.via(normalised), {:voice_audio, attempt, kind})

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
  def subscribe(slug), do: Phoenix.PubSub.subscribe(Thereish.PubSub, topic(slug))

  @doc """
  Tells everyone watching this Room that something happened to it.

  For the things that happen to a Room from outside its own process — the
  Scribe filing a recap, minutes after the Room stopped thinking about that
  Page.
  """
  @spec broadcast(String.t(), atom()) :: :ok | {:error, term()}
  def broadcast(slug, message),
    do: Phoenix.PubSub.broadcast(Thereish.PubSub, topic(slug), message)

  @doc false
  def topic(slug), do: "room:" <> slug

  @doc """
  Returns true if the Room process is running and its Phase is bridging, assaying, or reveal.
  """
  @spec in_play?(Room.t() | String.t() | pid() | any()) :: boolean()
  def in_play?(%Room{slug: code}), do: in_play?(code)

  def in_play?(code_or_id) when is_binary(code_or_id) do
    if uuid?(code_or_id) do
      case Thereish.Repo.get(Room, code_or_id) do
        nil -> false
        room -> in_play?(room.slug)
      end
    else
      case Code.normalise(code_or_id) do
        nil ->
          false

        normalized ->
          case GenServer.whereis(Server.via(normalized)) do
            pid when is_pid(pid) -> in_play?(pid)
            nil -> false
          end
      end
    end
  end

  def in_play?(pid) when is_pid(pid) do
    try do
      GenServer.call(pid, :in_play?, 1_000)
    catch
      :exit, _ -> false
    end
  end

  def in_play?(_), do: false

  @doc """
  Counts how many Pages are in play across all running Room processes.
  """
  @spec in_play_count() :: non_neg_integer()
  def in_play_count do
    Thereish.Rooms.Registry
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [:"$2"]}])
    |> Enum.count(&in_play?/1)
  end

  @doc """
  Answers the count of Pages in play for one Room (0 or 1).
  """
  @spec in_play_count(Room.t() | Ecto.UUID.t() | String.t()) :: 0 | 1
  def in_play_count(room_or_code_or_id) do
    if in_play?(room_or_code_or_id), do: 1, else: 0
  end

  @doc """
  Formats the in-play sentence for the spend page and Chronicle foot.
  Omitted (nil) when count is 0.
  """
  @spec in_play_sentence(non_neg_integer()) :: String.t() | nil
  def in_play_sentence(0), do: nil
  def in_play_sentence(1), do: "1 Page in play, not yet counted"
  def in_play_sentence(n) when is_integer(n) and n > 1, do: "#{n} Pages in play, not yet counted"

  defp uuid?(val) when is_binary(val) do
    Regex.match?(
      ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
      val
    )
  end

  defp uuid?(_), do: false

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
