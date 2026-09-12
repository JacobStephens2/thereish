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

  alias Thereish.Ladder

  @enforce_keys [:seat_limit, :seats]
  defstruct [
    :seat_limit,
    :seats,
    :page,
    :bookends,
    attempt: 1,
    gives: %{},
    last_gives: %{},
    author_failure: nil,
    bridges: %{},
    verdict: nil,
    furthest: nil,
    played: [],
    overrule: nil,
    overrules: [],
    fairness_taps: %{},
    bookends_taps: %{},
    page_seat_ids: nil,
    track: nil,
    track_held_over: false,
    masks: %{},
    full_table: true,
    bookend_origins: nil
  ]

  @type seat :: %{
          required(:id) => String.t(),
          required(:name) => String.t()
        }
  @type page :: %{id: String.t(), bookends: [String.t()]}

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

  @typedoc "One attempt as it was played, kept so the Chronicle can have it."
  @type attempt :: %{
          optional(:furthest) => [String.t()] | nil,
          number: pos_integer(),
          bookends: [String.t()],
          bridges: %{String.t() => String.t()},
          verdict: verdict() | nil
        }

  @type t :: %__MODULE__{
          seat_limit: pos_integer(),
          seats: [seat()],
          page: page() | nil,
          bookends: [String.t()] | nil,
          attempt: pos_integer(),
          gives: %{String.t() => String.t()},
          last_gives: %{String.t() => String.t()},
          author_failure: term(),
          bridges: %{String.t() => String.t()},
          verdict: verdict() | nil,
          furthest: [String.t()] | nil,
          played: [attempt()],
          overrule: map() | nil,
          overrules: [map()],
          fairness_taps: %{String.t() => String.t()},
          bookends_taps: %{String.t() => String.t()},
          page_seat_ids: [String.t()] | nil,
          track: map() | nil,
          track_held_over: boolean(),
          masks: %{String.t() => term()},
          full_table: boolean(),
          bookend_origins: [map()] | nil
        }

  @type viewer :: String.t() | nil

  @type event ::
          {:seat_joined, seat()}
          | {:track_landed, map() | String.t()}
          | {:give_committed,
             %{
               required(:seat_id) => String.t(),
               required(:give) => String.t()
             }}
          | {:mask_landed,
             %{
               required(:seat_id) => String.t(),
               required(:mask) => term()
             }}
          | {:mask_landed, String.t(), term()}
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
          | {:page_started, %{seat_id: String.t(), page: page()}}
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
          | {:chronicle, map()}
          | {:overrule, map()}
          | {:fairness_tap, map()}
          | {:bookends_tap, map()}

  @type error ::
          :room_full
          | :not_giving
          | :not_writing
          | :give_required
          | :give_too_long
          | :not_failed
          | :not_bridging
          | :no_such_seat
          | :already_committed
          | :bridge_required
          | :no_verdict_expected
          | :not_revealed
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
    seat_limit = Keyword.fetch!(opts, :seat_limit)
    seats = opts |> Keyword.get(:seats, []) |> Enum.map(&seat/1)

    page_seat_ids =
      if page != nil and length(seats) >= seat_limit do
        Enum.map(seats, & &1.id)
      else
        nil
      end

    track = normalize_track(Keyword.get(opts, :track))
    track_held_over = not is_nil(track) and is_nil(page)

    full_table =
      cond do
        Keyword.has_key?(opts, :full_table) -> Keyword.get(opts, :full_table)
        is_map(page) -> page_full_table(page, true)
        true -> true
      end

    %__MODULE__{
      seat_limit: seat_limit,
      seats: seats,
      page: page,
      bookends: page && (Map.get(page, :bookends) || Map.get(page, "bookends")),
      gives: %{},
      last_gives: %{},
      author_failure: nil,
      page_seat_ids: page_seat_ids,
      track: track,
      track_held_over: track_held_over,
      masks: %{},
      full_table: full_table == true,
      bookend_origins: page_origins(page)
    }
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
  def apply(%__MODULE__{} = state, {:track_landed, track}) when is_map(track) do
    {:ok, %{state | track: track, track_held_over: false}, []}
  end

  def apply(%__MODULE__{} = state, {:track_landed, track}) when is_binary(track) do
    {:ok, %{state | track: %{title: track}, track_held_over: false}, []}
  end

  def apply(%__MODULE__{} = state, {:seat_joined, seat}) do
    seat = seat(seat)

    cond do
      seated?(state, seat.id) ->
        {:ok, state, []}

      full?(state) ->
        {:error, :room_full}

      true ->
        new_seats = state.seats ++ [seat]

        page_seat_ids =
          if state.page != nil and length(new_seats) >= state.seat_limit and
               is_nil(state.page_seat_ids) do
            Enum.map(new_seats, & &1.id)
          else
            state.page_seat_ids
          end

        {:ok, %{state | seats: new_seats, page_seat_ids: page_seat_ids}, []}
    end
  end

  def apply(%__MODULE__{} = state, {:give_committed, %{seat_id: seat_id} = attrs}) do
    give = attrs[:give] || attrs[:text] || ""
    trimmed = String.trim(give)

    cond do
      phase(state) != :giving ->
        {:error, :not_giving}

      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      Map.has_key?(state.gives, seat_id) ->
        {:error, :already_committed}

      trimmed == "" ->
        {:error, :give_required}

      String.length(trimmed) > 120 ->
        {:error, :give_too_long}

      true ->
        gives = Map.put(state.gives, seat_id, trimmed)
        last_gives = Map.put(state.last_gives, seat_id, trimmed)
        state = %{state | gives: gives, last_gives: last_gives}

        if (state.seat_limit && map_size(gives) >= state.seat_limit) and
             length(state.seats) >= state.seat_limit do
          participating_seat_ids = Enum.map(state.seats, & &1.id)
          state = %{state | page_seat_ids: participating_seat_ids}
          {:ok, state, [{:author, author_request(state)}]}
        else
          {:ok, state, []}
        end
    end
  end

  def apply(%__MODULE__{} = state, {:mask_landed, %{seat_id: seat_id} = attrs}) do
    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      true ->
        mask =
          case Map.get(attrs, :mask) do
            m when is_map(m) -> Map.delete(m, :bytes)
            other -> other
          end

        masks = Map.put(state.masks || %{}, seat_id, mask)
        {:ok, %{state | masks: masks}, []}
    end
  end

  def apply(%__MODULE__{} = state, {:mask_landed, seat_id, mask}) when is_binary(seat_id) do
    apply(state, {:mask_landed, %{seat_id: seat_id, mask: mask}})
  end

  def apply(%__MODULE__{} = state, {:start_page, %{seat_id: seat_id}}) do
    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      phase(state) != :giving ->
        {:error, :not_giving}

      not Map.has_key?(state.gives, seat_id) ->
        {:error, :give_required}

      map_size(state.gives) < 2 ->
        {:error, :not_enough_gives}

      true ->
        participating_seat_ids =
          state.seats
          |> Enum.filter(&Map.has_key?(state.gives, &1.id))
          |> Enum.map(& &1.id)

        state = %{state | page_seat_ids: participating_seat_ids}
        {:ok, state, [{:author, author_request(state)}]}
    end
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
        origins = origins_from(state, attrs[:from] || attrs["from"], bookends)

        page = %{
          bookends: bookends,
          bookend_origins: origins,
          gives: state.gives,
          meta: meta,
          full_table: page_full_table(attrs, state.full_table)
        }

        {:ok,
         %{
           state
           | page: page,
             bookends: bookends,
             bookend_origins: origins,
             attempt: 1,
             bridges: %{},
             verdict: nil,
             played: [],
             overrule: nil,
             overrules: [],
             fairness_taps: %{},
             bookends_taps: %{},
             author_failure: nil
         }, []}
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
    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      phase(state) != :writing or is_nil(state.author_failure) ->
        {:error, :not_failed}

      true ->
        {:ok, %{state | author_failure: nil}, [{:author, author_request(state)}]}
    end
  end

  def apply(%__MODULE__{} = state, {:gives_reset, %{seat_id: seat_id}}) do
    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      phase(state) != :writing ->
        {:error, :not_writing}

      true ->
        {:ok, %{state | gives: %{}, masks: %{}, author_failure: nil, page_seat_ids: nil}, []}
    end
  end

  def apply(%__MODULE__{} = state, {:bridge_committed, %{seat_id: seat_id, bridge: bridge}}) do
    bridge = Thereish.Steward.Legality.normalize_bridge(bridge)

    cond do
      phase(state) != :bridging ->
        {:error, :not_bridging}

      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      playing_page_seat(state, seat_id) != :ok ->
        {:error, :not_playing_page}

      committed?(state, seat_id) ->
        {:error, :already_committed}

      bridge == "" ->
        {:error, :bridge_required}

      true ->
        case Thereish.Steward.Legality.check_bridge(bridge, barred_words(state)) do
          :ok -> committed(%{state | bridges: Map.put(state.bridges, seat_id, bridge)})
          {:illegal, reason} -> {:error, {:illegal_bridge, reason}}
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
      pairs: Map.get(verdict, :pairs),
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
    closeness = Map.get(attrs, :closeness, Ladder.meld_threshold())

    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      playing_page_seat(state, seat_id) != :ok ->
        {:error, :not_playing_page}

      phase(state) not in [:reveal, :closed] or is_nil(state.verdict) ->
        {:error, :not_revealed}

      state.overrule != nil ->
        {:error, :proposal_pending}

      already_overruled?(state, seat_id) ->
        {:error, :already_overruled}

      true ->
        proposed_state = %{
          state
          | overrule: %{
              proposer_id: seat_id,
              closeness: closeness,
              agreed: MapSet.new([seat_id])
            }
        }

        resolve_overrule_unanimity(proposed_state, proposed_state.overrule.agreed)
    end
  end

  def apply(%__MODULE__{} = state, {:overrule_agreed, %{seat_id: seat_id}}) do
    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      playing_page_seat(state, seat_id) != :ok ->
        {:error, :not_playing_page}

      state.overrule == nil ->
        {:error, :no_proposal_pending}

      true ->
        agreed = MapSet.put(state.overrule.agreed, seat_id)
        state = %{state | overrule: %{state.overrule | agreed: agreed}}
        resolve_overrule_unanimity(state, agreed)
    end
  end

  def apply(%__MODULE__{} = state, {:overrule_declined, %{seat_id: seat_id}}) do
    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      playing_page_seat(state, seat_id) != :ok ->
        {:error, :not_playing_page}

      state.overrule == nil ->
        {:error, :no_proposal_pending}

      true ->
        {:ok, %{state | overrule: nil}, []}
    end
  end

  def apply(%__MODULE__{} = state, {:fairness_tapped, %{seat_id: seat_id, label: label}}) do
    verdict = state.verdict
    label_str = normalize_label(label)

    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      playing_page_seat(state, seat_id) != :ok ->
        {:error, :not_playing_page}

      phase(state) not in [:reveal, :closed] or is_nil(verdict) ->
        {:error, :not_revealed}

      is_nil(verdict.closeness) and is_nil(Map.get(verdict, :original_closeness)) ->
        {:error, :not_assayed}

      label_str not in ["fair", "too_kind", "too_harsh"] ->
        {:error, :invalid_label}

      true ->
        grade = Map.get(verdict, :original_closeness) || verdict.closeness
        band = Map.get(verdict, :original_band) || (grade && Ladder.read(grade).band)
        meta = verdict.meta || %{}
        bridges = written_bridges(state)

        tap_effect_data = %{
          seat_id: seat_id,
          attempt_number: state.attempt,
          bookends: state.bookends,
          bridges: bridges,
          grade: grade,
          closeness: grade,
          band: band && to_string(band),
          model: meta[:model],
          prompt_version: meta[:prompt_version],
          label: label_str
        }

        current_taps = state.fairness_taps || %{}
        next_state = %{state | fairness_taps: Map.put(current_taps, seat_id, label_str)}

        {:ok, next_state, [{:fairness_tap, tap_effect_data}]}
    end
  end

  def apply(%__MODULE__{} = state, {:attempt_advanced, %{seat_id: seat_id}}) do
    with :ok <- taken_by_a_seat(state, seat_id),
         :ok <- playing_page_seat(state, seat_id),
         :ok <- open_reveal(state) do
      carried = carried(state)

      {:ok,
       %{
         state
         | bookends: Enum.map(carried, & &1.word),
           bookend_origins: Enum.map(carried, &Map.take(&1, [:seat_id])),
           attempt: state.attempt + 1,
           bridges: %{},
           verdict: nil,
           furthest: nil,
           played: state.played ++ [this_attempt(state)],
           overrule: nil,
           fairness_taps: %{}
       }, []}
    end
  end

  def apply(%__MODULE__{} = state, {:page_started, %{seat_id: seat_id, page: page}}) do
    with :ok <- taken_by_a_seat(state, seat_id),
         :ok <- closed_page(state) do
      {:ok,
       %{
         state
         | page: page,
           bookends: page && (Map.get(page, :bookends) || Map.get(page, "bookends")),
           bookend_origins: page_origins(page),
           attempt: 1,
           bridges: %{},
           verdict: nil,
           furthest: nil,
           played: [],
           overrule: nil,
           overrules: [],
           fairness_taps: %{}
       }, []}
    end
  end

  def apply(%__MODULE__{} = state, {:bookends_tapped, %{seat_id: seat_id, label: label}}) do
    label_str = normalize_label(label)

    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      phase(state) != :closed ->
        {:error, :not_closed}

      label_str not in ["flat", "fine", "great"] ->
        {:error, :invalid_label}

      true ->
        meta = (state.page && state.page[:meta]) || %{}
        arm = meta[:arm] || meta["arm"]
        bookends = (state.page && state.page[:bookends]) || state.bookends

        page_id =
          (state.page && (state.page[:id] || state.page["id"])) ||
            (bookends && Enum.join(bookends, "-")) || "page"

        tap_effect_data = %{
          page_id: page_id,
          page_identifier: page_id,
          seat_id: seat_id,
          label: label_str,
          bookends: bookends,
          gives: (state.page && state.page[:gives]) || state.gives,
          author_meta: meta,
          arm: arm
        }

        current_taps = state.bookends_taps || %{}
        next_state = %{state | bookends_taps: Map.put(current_taps, seat_id, label_str)}

        {:ok, next_state, [{:bookends_tap, tap_effect_data}]}
    end
  end

  def apply(%__MODULE__{} = state, {:next_page, %{seat_id: seat_id}}) do
    with :ok <- taken_by_a_seat(state, seat_id),
         :ok <- closed_page(state) do
      last_gives = Map.merge(state.last_gives || %{}, state.gives || %{})

      {:ok,
       %{
         state
         | page: nil,
           bookends: nil,
           bookend_origins: nil,
           attempt: 1,
           gives: %{},
           last_gives: last_gives,
           bridges: %{},
           verdict: nil,
           furthest: nil,
           played: [],
           overrule: nil,
           overrules: [],
           fairness_taps: %{},
           bookends_taps: %{},
           author_failure: nil,
           page_seat_ids: nil,
           track: state.track,
           track_held_over: not is_nil(state.track),
           masks: %{}
       }, []}
    end
  end

  @doc """
  Projects what one viewer may see: a Seat by its id, or `nil` for a viewer that
  holds no Seat — the stage on the laptop, or a phone still at the name form.

  Everyone gets the same roster, the same Bookends and the same reveal — the
  stage and the phones must never disagree about the Page they are playing. The
  only things that differ are which Seat is the viewer's own and which Bridge it
  wrote, and an uncommitted Bridge is in nobody's view but its author's until
  every Seat has committed.
  """
  @spec view(t(), viewer()) :: map()
  def view(%__MODULE__{} = state, viewer) do
    phase = phase(state)
    fairness_taps = state.fairness_taps || %{}

    viewer_late? =
      state.page_seat_ids != nil and viewer != nil and viewer not in state.page_seat_ids

    %{
      phase: phase,
      late?: viewer_late?,
      seats: Enum.map(state.seats, &seat_view(state, &1, viewer)),
      you: find_seat(state, viewer),
      seat_limit: state.seat_limit,
      open_seats: state.seat_limit - length(state.seats),
      bookends: bookends(state, phase),
      bookend_chips: bookend_chips(state, phase),
      page_give: state.page && (state.page[:give] || state.page["give"]),
      page_chapter: state.page && (state.page[:chapter] || state.page["chapter"]),
      page_theme: state.page && (state.page[:theme] || state.page["theme"]),
      your_give: Map.get(state.gives, viewer),
      your_last_give: Map.get(state.last_gives, viewer),
      your_mask: if(viewer, do: Map.get(state.masks || %{}, viewer)),
      gives_in: map_size(state.gives),
      author_failure: state.author_failure,
      your_bridge: Map.get(state.bridges, viewer),
      attempt: %{number: state.attempt, of: attempt_cap()},
      reveal: reveal(state, phase, viewer),
      # What the next attempt will hang between, so the tap that starts it can
      # say so. The carry-forward is the point of a miss; a button that named
      # neither word would hide it.
      next_bookends: if(phase == :reveal, do: carried_bookends(state)),
      # Whether the Assayer picked those two words or the game fell back to the
      # first two Bridges in roster order. The couple are about to spend an
      # attempt on them, so which of the two happened is theirs to know. At a
      # Full table the table's own Bridges carry, so there is no choice to miss.
      next_bookends_chosen?: if(phase == :reveal, do: next_bookends_chosen?(state)),
      closed: closed(state, phase),
      played: Enum.map(state.played, &attempt_view(state, &1)),
      overrule: overrule_view(state, viewer),
      your_tap: Map.get(fairness_taps, viewer),
      fairness_taps: fairness_taps,
      your_bookends_tap: Map.get(state.bookends_taps || %{}, viewer),
      bookends_taps: state.bookends_taps || %{},
      barred_words: if(phase != :waiting, do: barred_words(state)),
      track: track_view(state),
      gives: if(phase in [:reveal, :closed] or state.played != [], do: gives_view(state)),
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
    past_bookends = Enum.flat_map(state.played, fn a -> a[:bookends] || a.bookends || [] end)

    past_bridges =
      Enum.flat_map(state.played, fn a -> Map.values(a[:bridges] || a.bridges || %{}) end)

    current_bookends = state.bookends || []

    (current_bookends ++ past_bookends ++ past_bridges)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp page_seats(state) do
    if state.page_seat_ids do
      Enum.filter(state.seats, &(&1.id in state.page_seat_ids))
    else
      state.seats
    end
  end

  defp author_request(state) do
    seat_ids = state.page_seat_ids || Enum.map(state.seats, & &1.id)
    participating = Enum.filter(state.seats, &(&1.id in seat_ids))

    gives =
      Enum.map(participating, fn s ->
        %{seat_id: s.id, name: s.name, text: state.gives[s.id], give: state.gives[s.id]}
      end)

    %{gives: gives, count: bookend_count(state, participating)}
  end

  defp bookend_count(%{full_table: false}, _seats), do: 2
  defp bookend_count(_state, seats), do: length(seats)

  # A Page keeps the rule it was written under. Omitted or missing (Pages from
  # before the rule, or a Room that has not written one yet) reads as the
  # Room's current rule, default on.
  defp page_full_table(attrs, default \\ true)

  defp page_full_table(attrs, default) when is_map(attrs) do
    case Map.get(attrs, :full_table, Map.get(attrs, "full_table", default)) do
      false -> false
      _ -> true
    end
  end

  defp page_full_table(_, default), do: default == true

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
  defp bookends(state, _phase), do: state.bookends

  # The Bridges go in roster order, the order the reveal puts them in, so that
  # the sentence the Assayer writes, the joke it makes and the two words it
  # names as furthest apart all read in the order they are on the screen.
  #
  # assay-4 carries Bookends of two or more, Bridges with player names in roster
  # order, earlier Attempts, and Gives.
  defp assay(state), do: {:assay, assay_request_overall(state)}

  defp assay_request_overall(state) do
    seats = page_seats(state)

    seat_bridges =
      Enum.map(seats, fn seat ->
        %{name: seat.name, bridge: state.bridges[seat.id]}
      end)

    %{
      bookends: state.bookends,
      bridges: written_bridges(state),
      seat_bridges: seat_bridges,
      player_bridges: seat_bridges,
      earlier_attempts:
        Enum.map(state.played, fn attempt ->
          attempt_bridges = attempt[:bridges] || attempt.bridges || %{}

          %{
            number: attempt[:number] || attempt.number,
            bookends: attempt[:bookends] || attempt.bookends,
            bridges:
              Enum.map(seats, fn seat ->
                %{name: seat.name, bridge: Map.get(attempt_bridges, seat.id)}
              end)
          }
        end),
      gives: gives_for_assay(state)
    }
  end

  defp gives_for_assay(state) do
    cond do
      is_nil(state.page) ->
        []

      gives = state.page[:gives] || state.page["gives"] ->
        case gives do
          list when is_list(list) ->
            list

          map when is_map(map) ->
            Enum.map(page_seats(state), fn seat ->
              %{name: seat.name, give: map[seat.id] || map[seat.name]}
            end)

          _ ->
            []
        end

      give = state.page[:give] || state.page["give"] ->
        if is_binary(give) and give != "" do
          [%{give: give}]
        else
          []
        end

      true ->
        []
    end
  end

  # Every Bridge of this attempt, in roster order.
  defp written_bridges(state), do: Enum.map(page_seats(state), &state.bridges[&1.id])

  # An Attempt is graded once. The Room can deliver the same verdict twice — a
  # retry, a message that outlived the attempt it was about — and the second one
  # must not be able to change a number the players are already looking at.
  defp record(state, verdict) do
    cond do
      state.verdict != nil -> {:ok, state, []}
      phase(state) != :assaying -> {:error, :no_verdict_expected}
      true -> graded(%{state | verdict: verdict})
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
      state.page_seat_ids != nil and state.page == nil ->
        :writing

      state.page != nil and (state.page_seat_ids != nil or full?(state)) ->
        seat_count =
          if state.page_seat_ids, do: length(state.page_seat_ids), else: length(state.seats)

        cond do
          map_size(state.bridges) < seat_count -> :bridging
          state.verdict == nil -> :assaying
          over?(state) -> :closed
          true -> :reveal
        end

      state.page != nil and not full?(state) ->
        :waiting

      not full?(state) and length(state.seats) < 2 ->
        :waiting

      state.page == nil and full?(state) and map_size(state.gives) >= length(state.seats) ->
        :writing

      true ->
        :giving
    end
  end

  # Both ways a Page ends. A Meld ends it the moment it lands, so that landing it
  # is the last thing that happens rather than one more rung; spending the last
  # attempt ends it too, and that is an ending rather than a failure.
  defp over?(state), do: melded?(state) or state.attempt >= attempt_cap()

  defp melded?(state) do
    state |> headline() |> Ladder.read() |> Map.fetch!(:melded?)
  end

  defp closed_because(state), do: if(melded?(state), do: :meld, else: :attempts_spent)

  defp closed(_state, phase) when phase != :closed, do: nil

  defp closed(state, _phase), do: %{because: closed_because(state), attempt: state.attempt}

  # One reveal for every Seat: every Bridge, one number in its band, one quip,
  # the two words that landed furthest apart, and every pair of Seats graded
  # alongside the one Verdict (ADR-0010, ticket 07). Reasoning is kept in the
  # Chronicle and kept off the screen.
  defp reveal(state, phase, viewer) when phase in [:reveal, :closed] do
    gives = gives_view(state)

    base =
      state.verdict
      |> verdict_view()
      |> Map.delete(:reasoning)
      |> Map.merge(%{
        bridges: bridges_view(state, state.bridges),
        furthest: furthest_view(state, chosen_furthest(state)),
        gives: gives
      })

    if state.verdict && state.verdict[:pairs] do
      pairs = pairs_view(state, state.verdict[:pairs], viewer)
      Map.put(base, :pairs, pairs)
    else
      base
    end
  end

  defp reveal(_state, _phase, _viewer), do: nil

  defp track_view(%{track: nil}), do: nil

  defp track_view(%{track: track} = state) do
    if state.track_held_over or phase(state) in [:reveal, :closed] or state.played != [] do
      track
    else
      Map.delete(track, :title)
    end
  end

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

  defp normalize_track(nil), do: nil
  defp normalize_track(track) when is_binary(track), do: %{title: track}
  defp normalize_track(track) when is_map(track), do: track

  # The Page's number is the Verdict's, and an Attempt the Assayer could not
  # grade has no number rather than a zero: "we don't know" is not "you missed".
  defp headline(%{verdict: %{graded?: true, closeness: closeness}}), do: closeness

  defp headline(_state), do: nil

  # Carry-forward reads the Page's rule (ADR-0016). At a Full table every
  # Seat's Bridge becomes the next Attempt's Bookends, in roster order. Off, the
  # two the Assayer named as furthest apart carry — Medium's rule — and with no
  # Verdict the first two in roster order carry, which `next_bookends_chosen?`
  # tells the screens.
  #
  # Nothing here defends against two carried words being the same word: that
  # needs an Assayer that names a word twice, and if one ever does, the next
  # attempt is a Page with one word twice rather than a crash.
  defp carried_bookends(state), do: Enum.map(carried(state), & &1.word)

  defp carried(state) do
    if page_full_table(state.page, state.full_table) do
      Enum.map(page_seats(state), fn seat ->
        %{word: state.bridges[seat.id], seat_id: seat.id}
      end)
    else
      two_carried(state)
    end
  end

  defp two_carried(state) do
    words = chosen_furthest(state) || Enum.take(written_bridges(state), 2)

    {origins, _remaining} =
      Enum.map_reduce(words, written_seat_bridges(state), fn word, remaining ->
        case Enum.split_while(remaining, fn {_seat, bridge} -> bridge != word end) do
          {passed, [{seat, _} | rest]} ->
            {%{word: word, seat_id: seat.id}, passed ++ rest}

          {_all, []} ->
            {%{word: word}, remaining}
        end
      end)

    origins
  end

  defp written_seat_bridges(state) do
    for seat <- page_seats(state), Map.has_key?(state.bridges, seat.id) do
      {seat, state.bridges[seat.id]}
    end
  end

  defp next_bookends_chosen?(state) do
    page_full_table(state.page, state.full_table) or chosen_furthest(state) != nil
  end

  defp bookend_chips(_state, phase) when phase in [:waiting, :giving, :writing], do: nil

  defp bookend_chips(state, _phase) do
    words = state.bookends || []
    origins = pad_origins(state.bookend_origins, length(words))

    Enum.zip(words, origins)
    |> Enum.map(fn {word, origin} ->
      seat_id = origin[:seat_id] || origin["seat_id"]
      give = origin[:give] || origin["give"]
      show_mask? = state.attempt > 1 and is_binary(seat_id)

      %{
        word: word,
        seat_id: seat_id,
        give: give,
        mask: if(show_mask?, do: Map.get(state.masks || %{}, seat_id))
      }
    end)
  end

  defp pad_origins(origins, count) when is_list(origins) and length(origins) >= count,
    do: Enum.take(origins, count)

  defp pad_origins(origins, count) when is_list(origins) do
    origins ++ List.duplicate(%{}, count - length(origins))
  end

  defp pad_origins(_, count), do: List.duplicate(%{}, count)

  defp page_origins(nil), do: nil

  defp page_origins(page) when is_map(page) do
    page[:bookend_origins] || page["bookend_origins"] ||
      page[:bookend_gives] || page["bookend_gives"] ||
      Enum.map(page[:bookends] || page["bookends"] || [], fn _ -> %{} end)
  end

  defp origins_from(_state, nil, bookends), do: Enum.map(bookends, fn _ -> %{} end)

  defp origins_from(state, from, bookends) when is_list(from) do
    by_name =
      Map.new(page_seats(state), fn seat ->
        {String.downcase(String.trim(seat.name)), seat}
      end)

    Enum.zip(bookends, from)
    |> Enum.map(fn {word, name} ->
      case Map.get(by_name, name |> to_string() |> String.trim() |> String.downcase()) do
        nil ->
          %{word: word}

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

  defp origins_from(_state, _from, bookends), do: Enum.map(bookends, fn _ -> %{} end)

  # The two words the Assayer named, but only if the roster can account for both
  # of them: they are about to be Bookends, and a Bookend nobody wrote is a Page
  # the table was never asked to play. A paraphrase is no choice at all, so the
  # game falls back and says it fell back.
  defp chosen_furthest(%{verdict: %{graded?: true, furthest: [_, _] = furthest}} = state) do
    if furthest_view(state, furthest), do: furthest
  end

  defp chosen_furthest(_state), do: nil

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

  # The furthest two, said the way the reveal says them: the word and whose it
  # is. Each is claimed from the roster and taken out of it, so a table that
  # wrote one word twice does not read as one player disagreeing with
  # themselves, and a word the roster cannot account for is no pair at all.
  defp furthest_view(_state, nil), do: nil

  defp furthest_view(state, furthest) do
    {views, _unclaimed} =
      Enum.map_reduce(furthest, bridges_view(state, state.bridges), &claim_bridge/2)

    if Enum.all?(views), do: views
  end

  defp claim_bridge(word, unclaimed) do
    case Enum.split_while(unclaimed, &(&1.bridge != word)) do
      {passed, [claimed | rest]} -> {claimed, passed ++ rest}
      {_all, []} -> {nil, unclaimed}
    end
  end

  defp bridges_view(state, bridges) do
    for seat <- state.seats, Map.has_key?(bridges, seat.id) do
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

  defp this_attempt(state) do
    %{
      number: state.attempt,
      bookends: state.bookends,
      bridges: state.bridges,
      verdict: state.verdict,
      furthest: state.furthest
    }
  end

  # The whole Page as it was played, for the Room to write down. Everything the
  # Chronicle keeps about a Page is here, including the attempts that were
  # already over when this one closed.
  defp chronicle(state) do
    attempts = state.played ++ [this_attempt(state)]

    %{
      page: state.page,
      bookends: state.bookends,
      gives:
        Enum.map(page_seats(state), fn seat ->
          %{
            seat_id: seat.id,
            seat_name: seat.name,
            text: state.gives[seat.id] || "",
            mask: Map.get(state.masks || %{}, seat.id)
          }
        end),
      masks: state.masks || %{},
      author_meta: state.page && (state.page[:meta] || state.page["meta"]),
      closed_because: closed_because(state),
      melded?: melded?(state),
      closeness: headline(state),
      attempts: Enum.map(attempts, &chronicle_attempt(state, &1)),
      overrules: state.overrules
    }
  end

  defp overrule_view(%{overrule: nil}, _viewer), do: nil

  defp overrule_view(%{overrule: overrule} = state, viewer) do
    proposer = find_seat(state, overrule.proposer_id)

    %{
      pending?: true,
      proposer_id: overrule.proposer_id,
      proposer_name: proposer && proposer.name,
      closeness: overrule.closeness,
      agreed_seat_ids: MapSet.to_list(overrule.agreed),
      you_proposed?: viewer == overrule.proposer_id,
      you_agreed?: MapSet.member?(overrule.agreed, viewer)
    }
  end

  defp already_overruled?(state, _seat_id) do
    state.verdict != nil and Map.get(state.verdict, :overruled?, false)
  end

  defp resolve_overrule_unanimity(state, agreed) do
    required = state.page_seat_ids || Enum.map(state.seats, & &1.id)

    if Enum.all?(required, &MapSet.member?(agreed, &1)) do
      agree_overrule(state)
    else
      {:ok, state, []}
    end
  end

  defp agree_overrule(state) do
    apply_agreed_overrule(
      state,
      state.verdict,
      "Overruled jointly across all Seats. Recorded as precedent.",
      written_bridges(state),
      fn s, new_verdict -> %{s | verdict: new_verdict} end
    )
  end

  defp apply_agreed_overrule(
         state,
         original_verdict,
         couple_reasoning,
         bridges,
         update_verdict_fn
       ) do
    previously_closed? = phase(state) == :closed

    %{proposer_id: proposer_id, closeness: couple_closeness} = state.overrule
    couple_quip = "House law."

    new_verdict =
      Map.merge(original_verdict, %{
        graded?: true,
        closeness: couple_closeness,
        reasoning: couple_reasoning,
        quip: couple_quip,
        overruled?: true,
        original_closeness: original_verdict.closeness,
        original_reasoning: original_verdict.reasoning,
        original_quip: original_verdict.quip
      })

    overrule_effect_data = %{
      attempt_number: state.attempt,
      proposer_seat_id: proposer_id,
      bookends: state.bookends,
      bridges: bridges,
      machine_closeness: original_verdict.closeness,
      machine_reasoning: original_verdict.reasoning,
      machine_quip: original_verdict.quip,
      couple_closeness: couple_closeness,
      couple_reasoning: couple_reasoning,
      couple_quip: couple_quip
    }

    overrules = state.overrules ++ [overrule_effect_data]
    state = update_verdict_fn.(state, new_verdict)
    state = %{state | overrule: nil, overrules: overrules}

    effects = [{:overrule, overrule_effect_data}]

    effects =
      if phase(state) == :closed and not previously_closed? do
        effects ++ [{:chronicle, chronicle(state)}]
      else
        effects
      end

    {:ok, state, effects}
  end

  # An attempt as the arc reads it, plus the one Verdict behind it. The book
  # keeps a list because an attempt has held more than one row before and the
  # rows are what a reader counts; today that list is one long (ADR-0010).
  defp chronicle_attempt(state, attempt) do
    verdicts =
      if attempt.verdict do
        [chronicle_verdict(state, attempt)]
      else
        []
      end

    state
    |> attempt_view(attempt)
    |> Map.put(:verdicts, verdicts)
  end

  # A verdict row says which word every Seat had in it, in the same order as the
  # Seats it names, so the row can be read without joining anything back to it —
  # and which two of those words the Assayer sent the couple to next.
  defp chronicle_verdict(state, attempt) do
    verdict = attempt.verdict
    seats = page_seats(state)

    verdict
    |> verdict_view()
    |> Map.merge(%{
      seat_ids: Enum.map(seats, & &1.id),
      names: Enum.map(seats, & &1.name),
      bridges: Enum.map(seats, &attempt.bridges[&1.id]),
      furthest: Map.get(verdict, :furthest),
      meta: verdict.meta
    })
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
    seat_late? = state.page_seat_ids != nil and seat.id not in state.page_seat_ids

    %{
      id: seat.id,
      name: seat.name,
      colour: seat_colour(state, seat),
      mask: mask_for_viewer(state, seat, viewer),
      you?: seat.id == viewer,
      committed?: committed?(state, seat.id),
      late?: seat_late?
    }
  end

  defp mask_for_viewer(state, seat, viewer) do
    raw_mask = Map.get(state.masks || %{}, seat.id)
    first_reveal? = phase(state) in [:reveal, :closed] or state.played != []

    cond do
      first_reveal? ->
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

  defp pairs_view(state, pair_verdicts, _viewer) do
    all_pairs =
      for {seat_a, idx} <- Enum.with_index(state.seats),
          seat_b <- Enum.drop(state.seats, idx + 1) do
        {seat_a, seat_b}
      end

    pairs =
      Enum.map(all_pairs, fn {seat_a, seat_b} ->
        pair_ids = [seat_a.id, seat_b.id]
        names = [seat_a.name, seat_b.name]
        bridge_a = state.bridges[seat_a.id]
        bridge_b = state.bridges[seat_b.id]
        bridges = [bridge_a, bridge_b]

        v =
          (pair_verdicts || [])
          |> Enum.find(fn pv ->
            p_ids = pv[:seat_ids] || pv["seat_ids"] || []
            seat_a.id in p_ids and seat_b.id in p_ids
          end)

        closeness =
          cond do
            v && (v[:closeness] != nil || v["closeness"] != nil) ->
              v[:closeness] || v["closeness"]

            (length(state.seats) == 2 and state.verdict) && state.verdict.closeness != nil ->
              state.verdict.closeness

            true ->
              nil
          end

        band_info = if closeness, do: Ladder.read(closeness), else: %{band: nil, melded?: false}
        melded? = band_info.melded?
        band = band_info.band

        pair_data = %{
          seat_ids: pair_ids,
          names: names,
          bridges: bridges,
          closeness: closeness,
          band: band,
          melded?: melded?,
          couple?: false,
          cross_couple?: false,
          cross_couple_meld?: false,
          surprise: nil
        }

        {pair_data, false}
      end)

    pairs
    |> Enum.sort_by(fn {p, viewer_couple?} ->
      cond do
        viewer_couple? -> {0, 0}
        p.couple? -> {1, -(p.closeness || 0)}
        p.cross_couple_meld? -> {2, -(p.closeness || 0)}
        true -> {3, -(p.closeness || 0)}
      end
    end)
    |> Enum.map(fn {p, _} -> p end)
  end

  defp taken_by_a_seat(state, seat_id) do
    if seated?(state, seat_id), do: :ok, else: {:error, :no_such_seat}
  end

  defp playing_page_seat(state, seat_id) do
    if state.page_seat_ids != nil and seat_id not in state.page_seat_ids do
      {:error, :not_playing_page}
    else
      :ok
    end
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

  defp committed?(state, seat_id), do: Map.has_key?(state.bridges, seat_id)

  defp find_seat(state, seat_id), do: Enum.find(state.seats, &(&1.id == seat_id))

  defp full?(state), do: length(state.seats) >= state.seat_limit

  defp normalize_label(:fair), do: "fair"
  defp normalize_label(:too_kind), do: "too_kind"
  defp normalize_label(:too_harsh), do: "too_harsh"
  defp normalize_label("fair"), do: "fair"
  defp normalize_label("too_kind"), do: "too_kind"
  defp normalize_label("too kind"), do: "too_kind"
  defp normalize_label("too_harsh"), do: "too_harsh"
  defp normalize_label("too harsh"), do: "too_harsh"

  defp normalize_label(other) when is_binary(other),
    do: other |> String.trim() |> String.downcase()

  defp normalize_label(other), do: to_string(other)

  defp seat(%{id: id, name: name}) do
    %{id: id, name: name}
  end

  defp seated?(state, seat_id), do: find_seat(state, seat_id) != nil
end
