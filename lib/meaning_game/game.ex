defmodule MeaningGame.Game do
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
  the clearest case: every unordered pair of Seats gets its own closeness and
  the headline number is the mean across them, which at two Seats is one pair
  and nothing special-cased.

  This module knows nothing about devices, browsers, or Postgres. A Seat here is
  just an id and the name its player typed; who is holding it and how they got
  back to it are the Room's problem.

  ## A Page is a ladder of attempts, not one shot

  A miss does not end the Page. The two Bridges that missed become the next
  attempt's Anchors — Medium's carry-forward rule — so the words the couple
  reach for narrow towards each other and a missed Page converges rather than
  collapsing. After `attempt_cap/0` tries the Page closes unmelded, and a Meld
  closes it the moment it lands.

  ## Phase is derived, never stored

  Where a Page has got to is a question about the state rather than a field in
  it: a Room that is not full is `:waiting`, a full Room with a Page is
  `:bridging`, every Bridge in makes it `:assaying`, every pair graded makes it
  `:reveal`, and a reveal that melded or spent the last attempt makes it
  `:closed`. Nothing has to remember to advance it, and in particular nothing
  has to remember to end a Page — which is why a Meld closing one is not an
  event that could go missing.

  One deliberate departure from the spec's sketch of this module: `apply/2` can
  answer `{:error, reason}`, because whether a Bridge may be written is a rule
  and rules live here.
  """

  # `apply/2` is the name the spec gives this function, and the reducer shape is
  # worth more than the Kernel import it displaces.
  import Kernel, except: [apply: 2]

  alias MeaningGame.Ladder

  @enforce_keys [:seat_limit, :seats]
  defstruct [
    :seat_limit,
    :seats,
    :page,
    :anchors,
    attempt: 1,
    bridges: %{},
    verdicts: %{},
    played: [],
    overrule: nil,
    overrules: [],
    fairness_taps: %{}
  ]

  @type seat :: %{id: String.t(), name: String.t()}
  @type page :: %{id: String.t(), anchors: [String.t()]}

  @typedoc "Two Seat ids, sorted, so both orderings of a pair name one thing."
  @type pair :: [String.t()]

  @typedoc """
  What the Assayer said about one pair, or that it could not say.

  `quip` is the joke it made about the two words these players actually wrote.
  The rules keep it beside the reasoning and never read it: the reveal is the
  product, and the line that makes it funny is not chrome the view can invent
  for itself.

  `meta` is provenance — which model answered, at what prompt version, how long
  it took, what it cost. The rules carry it to the Chronicle and never read it;
  a grade is a grade whoever produced it.
  """
  @type verdict :: %{
          graded?: boolean(),
          closeness: integer() | nil,
          reasoning: String.t() | nil,
          quip: String.t() | nil,
          meta: map()
        }

  @typedoc "One attempt as it was played, kept so the Chronicle can have it."
  @type attempt :: %{
          number: pos_integer(),
          anchors: [String.t()],
          bridges: %{String.t() => String.t()},
          verdicts: %{pair() => verdict()}
        }

  @type t :: %__MODULE__{
          seat_limit: pos_integer(),
          seats: [seat()],
          page: page() | nil,
          anchors: [String.t()] | nil,
          attempt: pos_integer(),
          bridges: %{String.t() => String.t()},
          verdicts: %{pair() => verdict()},
          played: [attempt()],
          overrule: map() | nil,
          overrules: [map()],
          fairness_taps: %{String.t() => String.t()}
        }

  @type viewer :: String.t() | nil

  @type event ::
          {:seat_joined, seat()}
          | {:bridge_committed, %{seat_id: String.t(), bridge: String.t()}}
          | {:verdict_received,
             %{
               pair: pair(),
               closeness: integer(),
               reasoning: String.t(),
               quip: String.t(),
               meta: map()
             }}
          | {:verdict_unavailable, %{pair: pair(), meta: map()}}
          | {:attempt_advanced, %{seat_id: String.t()}}
          | {:page_started, %{seat_id: String.t(), page: page()}}
          | {:overrule_proposed,
             %{
               required(:seat_id) => String.t(),
               optional(:pair) => pair(),
               optional(:closeness) => integer()
             }}
          | {:overrule_agreed, %{seat_id: String.t()}}
          | {:overrule_declined, %{seat_id: String.t()}}
          | {:fairness_tapped,
             %{
               required(:seat_id) => String.t(),
               required(:label) => String.t() | atom(),
               optional(:pair) => pair()
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
          | {:assay, pair(), %{anchors: [String.t()], bridges: [String.t()]}}
          | {:chronicle, map()}
          | {:overrule, map()}
          | {:fairness_tap, map()}

  @type error ::
          :room_full
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

    %__MODULE__{
      seat_limit: Keyword.fetch!(opts, :seat_limit),
      seats: opts |> Keyword.get(:seats, []) |> Enum.map(&seat/1),
      page: page,
      anchors: page && page.anchors
    }
  end

  @doc """
  How many attempts one Page gets before it closes unmelded.

  Named configuration rather than a constant, because five is a guess about how
  long a converging arc stays funny and the couch is what settles it. It is read
  here, inside the rules, for the same reason `MeaningGame.Ladder`'s band
  boundaries are: the cap and the boundaries are the same kind of thing — numbers
  the couple's play moves — and splitting them so that one is passed in and the
  other is looked up would make the pair harder to calibrate together.
  """
  @spec attempt_cap() :: pos_integer()
  def attempt_cap, do: Application.fetch_env!(:meaning_game, :attempts_per_page)

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
      seated?(state, seat.id) -> {:ok, state, []}
      full?(state) -> {:error, :room_full}
      true -> {:ok, %{state | seats: state.seats ++ [seat]}, []}
    end
  end

  def apply(%__MODULE__{} = state, {:bridge_committed, %{seat_id: seat_id, bridge: bridge}}) do
    bridge = normalize(bridge)

    cond do
      phase(state) != :bridging ->
        {:error, :not_bridging}

      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      committed?(state, seat_id) ->
        {:error, :already_committed}

      bridge == "" ->
        {:error, :bridge_required}

      true ->
        case MeaningGame.Keeper.Legality.check_bridge(bridge, state.anchors) do
          :ok -> committed(%{state | bridges: Map.put(state.bridges, seat_id, bridge)})
          {:illegal, reason} -> {:error, {:illegal_bridge, reason}}
        end
    end
  end

  def apply(%__MODULE__{} = state, {:verdict_received, %{pair: pair} = verdict}) do
    quip = Map.get(verdict, :quip) || fallback_quip(state, pair)

    record(state, pair, %{
      graded?: true,
      closeness: verdict.closeness,
      reasoning: verdict.reasoning,
      quip: quip,
      meta: Map.get(verdict, :meta, %{})
    })
  end

  def apply(%__MODULE__{} = state, {:verdict_unavailable, %{pair: pair} = event}) do
    quip = Map.get(event, :quip) || fallback_quip(state, pair)

    record(state, pair, %{
      graded?: false,
      closeness: nil,
      reasoning: nil,
      quip: quip,
      meta: Map.get(event, :meta, %{})
    })
  end

  def apply(%__MODULE__{} = state, {:overrule_proposed, %{seat_id: seat_id} = attrs}) do
    pair = Map.get(attrs, :pair) || default_pair(state)
    closeness = Map.get(attrs, :closeness, 100)

    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      phase(state) not in [:reveal, :closed] or state.verdicts == %{} ->
        {:error, :not_revealed}

      state.overrule != nil ->
        {:error, :proposal_pending}

      already_overruled?(state, pair) ->
        {:error, :already_overruled}

      true ->
        proposed_state = %{
          state
          | overrule: %{
              proposer_id: seat_id,
              pair: pair,
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

      state.overrule == nil ->
        {:error, :no_proposal_pending}

      true ->
        {:ok, %{state | overrule: nil}, []}
    end
  end

  def apply(%__MODULE__{} = state, {:fairness_tapped, %{seat_id: seat_id, label: label} = attrs}) do
    pair = Map.get(attrs, :pair) || default_pair(state)
    verdict = Map.get(state.verdicts, pair)
    label_str = normalize_label(label)

    cond do
      not seated?(state, seat_id) ->
        {:error, :no_such_seat}

      phase(state) not in [:reveal, :closed] or is_nil(verdict) ->
        {:error, :not_revealed}

      is_nil(verdict.closeness) and is_nil(Map.get(verdict, :original_closeness)) ->
        {:error, :not_assayed}

      label_str not in ["fair", "too_kind", "too_harsh"] ->
        {:error, :invalid_label}

      true ->
        bridges = for seat <- state.seats, seat.id in pair, do: state.bridges[seat.id]
        grade = Map.get(verdict, :original_closeness) || verdict.closeness
        band = Map.get(verdict, :original_band) || (grade && Ladder.read(grade).band)
        meta = verdict.meta || %{}

        tap_effect_data = %{
          seat_id: seat_id,
          attempt_number: state.attempt,
          anchors: state.anchors,
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
         :ok <- open_reveal(state) do
      {:ok,
       %{
         state
         | anchors: carried_anchors(state),
           attempt: state.attempt + 1,
           bridges: %{},
           verdicts: %{},
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
           anchors: page.anchors,
           attempt: 1,
           bridges: %{},
           verdicts: %{},
           played: [],
           overrule: nil,
           overrules: [],
           fairness_taps: %{}
       }, []}
    end
  end

  @doc """
  Projects what one viewer may see: a Seat by its id, or `nil` for a viewer that
  holds no Seat — the stage on the laptop, or a phone still at the name form.

  Everyone gets the same roster, the same Anchors and the same reveal — the
  stage and the phones must never disagree about the Page they are playing. The
  only things that differ are which Seat is the viewer's own and which Bridge it
  wrote, and an uncommitted Bridge is in nobody's view but its author's until
  every Seat has committed.
  """
  @spec view(t(), viewer()) :: map()
  def view(%__MODULE__{} = state, viewer) do
    phase = phase(state)
    fairness_taps = state.fairness_taps || %{}

    %{
      phase: phase,
      seats: Enum.map(state.seats, &seat_view(state, &1, viewer)),
      you: find_seat(state, viewer),
      seat_limit: state.seat_limit,
      open_seats: state.seat_limit - length(state.seats),
      anchors: anchors(state, phase),
      page_give: state.page && (state.page[:give] || state.page["give"]),
      page_chapter: state.page && (state.page[:chapter] || state.page["chapter"]),
      page_theme: state.page && (state.page[:theme] || state.page["theme"]),
      your_bridge: Map.get(state.bridges, viewer),
      attempt: %{number: state.attempt, of: attempt_cap()},
      reveal: reveal(state, phase),
      # What the next attempt will hang between, so the tap that starts it can
      # say so. The carry-forward is the point of a miss; a button that named
      # neither word would hide it.
      next_anchors: if(phase == :reveal, do: carried_anchors(state)),
      closed: closed(state, phase),
      played: Enum.map(state.played, &attempt_view(state, &1)),
      overrule: overrule_view(state, viewer),
      your_tap: Map.get(fairness_taps, viewer),
      fairness_taps: fairness_taps
    }
  end

  # `init`, `apply` and `view` are the whole surface. Everything below is reached
  # through them, including in tests — a rule that can only be seen by asking a
  # question no player can ask is not being tested where it lives.

  # The last Bridge in is the moment the Page turns: the Assayer is asked for
  # every pair at once, and the beat starts alongside rather than after, so the
  # theatre and the grading run in parallel.
  defp committed(state) do
    if phase(state) == :assaying do
      {:ok, state, [:beat | Enum.map(pairs(state), &assay(state, &1))]}
    else
      {:ok, state, []}
    end
  end

  # Nobody sees the Anchors until everybody can: a player alone in the Room with
  # the two words on screen is a player with a head start on the one still
  # typing their name.
  defp anchors(_state, :waiting), do: nil
  defp anchors(state, _phase), do: state.anchors

  # The pair is a key and is sorted, so that both orderings of it name one
  # thing. The Bridges inside the request are not: they go in roster order, the
  # order the reveal puts them in, so that the sentence the Assayer writes and
  # the joke it makes name the two words in the order they are on the screen.
  defp assay(state, pair) do
    bridges = for seat <- state.seats, seat.id in pair, do: state.bridges[seat.id]

    {:assay, pair, %{anchors: state.anchors, bridges: bridges}}
  end

  defp fallback_quip(%{page: %{} = page} = state, pair) do
    scripts = Map.get(page, :band_scripts) || Map.get(page, "band_scripts")

    if is_map(scripts) do
      bridges =
        state.seats
        |> Enum.filter(&(&1.id in pair))
        |> Enum.map(&state.bridges[&1.id])

      case bridges do
        [left, right] when is_binary(left) and is_binary(right) ->
          band = MeaningGame.Keeper.Author.provisional_reading(page, left, right)
          Map.get(scripts, to_string(band)) || Map.get(scripts, band)

        _ ->
          nil
      end
    end
  end

  defp fallback_quip(_state, _pair), do: nil

  # A pair is graded once. The Room can deliver the same verdict twice — a
  # retry, a message that outlived the attempt it was about — and the second one
  # must not be able to change a number the players are already looking at.
  defp record(state, pair, verdict) do
    pair = Enum.sort(pair)

    cond do
      pair not in pairs(state) ->
        {:error, :no_verdict_expected}

      Map.has_key?(state.verdicts, pair) ->
        {:ok, state, []}

      phase(state) != :assaying ->
        {:error, :no_verdict_expected}

      true ->
        graded(%{state | verdicts: Map.put(state.verdicts, pair, verdict)})
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

  # Read top to bottom, this is the Page's own order: fill the Room, write the
  # Bridges, grade the pairs, show it, and end.
  defp phase(state) do
    cond do
      state.page == nil or not full?(state) -> :waiting
      map_size(state.bridges) < length(state.seats) -> :bridging
      map_size(state.verdicts) < length(pairs(state)) -> :assaying
      over?(state) -> :closed
      true -> :reveal
    end
  end

  # Both ways a Page ends. A Meld ends it the moment it lands, so that landing it
  # is the last thing that happens rather than one more rung; spending the last
  # attempt ends it too, and that is an ending rather than a failure.
  defp over?(state), do: melded?(state) or state.attempt >= attempt_cap()

  defp melded?(state), do: state |> headline() |> Ladder.read() |> Map.fetch!(:melded?)

  defp closed_because(state), do: if(melded?(state), do: :meld, else: :attempts_spent)

  defp closed(_state, phase) when phase != :closed, do: nil

  defp closed(state, _phase), do: %{because: closed_because(state), attempt: state.attempt}

  # Every unordered pair of Seats, each sorted so that a verdict can be filed
  # under one key however the Assayer was asked. Two Seats is one pair.
  defp pairs(state) do
    ids = Enum.map(state.seats, & &1.id)

    for {id, index} <- Enum.with_index(ids), other <- Enum.drop(ids, index + 1) do
      Enum.sort([id, other])
    end
  end

  defp reveal(state, phase) when phase in [:reveal, :closed] do
    pairs = Enum.map(pairs(state), &pair_view(state, &1))

    Map.merge(Ladder.read(headline(state)), %{
      bridges: bridges_view(state, state.bridges),
      pairs: pairs,
      overruled?: Enum.any?(pairs, & &1.overruled?)
    })
  end

  defp reveal(_state, _phase), do: nil

  # The Page's number is the mean across the pairs that got one. A pair the
  # Assayer could not grade is left out rather than counted as a zero, because
  # "we don't know" is not "you missed".
  defp headline(state), do: state.verdicts |> Map.values() |> mean()

  defp mean(verdicts) do
    case verdicts |> Enum.filter(& &1.graded?) |> Enum.map(& &1.closeness) do
      [] -> nil
      graded -> round(Enum.sum(graded) / length(graded))
    end
  end

  # Medium's carry-forward rule, written for a list of Seats: the two Bridges
  # that missed by the most become the next attempt's Anchors. At two Seats that
  # is simply the two Bridges, which is the rule as the design states it; at
  # three it is the widest gap of the three, because the widest gap is the one
  # worth asking them to bridge. A pair the Assayer could not grade is not the
  # widest — an unknown is not a miss — so it is taken only when nothing was
  # graded at all.
  #
  # Nothing here defends against the two carried words being the same word: that
  # needs an Assayer that grades a word against itself below the meld threshold,
  # and if one ever does, the next attempt is a Page with one word twice rather
  # than a crash.
  defp carried_anchors(state) do
    widest = Enum.min_by(pairs(state), &how_close(state.verdicts[&1]))

    state.seats
    |> Enum.filter(&(&1.id in widest))
    |> Enum.map(&state.bridges[&1.id])
  end

  # How close a pair landed, ordered so that the least close sorts first. An
  # ungraded pair sorts last however low the graded ones are: the game does not
  # know that those two missed, and it will not guess that they missed hardest.
  defp how_close(%{graded?: true, closeness: closeness}), do: {0, closeness}
  defp how_close(_ungraded), do: {1, 0}

  # Names and ids come out in roster order rather than in the pair's own sorted
  # order, because the pair is a key and the roster is what people are looking
  # at.
  defp pair_view(state, pair), do: verdict_view(state, pair, state.verdicts[pair])

  defp verdict_view(state, pair, verdict) do
    seats = Enum.filter(state.seats, &(&1.id in pair))

    Map.merge(Ladder.read(verdict.closeness), %{
      seat_ids: Enum.map(seats, & &1.id),
      names: Enum.map(seats, & &1.name),
      graded?: verdict.graded?,
      reasoning: verdict.reasoning,
      quip: verdict.quip,
      overruled?: Map.get(verdict, :overruled?, false)
    })
  end

  defp bridges_view(state, bridges) do
    for seat <- state.seats, Map.has_key?(bridges, seat.id) do
      %{seat_id: seat.id, name: seat.name, bridge: bridges[seat.id]}
    end
  end

  # An attempt already played, as the arc at the close reads it.
  defp attempt_view(state, attempt) do
    Map.merge(Ladder.read(mean(Map.values(attempt.verdicts))), %{
      number: attempt.number,
      anchors: attempt.anchors,
      bridges: bridges_view(state, attempt.bridges)
    })
  end

  defp this_attempt(state) do
    %{
      number: state.attempt,
      anchors: state.anchors,
      bridges: state.bridges,
      verdicts: state.verdicts
    }
  end

  # The whole Page as it was played, for the Room to write down. Everything the
  # Chronicle keeps about a Page is here, including the attempts that were
  # already over when this one closed.
  defp chronicle(state) do
    attempts = state.played ++ [this_attempt(state)]

    %{
      page: state.page,
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
      pair: overrule.pair,
      closeness: overrule.closeness,
      agreed_seat_ids: MapSet.to_list(overrule.agreed),
      you_proposed?: viewer == overrule.proposer_id,
      you_agreed?: MapSet.member?(overrule.agreed, viewer)
    }
  end

  defp default_pair(state) do
    case pairs(state) do
      [single_pair] -> single_pair
      _ -> hd(pairs(state))
    end
  end

  defp already_overruled?(state, pair) do
    case Map.get(state.verdicts, pair) do
      %{overruled?: true} -> true
      _ -> false
    end
  end

  defp resolve_overrule_unanimity(state, agreed) do
    if MapSet.size(agreed) >= length(state.seats) do
      agree_overrule(state)
    else
      {:ok, state, []}
    end
  end

  defp agree_overrule(state) do
    previously_closed? = phase(state) == :closed

    %{
      proposer_id: proposer_id,
      pair: pair,
      closeness: couple_closeness
    } = state.overrule

    original_verdict = Map.fetch!(state.verdicts, pair)

    couple_reasoning = "Overruled jointly across all Seats. Recorded as precedent."
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

    bridges = for seat <- state.seats, seat.id in pair, do: state.bridges[seat.id]

    overrule_effect_data = %{
      attempt_number: state.attempt,
      proposer_seat_id: proposer_id,
      pair: pair,
      anchors: state.anchors,
      bridges: bridges,
      machine_closeness: original_verdict.closeness,
      machine_reasoning: original_verdict.reasoning,
      machine_quip: original_verdict.quip,
      couple_closeness: couple_closeness,
      couple_reasoning: couple_reasoning,
      couple_quip: couple_quip
    }

    overrules = state.overrules ++ [overrule_effect_data]
    new_verdicts = Map.put(state.verdicts, pair, new_verdict)
    state = %{state | verdicts: new_verdicts, overrule: nil, overrules: overrules}

    effects = [{:overrule, overrule_effect_data}]

    effects =
      if phase(state) == :closed and not previously_closed? do
        effects ++ [{:chronicle, chronicle(state)}]
      else
        effects
      end

    {:ok, state, effects}
  end

  # An attempt as the arc reads it, plus the verdicts behind it — which the
  # players are shown one at a time and the Chronicle keeps all of.
  defp chronicle_attempt(state, attempt) do
    verdicts = Enum.sort_by(attempt.verdicts, fn {pair, _verdict} -> pair end)

    state
    |> attempt_view(attempt)
    |> Map.put(:verdicts, Enum.map(verdicts, &chronicle_verdict(state, attempt.bridges, &1)))
  end

  # A verdict row says which word each Seat in the pair had in it, in the same
  # order as the Seats it names, so the row can be read without joining anything
  # back to it.
  defp chronicle_verdict(state, bridges, {pair, verdict}) do
    view = verdict_view(state, pair, verdict)

    Map.merge(view, %{bridges: Enum.map(view.seat_ids, &bridges[&1]), meta: verdict.meta})
  end

  defp seat_view(state, seat, viewer) do
    %{
      id: seat.id,
      name: seat.name,
      you?: seat.id == viewer,
      committed?: committed?(state, seat.id)
    }
  end

  defp taken_by_a_seat(state, seat_id) do
    if seated?(state, seat_id), do: :ok, else: {:error, :no_such_seat}
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

  # A Bridge is one word, and the game says it its own way: what the players are
  # shown side by side should differ in meaning, not in the shift key.
  defp normalize(bridge), do: bridge |> String.trim() |> String.downcase()

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

  defp seat(%{id: id, name: name}), do: %{id: id, name: name}

  defp seated?(state, seat_id), do: find_seat(state, seat_id) != nil
end
