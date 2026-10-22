defmodule Thereish.Game do
  @moduledoc """
  The rules, as a pure reducer over a list of Seats.

  Three functions and no I/O: build the initial state, apply an event, project
  what one viewer may see. It starts no timers, opens no sockets, and calls no
  models — a verdict arrives here as an event, never as a call this module
  makes. That is what lets a whole Page be driven in a test as a list of events,
  and it is why the Room, not the Game, owns time.

  Seats are a **list of N**, two by default, never a pair. Every rule that could
  be written for two players is written for the list, so Jackbox-shaped group
  play is a configuration change rather than a rewrite (ADR-0007). Scoring is
  the clearest case: an Attempt's Bridges are read together and answered with
  **one Verdict** — one number for how far the table is from one mind — which at
  two Seats is how near two words landed to each other, the rule the couch
  already had (ADR-0010).

  This module knows nothing about devices, browsers, or Postgres. A Seat here is
  just an id and the name its player typed; who is holding it and how they got
  back to it are the Room's problem.

  ## A Page is a ladder of attempts, not one shot

  A miss does not end the Page. Carry-forward still takes the two Bridges the
  Assayer named as furthest apart — Medium's rule, and the two-Bookend rule
  when Full table is off. At a Full table the first Attempt already has one
  Bookend per Seat on the Page (ADR-0016); carrying every Seat's Bridge after a
  miss is the rest of that rule. After `attempt_cap/0` tries the Page closes
  unmelded, and a Meld closes it the moment it lands.

  The Game has a current Attempt (`Thereish.Game.Attempt`) exactly when it has
  a Page, a Game built by `init/1` with a Page included. Everything that starts
  over with an Attempt lives in that one value, and opening one is the only way
  to start it over.

  ## Phase is derived, never stored

  Where a Page has got to is a question about the state rather than a field in
  it: a Room that is not full is `:waiting`, a full Room with a Page is
  `:bridging`, every Bridge in makes it `:assaying`, the Verdict landing — or
  being given up on — makes it `:reveal`, and a reveal that melded or spent the
  last attempt makes it `:closed`. Nothing has to remember to advance it, and in particular nothing
  has to remember to end a Page — which is why a Meld closing one is not an
  event that could go missing.

  One deliberate departure from the spec's sketch of this module: `apply/2` can
  answer `{:error, reason}`, because whether a Bridge may be written is a rule
  and rules live here.
  """

  # `apply/2` is the name the spec gives this function, and the reducer shape is
  # worth more than the Kernel import it displaces.
  import Kernel, except: [apply: 2]

  alias Thereish.Bookends
  alias Thereish.Chronicle.Document
  alias Thereish.Chronicle.Entry
  alias Thereish.Chronicle.Opinion
  alias Thereish.Game.Attempt
  alias Thereish.Ladder
  alias Thereish.Mask
  alias Thereish.Overrule

  @enforce_keys [:seat_limit, :seats]
  defstruct [
    :seat_limit,
    :seats,
    :page,
    :attempt,
    gives: %{},
    last_gives: %{},
    author_failure: nil,
    author_retries_used: 0,
    author_retry_allowance: 1,
    played: [],
    bookends_taps: %{},
    page_seat_ids: nil,
    masks: %{},
    full_table: true
  ]

  @type seat :: %{
          required(:id) => String.t(),
          required(:name) => String.t()
        }
  @typedoc """
  What the Assayer said about one Attempt's Bridges, read together, or that it
  could not say (ADR-0010).

  `quip` is the joke it made about the words these players actually wrote. The
  rules keep it beside the reasoning and never read it: the reveal is the
  product, and the line that makes it funny is not chrome the view can invent
  for itself.

  `furthest` is the two of those Bridges that landed furthest apart, as words.
  The rules do read that one: it is the next Attempt's Bookends.

  `meta` is provenance — which model answered, at what prompt version, how long
  it took, what it cost. The rules carry it to the Chronicle and never read it;
  a grade is a grade whoever produced it.
  """
  @type verdict :: %{
          graded?: boolean(),
          closeness: integer() | nil,
          reasoning: String.t() | nil,
          quip: String.t() | nil,
          furthest: [String.t()] | nil,
          meta: map()
        }

  @typedoc """
  `attempt` is the Attempt being played and `played` the ones this Page already
  played, kept whole so the Chronicle can have them.
  """
  @type t :: %__MODULE__{
          seat_limit: pos_integer(),
          seats: [seat()],
          page: Document.t() | nil,
          attempt: Attempt.t() | nil,
          gives: %{String.t() => String.t()},
          last_gives: %{String.t() => String.t()},
          author_failure: term(),
          author_retries_used: non_neg_integer(),
          author_retry_allowance: non_neg_integer(),
          played: [Attempt.t()],
          bookends_taps: %{String.t() => String.t()},
          page_seat_ids: [String.t()] | nil,
          masks: %{String.t() => Mask.t() | :dot},
          full_table: boolean()
        }

  @type viewer :: String.t() | nil

  @type event ::
          {:seat_joined, seat()}
          | {:give_committed,
             %{
               required(:seat_id) => String.t(),
               required(:give) => String.t()
             }}
          | {:mask_landed,
             %{
               required(:seat_id) => String.t(),
               required(:mask) => Mask.t() | :dot
             }}
          | {:start_page, %{required(:seat_id) => String.t()}}
          | {:page_written,
             %{
               required(:bookends) => [String.t()],
               optional(:from) => [String.t()],
               optional(:meta) => map(),
               optional(:full_table) => boolean()
             }}
          | {:author_failed, %{required(:reason) => term()}}
          | {:author_retried, %{required(:seat_id) => String.t()}}
          | {:gives_reset, %{required(:seat_id) => String.t()}}
          | {:bridge_committed, %{seat_id: String.t(), bridge: String.t()}}
          | {:verdict_received,
             %{
               closeness: integer(),
               reasoning: String.t(),
               quip: String.t(),
               furthest: [String.t()],
               meta: map()
             }}
          | {:verdict_unavailable, %{optional(:meta) => map()}}
          | {:attempt_advanced, %{seat_id: String.t()}}
          | {:next_page, %{seat_id: String.t()}}
          | {:overrule_proposed,
             %{
               required(:seat_id) => String.t(),
               optional(:closeness) => integer()
             }}
          | {:overrule_agreed, %{seat_id: String.t()}}
          | {:overrule_declined, %{seat_id: String.t()}}
          | {:fairness_tapped,
             %{
               required(:seat_id) => String.t(),
               required(:label) => String.t() | atom()
             }}
          | {:bookends_tapped,
             %{
               required(:seat_id) => String.t(),
               required(:label) => String.t() | atom()
             }}

  @typedoc """
  What the Room is asked to do next. Effects are descriptions, never actions:
  this module neither waits out a beat nor calls an Assayer nor writes to
  Postgres, it says that one is owed. `:beat` carries no duration for the same
  reason — how long the theatre runs is the Room's business, and a description
  that carried it would make this module read the clock's configuration.
  """
  @type effect ::
          :beat
          | {:author, %{gives: [map()], count: pos_integer()}}
          | {:assay, %{bookends: [String.t()], bridges: [String.t()]}}
          | {:chronicle, Entry.t()}
          | {:overrule, Overrule.ruling()}
          | {:fairness_tap, map()}
          | {:bookends_tap, map()}

  @type error ::
          :room_full
          | :not_giving
          | :not_writing
          | :give_required
          | :give_too_long
          | :not_failed
          | :retries_spent
          | :not_bridging
          | :no_such_seat
          | :already_committed
          | :bridge_required
          | :no_verdict_expected
          | :not_revealed
          | :not_assayed
          | :not_closed
          | :page_closed
          | :page_open
          | :proposal_pending
          | :no_proposal_pending
          | :already_overruled
          | :invalid_label
          | :no_grade_to_rate
          | :not_enough_gives
          | :not_playing_page

  @doc """
  Builds the state of a Room that holds `seat_limit` Seats, `seats` of them
  already taken, playing `page`.

  Existing Seats are passed in rather than replayed as events, because they come
  from Postgres, where they outlive every process in this system. A Room with no
  Page yet is a Room waiting for one.
  """
  @spec init(keyword()) :: t()
  def init(opts) do
    page = Keyword.get(opts, :page)

    unless is_nil(page) or is_struct(page, Document) do
      raise ArgumentError,
            "a Game's :page is a Thereish.Chronicle.Document, got: #{inspect(page)}"
    end

    seat_limit = Keyword.fetch!(opts, :seat_limit)
    seats = opts |> Keyword.get(:seats, []) |> Enum.map(&seat/1)

    # A Game built with a Page is played by the Seats it was built with.
    page_seat_ids = if page, do: Enum.map(seats, & &1.id)

    full_table = Keyword.get_lazy(opts, :full_table, fn -> page_full_table(page, true) end)

    %__MODULE__{
      seat_limit: seat_limit,
      seats: seats,
      page: page,
      attempt: first_attempt(page),
      gives: %{},
      last_gives: %{},
      author_failure: nil,
      author_retries_used: 0,
      author_retry_allowance: retry_allowance(opts),
      page_seat_ids: page_seat_ids,
      masks: %{},
      full_table: full_table == true
    }
  end

  @doc """
  Sets the Room's Full table rule. A Page already written keeps the rule it
  was written under; the next Page is written under this one.
  """
  @spec set_full_table(t(), boolean()) :: t()
  def set_full_table(%__MODULE__{} = state, enabled) when is_boolean(enabled) do
    %{state | full_table: enabled}
  end

  @doc """
  How many attempts one Page gets before it closes unmelded.

  Named configuration rather than a constant, because five is a guess about how
  long a converging arc stays funny and the couch is what settles it. It is read
  here, inside the rules, for the same reason `Thereish.Ladder`'s band
  boundaries are: the cap and the boundaries are the same kind of thing — numbers
  the couple's play moves — and splitting them so that one is passed in and the
  other is looked up would make the pair harder to calibrate together.
  """
  @spec attempt_cap() :: pos_integer()
  def attempt_cap, do: Application.fetch_env!(:thereish, :attempts_per_page)

  @doc """
  Names a list of words the way the table hears them: two stay "cairn and beacon",
  six become "cairn, beacon, wharf, signal, torch and lamp".
  """
  @spec join_and([String.t() | map()]) :: String.t()
  def join_and(words) when is_list(words) do
    words = Enum.map(words, &join_and_word/1)

    case Enum.reject(words, &(&1 == "")) do
      [] ->
        ""

      [one] ->
        one

      [left, right] ->
        "#{left} and #{right}"

      many ->
        {last, rest} = List.pop_at(many, -1)
        Enum.join(rest, ", ") <> " and " <> last
    end
  end

  defp join_and_word(%{word: word}) when is_binary(word), do: word
  defp join_and_word(%{"word" => word}) when is_binary(word), do: word
  defp join_and_word(word) when is_binary(word), do: word
  defp join_and_word(_), do: ""

  @doc """
  Applies one event, returning the next state and whatever the Room now owes.

  A Seat already in the Room joining again is the ordinary rejoin, and is a
  no-op rather than an error — the Room replays `:seat_joined` on every reconnect
  and must not have to remember whether it already did.
  """
  @spec apply(t(), event()) :: {:ok, t(), [effect()]} | {:error, error()}
  def apply(%__MODULE__{} = state, {:seat_joined, seat}) do
    seat = seat(seat)

    cond do
      seated?(state, seat.id) ->
        {:ok, state, []}

      full?(state) ->
        {:error, :room_full}

      true ->
        {:ok, %{state | seats: state.seats ++ [seat]}, []}
    end
  end

  def apply(%__MODULE__{} = state, {:give_committed, %{seat_id: seat_id} = attrs}) do
    give = attrs[:give] || attrs[:text] || ""
    trimmed = String.trim(give)

    with :ok <- may_give(state, seat_id) do
      cond do
        trimmed == "" ->
          {:error, :give_required}

        String.length(trimmed) > 120 ->
          {:error, :give_too_long}

        true ->
          gives = Map.put(state.gives, seat_id, trimmed)
          last_gives = Map.put(state.last_gives, seat_id, trimmed)
          state = %{state | gives: gives, last_gives: last_gives}

          if full?(state) and map_size(gives) >= state.seat_limit do
            ask_author(state)
          else
            {:ok, state, []}
          end
      end
    end
  end

  def apply(%__MODULE__{} = state, {:mask_landed, %{seat_id: seat_id, mask: mask}})
      when is_struct(mask, Mask) or mask == :dot do
    if seated?(state, seat_id) do
      {:ok, %{state | masks: Map.put(state.masks || %{}, seat_id, mask)}, []}
    else
      {:error, :no_such_seat}
    end
  end

  def apply(%__MODULE__{} = state, {:start_page, %{seat_id: seat_id}}) do
    with :ok <- may_start_page(state, seat_id), do: ask_author(state)
  end

  def apply(%__MODULE__{} = state, {:page_written, bookends, meta}) when is_list(bookends) do
    __MODULE__.apply(state, {:page_written, %{bookends: bookends, meta: meta}})
  end

  def apply(%__MODULE__{} = state, {:page_written, %{bookends: bookends} = attrs}) do
    meta = attrs[:meta] || %{}

    cond do
      state.page != nil ->
        {:ok, state, []}

      phase(state) != :writing ->
        {:error, :not_writing}

      true ->
        page = %Document{
          bookends: bookends,
          origins: origins_from(state, attrs[:from], bookends),
          gives: state.gives,
          meta: meta,
          full_table: Map.get(attrs, :full_table, state.full_table) != false
        }

        {:ok, reset_page(state, page), []}
    end
  end

  def apply(%__MODULE__{} = state, {:author_failed, %{reason: reason}}) do
    cond do
      phase(state) != :writing ->
        {:error, :not_writing}

      true ->
        {:ok, %{state | author_failure: reason}, []}
    end
  end

  def apply(%__MODULE__{} = state, {:author_retried, %{seat_id: seat_id}}) do
    with :ok <- may_retry_author(state, seat_id) do
      ask_author(%{
        state
        | author_failure: nil,
          author_retries_used: state.author_retries_used + 1
      })
    end
  end

  def apply(%__MODULE__{} = state, {:gives_reset, %{seat_id: seat_id}}) do
    with :ok <- may_reset_gives(state, seat_id) do
      {:ok,
       %{
         state
         | gives: %{},
           masks: %{},
           author_failure: nil,
           page_seat_ids: nil,
           author_retries_used: 0
       }, []}
    end
  end

  def apply(%__MODULE__{} = state, {:bridge_committed, %{seat_id: seat_id, bridge: bridge}}) do
    bridge = Thereish.Steward.Legality.normalize_bridge(bridge)

    with :ok <- may_bridge(state, seat_id) do
      if bridge == "" do
        {:error, :bridge_required}
      else
        case Thereish.Steward.Legality.check_bridge(bridge, barred_words(state)) do
          :ok -> committed(put_attempt(state, :bridges, Map.put(bridges(state), seat_id, bridge)))
          {:illegal, reason} -> {:error, {:illegal_bridge, reason}}
        end
      end
    end
  end

  def apply(%__MODULE__{} = state, {:verdict_received, verdict}) do
    record(state, %{
      graded?: true,
      closeness: verdict.closeness,
      reasoning: verdict.reasoning,
      quip: Map.get(verdict, :quip),
      furthest: Map.get(verdict, :furthest),
      meta: Map.get(verdict, :meta, %{})
    })
  end

  def apply(%__MODULE__{} = state, {:verdict_unavailable, event}) do
    record(state, %{
      graded?: false,
      closeness: nil,
      reasoning: nil,
      quip: Map.get(event, :quip),
      furthest: nil,
      meta: Map.get(event, :meta, %{})
    })
  end

  def apply(%__MODULE__{} = state, {:overrule_proposed, %{seat_id: seat_id} = attrs}) do
    with :ok <- may_propose_overrule(state, seat_id) do
      resolve_overrule(state, Overrule.propose(seat_id, Map.get(attrs, :closeness)))
    end
  end

  def apply(%__MODULE__{} = state, {:overrule_agreed, %{seat_id: seat_id}}) do
    with :ok <- may_vote_overrule(state, seat_id) do
      resolve_overrule(state, Overrule.agree(overrule(state), seat_id))
    end
  end

  def apply(%__MODULE__{} = state, {:overrule_declined, %{seat_id: seat_id}}) do
    with :ok <- may_vote_overrule(state, seat_id) do
      {:ok, put_attempt(state, :overrule, nil), []}
    end
  end

  def apply(%__MODULE__{} = state, {:fairness_tapped, %{seat_id: seat_id, label: label}}) do
    with {:ok, opinion} <- opinion_at_reveal(state, seat_id, label) do
      opinions = Map.put(opinions(state), seat_id, opinion.label)
      {:ok, put_attempt(state, :opinions, opinions), [{:fairness_tap, opinion}]}
    end
  end

  def apply(%__MODULE__{} = state, {:attempt_advanced, %{seat_id: seat_id}}) do
    with :ok <- may_advance(state, seat_id) do
      %{carried: carried} = carry(state)
      next = Attempt.open(state.attempt.number + 1, Enum.map(carried, & &1.word), carried)

      {:ok, %{state | attempt: next, played: state.played ++ [state.attempt]}, []}
    end
  end

  def apply(%__MODULE__{} = state, {:bookends_tapped, %{seat_id: seat_id, label: label}}) do
    label_str = normalize_label(label)

    with :ok <- may_tap_bookends(state, seat_id) do
      if label_str not in ["flat", "fine", "great"] do
        {:error, :invalid_label}
      else
        meta = (state.page && state.page.meta) || %{}
        bookends = (state.page && state.page.bookends) || attempt_bookends(state)

        # Which Chronicle Page this is, and its Arm, are the Room's to say.
        tap_effect_data = %{
          seat_id: seat_id,
          label: label_str,
          bookends: bookends,
          gives: (state.page && state.page.gives) || state.gives,
          author_meta: meta
        }

        current_taps = state.bookends_taps || %{}
        next_state = %{state | bookends_taps: Map.put(current_taps, seat_id, label_str)}

        {:ok, next_state, [{:bookends_tap, tap_effect_data}]}
      end
    end
  end

  def apply(%__MODULE__{} = state, {:next_page, %{seat_id: seat_id}}) do
    with :ok <- may_next_page(state, seat_id) do
      last_gives = Map.merge(state.last_gives || %{}, state.gives || %{})
      state = reset_page(state, nil)

      {:ok,
       %{
         state
         | gives: %{},
           last_gives: last_gives,
           page_seat_ids: nil,
           masks: %{},
           author_retries_used: 0
       }, []}
    end
  end

  # What every Page starts over, whether it is being written or the last one
  # is being put away: its Attempts, its Bookends taps and the Author's failure.
  defp reset_page(state, page) do
    %{
      state
      | page: page,
        attempt: first_attempt(page),
        played: [],
        bookends_taps: %{},
        author_failure: nil
    }
  end

  defp first_attempt(nil), do: nil
  defp first_attempt(%Document{} = page), do: Attempt.open(1, page.bookends, page.origins)

  defp put_attempt(state, field, value),
    do: %{state | attempt: Map.replace!(state.attempt, field, value)}

  # The current Attempt's fields, read as an Attempt with nothing in it when
  # no Page is open.
  defp bridges(%{attempt: nil}), do: %{}
  defp bridges(%{attempt: attempt}), do: attempt.bridges

  defp verdict(%{attempt: nil}), do: nil
  defp verdict(%{attempt: attempt}), do: attempt.verdict

  defp overrule(%{attempt: nil}), do: nil
  defp overrule(%{attempt: attempt}), do: attempt.overrule

  defp opinions(%{attempt: nil}), do: %{}
  defp opinions(%{attempt: attempt}), do: attempt.opinions

  @doc """
  Projects what one viewer may see: a Seat by its id, or `nil` for a viewer that
  holds no Seat — the stage on the laptop, or a phone still at the name form.

  Everyone gets the same roster, the same Bookends and the same reveal — the
  stage and the phones must never disagree about the Page they are playing. The
  only things that differ are which Seat is the viewer's own and which Bridge it
  wrote, and an uncommitted Bridge is in nobody's view but its author's until
  every Seat has committed.

  `may` says which actions this viewer may take right now, one boolean per Seat
  action. Each is the same check `apply/2` makes before it reads the event's
  input, so a control a screen shows is an event the Game accepts — as long as
  the input is good. It leaves out the hold after a reveal: the Game keeps no
  clock, and the Room's Pacing says when the hold is over.

  `first_revealed?` says whether this Page's first reveal has happened, the
  moment the Gives and the Masks go public.
  """
  @spec view(t(), viewer()) :: map()
  def view(%__MODULE__{} = state, viewer) do
    phase = phase(state)
    opinions = opinions(state)

    carry = if phase == :reveal, do: carry(state)

    %{
      phase: phase,
      late?: viewer != nil and not plays_page?(state, viewer),
      may: may(state, viewer),
      first_revealed?: first_revealed?(state),
      seats: Enum.map(state.seats, &seat_view(state, &1, viewer)),
      you: find_seat(state, viewer),
      seat_limit: state.seat_limit,
      open_seats: state.seat_limit - length(state.seats),
      bookends: bookends(state, phase),
      bookend_chips: bookend_chips(state, phase),
      your_give: Map.get(state.gives, viewer),
      your_last_give: Map.get(state.last_gives, viewer),
      your_mask: if(viewer, do: Map.get(state.masks || %{}, viewer)),
      gives_in: map_size(state.gives),
      author_failure: state.author_failure,
      your_bridge: Map.get(bridges(state), viewer),
      attempt: %{number: attempt_number(state), of: attempt_cap()},
      reveal: reveal(state, phase, viewer),
      # What the next attempt will hang between, so the tap that starts it can
      # say so. The carry-forward is the point of a miss; a button that named
      # neither word would hide it.
      next_bookends: carry && Enum.map(carry.carried, & &1.word),
      # Whether the Assayer picked those two words or the game fell back to the
      # first two Bridges in roster order. The couple are about to spend an
      # attempt on them, so which of the two happened is theirs to know. At a
      # Full table the table's own Bridges carry, so there is no choice to miss.
      next_bookends_chosen?: carry && carry.chosen?,
      closed: closed(state, phase),
      played: Enum.map(state.played, &attempt_view(state, &1)),
      overrule: overrule_view(state, viewer),
      your_tap: Map.get(opinions, viewer),
      fairness_taps: opinions,
      your_bookends_tap: Map.get(state.bookends_taps || %{}, viewer),
      bookends_taps: state.bookends_taps || %{},
      barred_words: if(phase != :waiting, do: barred_words(state)),
      gives: if(first_revealed?(state), do: gives_view(state)),
      full_table: page_full_table(state.page, state.full_table)
    }
  end

  @doc """
  All words and phrases barred from being played as a Bridge on this Page:
  the Bookends of every Attempt so far and every Bridge committed in earlier
  attempts of this Page.
  """
  @spec barred_words(t()) :: [String.t()]
  def barred_words(%__MODULE__{} = state) do
    past_bookends = Enum.flat_map(state.played, & &1.bookends)
    past_bridges = Enum.flat_map(state.played, &Map.values(&1.bridges))
    current_bookends = attempt_bookends(state) || []

    (current_bookends ++ past_bookends ++ past_bridges)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @doc """
  The number of the Attempt being played, or 1 when no Page is open, so a
  Room waiting for its Page counts from the first Attempt.
  """
  @spec attempt_number(t()) :: pos_integer()
  def attempt_number(%__MODULE__{attempt: nil}), do: 1
  def attempt_number(%__MODULE__{attempt: attempt}), do: attempt.number

  @doc "The Bookends of the Attempt being played, or nil when no Page is open."
  @spec attempt_bookends(t()) :: [String.t()] | nil
  def attempt_bookends(%__MODULE__{attempt: nil}), do: nil
  def attempt_bookends(%__MODULE__{attempt: attempt}), do: attempt.bookends

  # The Page's Seats, in roster order. Every walk of the Seats that concerns
  # the Page goes through here. Until the Author is asked for a Page, no Seats
  # are fixed, and every Seat counts.
  defp page_seats(state), do: Enum.filter(state.seats, &plays_page?(state, &1.id))

  # Whether a Seat plays the Page. A Seat that sat down after the Author was
  # asked watches this Page and plays from the next one.
  defp plays_page?(%{page_seat_ids: nil}, _seat_id), do: true
  defp plays_page?(state, seat_id), do: seat_id in state.page_seat_ids

  # The one place play fixes a Page's Seats: the Seats that wrote a Give when the
  # Author is asked for the Page, whether Start Page asks or the last Give of a
  # full Room does. Gives reset and the next Page clear them. A Game built with
  # a Page in hand (`init/1`) is the only other start, and it gives that Page
  # the Seats it was built with.
  defp ask_author(state) do
    page_seat_ids = for seat <- state.seats, Map.has_key?(state.gives, seat.id), do: seat.id
    state = %{state | page_seat_ids: page_seat_ids}
    {:ok, state, [{:author, author_request(state)}]}
  end

  defp author_request(state) do
    participating = page_seats(state)

    gives =
      Enum.map(participating, fn s ->
        %{seat_id: s.id, name: s.name, text: state.gives[s.id], give: state.gives[s.id]}
      end)

    %{gives: gives, count: bookend_count(state, participating)}
  end

  defp bookend_count(%{full_table: false}, _seats), do: 2
  defp bookend_count(_state, seats), do: length(seats)

  # A Page keeps the rule it was written under. A Room that has not written
  # one yet, or a Page from before the rule, reads as the Room's current rule.
  defp page_full_table(%Document{full_table: full_table}, _default) when is_boolean(full_table),
    do: full_table

  defp page_full_table(_page, default), do: default == true

  # The last Bridge in is the moment the Page turns: the Assayer is asked once,
  # about every Bridge together, and the beat starts alongside rather than
  # after, so the theatre and the grading run in parallel.
  defp committed(state) do
    if phase(state) == :assaying do
      {:ok, state, [:beat, assay(state)]}
    else
      {:ok, state, []}
    end
  end

  # Nobody sees the Bookends until everybody can: a player alone in the Room with
  # the two words on screen is a player with a head start on the one still
  # typing their name.
  defp bookends(_state, phase) when phase in [:waiting, :giving, :writing], do: nil
  defp bookends(state, _phase), do: attempt_bookends(state)

  # The Bridges go in roster order, the order the reveal puts them in, so that
  # the sentence the Assayer writes, the joke it makes and the two words it
  # names as furthest apart all read in the order they are on the screen.
  #
  # assay-4 carries Bookends of two or more, Bridges with player names in roster
  # order, earlier Attempts with their Quips, and Gives.
  defp assay(state), do: {:assay, assay_request_overall(state)}

  defp assay_request_overall(state) do
    seats = page_seats(state)

    seat_bridges =
      Enum.map(seats, fn seat ->
        %{name: seat.name, bridge: bridges(state)[seat.id]}
      end)

    %{
      bookends: attempt_bookends(state),
      bridges: written_bridges(state),
      seat_bridges: seat_bridges,
      player_bridges: seat_bridges,
      earlier_attempts:
        Enum.map(state.played, fn attempt ->
          %{
            number: attempt.number,
            bookends: attempt.bookends,
            bridges:
              Enum.map(seats, fn seat ->
                %{name: seat.name, bridge: Map.get(attempt.bridges, seat.id)}
              end),
            quip: attempt_quip(attempt)
          }
        end),
      gives: gives_for_assay(state)
    }
  end

  # The Assayer reads this Page's earlier Quips beside the Chronicle's, so that
  # its comedy does not repeat itself (`Thereish.Steward.Digest.assayer/2`).
  # Neither the Precedent's key nor the prompt's earlier Attempts read it.
  defp attempt_quip(%{verdict: %{quip: quip}}), do: quip
  defp attempt_quip(_attempt), do: nil

  defp gives_for_assay(state) do
    cond do
      is_nil(state.page) ->
        []

      map_size(state.page.gives) == 0 and is_binary(state.page.give) and state.page.give != "" ->
        [%{give: state.page.give}]

      true ->
        Enum.map(page_seats(state), fn seat ->
          %{name: seat.name, give: state.page.gives[seat.id]}
        end)
    end
  end

  # Every Bridge of this attempt, in roster order.
  defp written_bridges(state), do: Enum.map(page_seats(state), &bridges(state)[&1.id])

  # The revealed Attempt as an Opinion reads it. An overrule keeps the
  # Assayer's grade as the Verdict's `original_closeness`.
  defp graded_attempt(state) do
    verdict = verdict(state)
    meta = verdict.meta || %{}

    %{
      attempt_number: attempt_number(state),
      bookends: attempt_bookends(state),
      bridges: written_bridges(state),
      participant_ids: for(seat <- page_seats(state), committed?(state, seat.id), do: seat.id),
      closeness: verdict.closeness,
      machine_closeness: Map.get(verdict, :original_closeness),
      model: meta[:model],
      prompt_version: meta[:prompt_version]
    }
  end

  # An Attempt is graded once. The Room can deliver the same verdict twice — a
  # retry, a message that outlived the attempt it was about — and the second one
  # must not be able to change a number the players are already looking at.
  defp record(state, verdict) do
    cond do
      verdict(state) != nil -> {:ok, state, []}
      phase(state) != :assaying -> {:error, :no_verdict_expected}
      true -> graded(put_attempt(state, :verdict, verdict))
    end
  end

  # The verdict that completes the reveal may also be the one that ends the
  # Page, and a Page that ended is a Page the Chronicle is owed.
  defp graded(state) do
    if phase(state) == :closed do
      {:ok, state, [{:chronicle, chronicle(state)}]}
    else
      {:ok, state, []}
    end
  end

  @doc "Where a Page has got to (waiting, giving, writing, bridging, assaying, reveal, closed)."
  def phase(state) do
    cond do
      state.page != nil ->
        cond do
          map_size(bridges(state)) < length(page_seats(state)) -> :bridging
          verdict(state) == nil -> :assaying
          over?(state) -> :closed
          true -> :reveal
        end

      state.page_seat_ids != nil ->
        :writing

      not full?(state) and length(state.seats) < 2 ->
        :waiting

      true ->
        :giving
    end
  end

  # Both ways a Page ends. A Meld ends it the moment it lands, so that landing it
  # is the last thing that happens rather than one more rung; spending the last
  # attempt ends it too, and that is an ending rather than a failure.
  defp over?(state), do: melded?(state) or attempt_number(state) >= attempt_cap()

  defp melded?(state) do
    state |> headline() |> Ladder.read() |> Map.fetch!(:melded?)
  end

  defp closed_because(state), do: if(melded?(state), do: :meld, else: :attempts_spent)

  defp closed(_state, phase) when phase != :closed, do: nil

  defp closed(state, _phase),
    do: %{because: closed_because(state), attempt: attempt_number(state)}

  # One reveal for every Seat: every Bridge, one number in its band, one quip,
  # and the two words that landed furthest apart, named inside the same Verdict
  # (ADR-0010). Reasoning is kept in the Chronicle and kept off the screen.
  defp reveal(state, phase, _viewer) when phase in [:reveal, :closed] do
    gives = gives_view(state)

    verdict(state)
    |> verdict_view()
    |> Map.delete(:reasoning)
    |> Map.merge(%{
      bridges: bridges_view(state, bridges(state)),
      furthest: furthest_view(state, verdict(state)),
      gives: gives
    })
  end

  defp reveal(_state, _phase, _viewer), do: nil

  defp gives_view(state) do
    Enum.map(page_seats(state), fn seat ->
      %{
        seat_id: seat.id,
        name: seat.name,
        text: state.gives[seat.id],
        mask: Map.get(state.masks || %{}, seat.id)
      }
    end)
  end

  # The Page's number is the Verdict's, and an Attempt the Assayer could not
  # grade has no number rather than a zero: "we don't know" is not "you missed".
  defp headline(state), do: attempt_closeness(state.attempt)

  # Carry-forward reads the Page's rule (ADR-0016), which `Bookends.carry/3`
  # owns: at a Full table every Seat's Bridge, in roster order; off, the two the
  # Assayer named as furthest apart, or the first two in roster order when it
  # named none the roster can account for, which `chosen?` tells the screens.
  #
  # Nothing here defends against two carried words being the same word: that
  # needs an Assayer that names a word twice, and if one ever does, the next
  # attempt is a Page with one word twice rather than a crash.
  defp carry(state) do
    bridges =
      for seat <- page_seats(state), Map.has_key?(bridges(state), seat.id) do
        %{seat_id: seat.id, bridge: bridges(state)[seat.id]}
      end

    Bookends.carry(bridges, verdict(state), page_full_table(state.page, state.full_table))
  end

  defp bookend_chips(_state, phase) when phase in [:waiting, :giving, :writing], do: nil

  defp bookend_chips(state, _phase) do
    Bookends.chips(
      attempt_bookends(state) || [],
      state.attempt.origins,
      attempt_number(state),
      state.masks || %{}
    )
  end

  defp origins_from(_state, nil, bookends), do: Enum.map(bookends, &unknown_origin/1)

  defp origins_from(state, from, bookends) when is_list(from) do
    by_name =
      Map.new(page_seats(state), fn seat ->
        {String.downcase(String.trim(seat.name)), seat}
      end)

    Enum.zip(bookends, from)
    |> Enum.map(fn {word, name} ->
      case Map.get(by_name, name |> to_string() |> String.trim() |> String.downcase()) do
        nil ->
          unknown_origin(word)

        seat ->
          %{
            word: word,
            seat_id: seat.id,
            seat_name: seat.name,
            give: state.gives[seat.id]
          }
      end
    end)
  end

  defp origins_from(_state, _from, bookends), do: Enum.map(bookends, &unknown_origin/1)

  defp unknown_origin(word), do: %{word: word, seat_id: nil, seat_name: nil, give: nil}

  # What the Assayer said, in the shape every screen and the book read it in.
  # The number goes through the Ladder here so that nothing downstream has to
  # know which rung a grade is on.
  defp verdict_view(verdict) do
    Map.merge(Ladder.read(verdict.closeness), %{
      graded?: verdict.graded?,
      reasoning: verdict.reasoning,
      quip: verdict.quip,
      overruled?: Map.get(verdict, :overruled?, false)
    })
  end

  # The furthest two a graded Verdict named, said the way the reveal says them:
  # the word and whose it is. Each is claimed from the roster once
  # (`Bookends.claim/2`), so a table that wrote one word twice does not read as
  # one player disagreeing with themselves, and a word the roster cannot account
  # for, such as a paraphrase, is no pair at all.
  defp furthest_view(state, %{graded?: true, furthest: [_, _] = furthest}) do
    bridges = bridges_view(state, bridges(state))
    claimed = Bookends.claim(furthest, bridges)

    if Enum.all?(claimed, & &1.seat_id) do
      Enum.map(claimed, fn %{seat_id: seat_id} ->
        Enum.find(bridges, &(&1.seat_id == seat_id))
      end)
    end
  end

  defp furthest_view(_state, _verdict), do: nil

  defp bridges_view(state, bridges) do
    for seat <- page_seats(state), Map.has_key?(bridges, seat.id) do
      %{seat_id: seat.id, name: seat.name, bridge: bridges[seat.id]}
    end
  end

  # An attempt already played, as the arc at the close reads it.
  defp attempt_view(state, attempt) do
    Map.merge(Ladder.read(attempt_closeness(attempt)), %{
      number: attempt.number,
      bookends: attempt.bookends,
      bridges: bridges_view(state, attempt.bridges)
    })
  end

  defp attempt_closeness(%{verdict: %{graded?: true, closeness: closeness}}), do: closeness

  defp attempt_closeness(_attempt), do: nil

  # The whole Page as it was played, for the Room to write down. Everything the
  # Chronicle keeps about a Page is here, including the attempts that were
  # already over when this one closed. It is built from the Game's state and
  # not from what any screen shows, so a change to a view cannot change what
  # the Chronicle stores.
  defp chronicle(state) do
    attempts = state.played ++ [state.attempt]

    %Entry{
      page: state.page,
      gives:
        Enum.map(page_seats(state), fn seat ->
          %Entry.Give{seat_id: seat.id, text: state.gives[seat.id] || ""}
        end),
      masks: state.masks || %{},
      author_meta: state.page && state.page.meta,
      closed_because: closed_because(state),
      melded?: melded?(state),
      closeness: headline(state),
      attempts: Enum.map(attempts, &chronicle_attempt(state, &1))
    }
  end

  defp overrule_view(state, viewer) do
    with %{} = view <- Overrule.view(overrule(state), viewer) do
      proposer = find_seat(state, view.proposer_id)
      Map.put(view, :proposer_name, proposer && proposer.name)
    end
  end

  # Holds the proposal while a Seat playing the Page has still to agree, and
  # rules it once every one of them has.
  defp resolve_overrule(state, proposal) do
    if Overrule.unanimous?(proposal, Enum.map(page_seats(state), & &1.id)) do
      rule_overrule(state, proposal)
    else
      {:ok, put_attempt(state, :overrule, proposal), []}
    end
  end

  defp rule_overrule(state, proposal) do
    previously_closed? = phase(state) == :closed

    {verdict, ruling} =
      Overrule.rule(proposal, verdict(state), %{
        number: attempt_number(state),
        bookends: attempt_bookends(state),
        bridges: written_bridges(state)
      })

    state = state |> put_attempt(:verdict, verdict) |> put_attempt(:overrule, nil)

    effects =
      if phase(state) == :closed and not previously_closed? do
        [{:overrule, ruling}, {:chronicle, chronicle(state)}]
      else
        [{:overrule, ruling}]
      end

    {:ok, state, effects}
  end

  # An attempt as the arc reads it, plus the one Verdict behind it. The book
  # keeps a list because an attempt has held more than one row before and the
  # rows are what a reader counts; today that list is one long (ADR-0010).
  defp chronicle_attempt(state, attempt) do
    %{closeness: closeness, melded?: melded?} = Ladder.read(attempt_closeness(attempt))

    %Entry.Attempt{
      number: attempt.number,
      bookends: attempt.bookends,
      closeness: closeness,
      melded?: melded?,
      bridges:
        for seat <- page_seats(state), Map.has_key?(attempt.bridges, seat.id) do
          %{seat_id: seat.id, bridge: attempt.bridges[seat.id]}
        end,
      verdicts: if(attempt.verdict, do: [chronicle_verdict(state, attempt)], else: [])
    }
  end

  # A verdict row says which word every Seat had in it, in the same order as the
  # Seats it names, so the row can be read without joining anything back to it —
  # and which two of those words the Assayer sent the couple to next. The number
  # goes through the Ladder, as it does on screen.
  defp chronicle_verdict(state, attempt) do
    verdict = attempt.verdict
    seats = page_seats(state)
    %{closeness: closeness, band: band} = Ladder.read(verdict.closeness)

    %Entry.Verdict{
      seat_ids: Enum.map(seats, & &1.id),
      bridges: Enum.map(seats, &attempt.bridges[&1.id]),
      graded?: verdict.graded?,
      closeness: closeness,
      band: band,
      reasoning: verdict.reasoning,
      quip: verdict.quip,
      furthest: Map.get(verdict, :furthest),
      overruled?: Map.get(verdict, :overruled?, false),
      meta: verdict.meta
    }
  end

  @doc "A Seat's house colour from the Limner palette by roster position."
  @spec seat_colour(t(), seat() | String.t()) :: String.t()
  def seat_colour(%__MODULE__{} = state, seat_or_id) do
    seat_id = if is_binary(seat_or_id), do: seat_or_id, else: seat_or_id.id
    palette = Thereish.Steward.Limner.palette()
    index = Enum.find_index(state.seats, &(&1.id == seat_id)) || 0
    Enum.at(palette, rem(index, length(palette)))
  end

  defp seat_view(state, seat, viewer) do
    %{
      id: seat.id,
      name: seat.name,
      colour: seat_colour(state, seat),
      mask: mask_for_viewer(state, seat, viewer),
      you?: seat.id == viewer,
      committed?: committed?(state, seat.id),
      late?: not plays_page?(state, seat.id)
    }
  end

  defp mask_for_viewer(state, seat, viewer) do
    raw_mask = Map.get(state.masks || %{}, seat.id)

    cond do
      first_revealed?(state) ->
        raw_mask

      seat.id == viewer ->
        raw_mask

      give_landed?(state, seat.id) ->
        :face_down

      true ->
        nil
    end
  end

  defp give_landed?(state, seat_id) do
    (is_map(state.gives) and Map.has_key?(state.gives, seat_id) and
       not is_nil(state.gives[seat_id])) or
      (is_map(state.masks) and Map.has_key?(state.masks, seat_id) and
         not is_nil(state.masks[seat_id]))
  end

  # Which Seat actions this viewer may take, by the checks `apply/2` makes.
  defp may(state, viewer) do
    %{
      give: may_give(state, viewer) == :ok,
      bridge: may_bridge(state, viewer) == :ok,
      propose_overrule: may_propose_overrule(state, viewer) == :ok,
      vote_overrule: may_vote_overrule(state, viewer) == :ok,
      tap_fairness: may_tap_fairness(state, viewer) == :ok,
      advance: may_advance(state, viewer) == :ok,
      tap_bookends: may_tap_bookends(state, viewer) == :ok,
      next_page: may_next_page(state, viewer) == :ok,
      start_page: may_start_page(state, viewer) == :ok,
      retry_author: may_retry_author(state, viewer) == :ok,
      reset_gives: may_reset_gives(state, viewer) == :ok
    }
  end

  # One check per Seat action: whether this Seat stands where the action can be
  # taken. What the event carries — the Give's text, the Bridge's word, the
  # tap's label — is checked after, by `apply/2` alone. A Give and a Bridge ask
  # about the Phase before the Seat, so their errors read as they always have.
  defp may_give(state, seat_id) do
    cond do
      phase(state) != :giving -> {:error, :not_giving}
      not seated?(state, seat_id) -> {:error, :no_such_seat}
      Map.has_key?(state.gives, seat_id) -> {:error, :already_committed}
      true -> :ok
    end
  end

  defp may_bridge(state, seat_id) do
    cond do
      phase(state) != :bridging -> {:error, :not_bridging}
      not seated?(state, seat_id) -> {:error, :no_such_seat}
      playing_page_seat(state, seat_id) != :ok -> {:error, :not_playing_page}
      committed?(state, seat_id) -> {:error, :already_committed}
      true -> :ok
    end
  end

  defp may_propose_overrule(state, seat_id) do
    with :ok <- taken_by_a_seat(state, seat_id),
         :ok <- playing_page_seat(state, seat_id),
         :ok <- verdict_revealed(state) do
      cond do
        overrule(state) != nil -> {:error, :proposal_pending}
        Overrule.overruled?(verdict(state)) -> {:error, :already_overruled}
        true -> :ok
      end
    end
  end

  defp may_vote_overrule(state, seat_id) do
    with :ok <- taken_by_a_seat(state, seat_id),
         :ok <- playing_page_seat(state, seat_id) do
      if overrule(state) == nil, do: {:error, :no_proposal_pending}, else: :ok
    end
  end

  # The Game says when a tap may happen. Who may give an Opinion, and of which
  # grade, is the Opinion's rule: a Verdict the Assayer could not grade has
  # nothing to rate, unless the table overruled it into a number.
  defp may_tap_fairness(state, seat_id) do
    with {:ok, _opinion} <- opinion_at_reveal(state, seat_id, :fair), do: :ok
  end

  defp opinion_at_reveal(state, seat_id, label) do
    with :ok <- taken_by_a_seat(state, seat_id),
         :ok <- playing_page_seat(state, seat_id),
         :ok <- verdict_revealed(state) do
      Opinion.new(graded_attempt(state), {:participant, seat_id}, label)
    end
  end

  defp may_advance(state, seat_id) do
    with :ok <- taken_by_a_seat(state, seat_id),
         :ok <- playing_page_seat(state, seat_id) do
      open_reveal(state)
    end
  end

  # A Seat that watched the Page may still say how its Bookends were, and may
  # start the next one, which it will play.
  defp may_tap_bookends(state, seat_id) do
    with :ok <- taken_by_a_seat(state, seat_id) do
      if phase(state) == :closed, do: :ok, else: {:error, :not_closed}
    end
  end

  defp may_next_page(state, seat_id) do
    with :ok <- taken_by_a_seat(state, seat_id) do
      closed_page(state)
    end
  end

  defp may_start_page(state, seat_id) do
    with :ok <- taken_by_a_seat(state, seat_id) do
      cond do
        phase(state) != :giving -> {:error, :not_giving}
        not Map.has_key?(state.gives, seat_id) -> {:error, :give_required}
        map_size(state.gives) < 2 -> {:error, :not_enough_gives}
        true -> :ok
      end
    end
  end

  # New Gives waits for the Author to fail. Try again is the allowance kept
  # with the Author's escalation times (`retries`, default 1), shared by
  # every Seat for this set of Gives. New Gives and the next Page clear it.
  defp may_retry_author(state, seat_id) do
    with :ok <- taken_by_a_seat(state, seat_id) do
      cond do
        phase(state) != :writing or is_nil(state.author_failure) ->
          {:error, :not_failed}

        state.author_retries_used >= state.author_retry_allowance ->
          {:error, :retries_spent}

        true ->
          :ok
      end
    end
  end

  defp may_reset_gives(state, seat_id) do
    with :ok <- taken_by_a_seat(state, seat_id) do
      cond do
        phase(state) != :writing -> {:error, :not_writing}
        is_nil(state.author_failure) -> {:error, :not_failed}
        true -> :ok
      end
    end
  end

  # The Room passes the count it read with the escalation times. A Game built
  # on its own reads the same list, and a missing count is one Try again.
  defp retry_allowance(opts) do
    opts
    |> Keyword.get_lazy(:author_retry_allowance, fn ->
      :thereish
      |> Application.fetch_env!(:author_escalation_ms)
      |> Keyword.get(:retries, 1)
    end)
    |> normalize_allowance()
  end

  defp normalize_allowance(count) when is_integer(count) and count >= 0, do: count
  defp normalize_allowance(_other), do: 1

  # Whether this Page's first reveal has happened: the reveal is on screen now,
  # or an earlier Attempt of this Page already had one.
  defp first_revealed?(state), do: phase(state) in [:reveal, :closed] or state.played != []

  defp verdict_revealed(state) do
    if phase(state) in [:reveal, :closed] and verdict(state) != nil,
      do: :ok,
      else: {:error, :not_revealed}
  end

  defp taken_by_a_seat(state, seat_id) do
    if seated?(state, seat_id), do: :ok, else: {:error, :no_such_seat}
  end

  defp playing_page_seat(state, seat_id) do
    if plays_page?(state, seat_id), do: :ok, else: {:error, :not_playing_page}
  end

  defp open_reveal(state) do
    case phase(state) do
      :reveal -> :ok
      :closed -> {:error, :page_closed}
      _other -> {:error, :not_revealed}
    end
  end

  defp closed_page(state) do
    if phase(state) == :closed, do: :ok, else: {:error, :page_open}
  end

  defp committed?(state, seat_id), do: Map.has_key?(bridges(state), seat_id)

  defp find_seat(state, seat_id), do: Enum.find(state.seats, &(&1.id == seat_id))

  defp full?(state), do: length(state.seats) >= state.seat_limit

  defp normalize_label(other) when is_binary(other),
    do: other |> String.trim() |> String.downcase()

  defp normalize_label(other), do: to_string(other)

  defp seat(%{id: id, name: name}) do
    %{id: id, name: name}
  end

  defp seated?(state, seat_id), do: find_seat(state, seat_id) != nil
end
