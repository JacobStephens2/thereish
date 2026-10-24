defmodule Thereish.Rooms.Play do
  @moduledoc """
  The Room's play in memory: the Game together with Pacing, Pages, Occupancy,
  Voice and Room facts, and every rule about how those six are told things.

  The Room's process hands it each command it receives, a tap from a phone,
  a timer or a result from the Steward, with the moment it was received, and
  gets back the new Play and one flat list of effects to perform in order. It
  touches no database, process, PubSub or Steward, and reads no clock: `now`
  is the `%{ms, at}` map Pacing already takes. Its one impurity is the one
  Pages already has: it mints fresh refs for the Author and for a Page.

  Refusals answer `{:error, reason}` and change nothing: the Game's reasons,
  `:reveal_held` from Pacing, `:refused` from Occupancy and
  `:bad_music_setting` from Facts. A result that arrives late or stale is not
  a refusal: it answers `{:ok, play, []}`.

  ## The orderings

    * A turned Page is passed to Voice first, so a Chronicle write Voice was
      holding is released, then to Pacing, Pages and Occupancy, then the
      Game's move is taken. The write lands after the turn has been decided,
      so the Pages of the turned Page are kept until it does: its
      `{:chronicle_written, page_id}` still binds that Page and releases what
      was held for it.
    * A reset of Gives reaches Pacing, Occupancy and Pages only once the Game
      accepts it, so a late tap after the Author has written the Page leaves
      that Page's music and times alone.
    * The Entry closing a Page carries Occupancy's music for the Room's music
      setting, the Page's Assignment and Pacing's times. Pages then holds
      results for it, and Voice decides whether it is written now or once the
      Verdict has been spoken.

  ## Broadcasts

  Every point at which a screen hears `:room_changed` is a `:broadcast`
  effect, emitted where the Room broadcast before Play existed and not
  deduplicated: after every move of the Game, when Pacing asks, when a Foley
  result changes what the Room shows or lands on a Page, when a Room fact
  changes (before the fact's own effects), when a Mask for past Gives is
  written, and after a Speaker press.

  ## Asks answered by a follow-up command

  Three effects need Postgres to answer, and the answer changes the Play. The
  Room's process performs each, then at once runs the follow-up command it
  names and performs that command's effects, before the rest of the list:

    * `{:open_page, request, assignment_or_nil}`: the Room makes an
      Assignment when this is nil, reads the Track cache for the request's
      Gives, and runs `{:page_opened, request, assignment, cached_track}`
    * `{:look_up_track, page_ref, gives}`: runs
      `{:track_looked_up, page_ref, cached_track}`
    * `{:write_chronicle, entry}`: runs `{:chronicle_written, page_id}`, or
      nothing when the write failed

  ## Guard writes

  `{:insert_seat, id, name}` and `{:persist_room, attrs}` are always the
  first effect when present. The Room performs that write before it adopts
  the new Play, and keeps the old one if the write fails.

  ## Effects

    * `:broadcast` and `{:broadcast, message}`
    * `{:insert_seat, id, name}` and `{:persist_room, attrs}`
    * `{:timer, name, token, ms}`: answer with `{:pacing, name, token}`
    * `{:open_page, request, assignment_or_nil}`
    * `{:ask_author, ref, request, arm}`, the Arm being the Author's job:
      answer with
      `{:author_completed, ref, result}`
    * `{:ask_assayer, request}`: answer with `{:assayed, event}`
    * `{:draw_mask, seat_id, giving_ref, give, colour}`: answer with
      `{:mask_landed, seat_id, giving_ref, mask_or_dot}`
    * `{:speak, attempt, kind, line}`: answer with
      `{:voice_spoken, attempt, kind, result}`
    * `{:start_vamp, ...}`, `{:enqueue_track, ...}`, `{:start_title, ...}`,
      `{:look_up_track, ...}`, `{:cache_track, ...}`, `{:record_never, path}`
      and `{:log, page_ref, event, gives_landed_at}`, as Occupancy names them
    * `{:log, level, message}`, as Voice names it
    * `{:write_chronicle, entry}` and `{:write_page, page_id, write}`
    * `{:record_overrule, overrule}` and `{:record_fairness_tap, data}`
  """

  import Kernel, except: [apply: 3]

  alias Thereish.Chronicle.Entry
  alias Thereish.Foley.Occupancy
  alias Thereish.Foley.Repertoire
  alias Thereish.Foley.Voice
  alias Thereish.Game
  alias Thereish.Mask
  alias Thereish.Rooms.Facts
  alias Thereish.Rooms.Pacing
  alias Thereish.Rooms.Pages
  alias Thereish.Rooms.Room

  # `pages_before_turn` is Pages as it stood before a turn that released the
  # Chronicle write, kept until that write's Page id comes back.
  defstruct [:game, :pacing, :pages, :occupancy, :voice, :facts, :pages_before_turn]

  @type t :: %__MODULE__{
          game: Game.t(),
          pacing: Pacing.t(),
          pages: Pages.t(),
          occupancy: Occupancy.t(),
          voice: Voice.t(),
          facts: Facts.t(),
          pages_before_turn: Pages.t() | nil
        }

  @type seat_id :: String.t()
  @type device_token :: String.t() | nil

  @type command ::
          {:seat_joined, seat_id(), String.t()}
          | {:give, seat_id(), String.t()}
          | {:start_page, seat_id()}
          | {:retry_author, seat_id()}
          | {:reset_gives, seat_id()}
          | {:commit_bridge, seat_id(), String.t()}
          | {:nudge, seat_id(), String.t()}
          | {:call, seat_id(), atom()}
          | {:react, seat_id(), atom()}
          | {:next_attempt, seat_id()}
          | {:next_page, seat_id(), [Repertoire.member()]}
          | {:propose_overrule, seat_id(), keyword() | map()}
          | {:agree_overrule, seat_id()}
          | {:decline_overrule, seat_id()}
          | {:record_fairness_tap, seat_id(), String.t()}
          | {:tap_bookends, seat_id(), String.t()}
          | {:room_fact, Facts.command()}
          | {:next, device_token()}
          | {:never, device_token()}
          | {:author_completed, reference(), {:ok, map()} | {:error, String.t()}}
          | {:assayed, Game.event()}
          | {:pacing, Pacing.name(), Pacing.token()}
          | {:voice_spoken, integer(), Voice.kind(), {:ok, map()} | {:error, map()}}
          | {:vamped | :scored | :titled, reference(), {:ok, map()} | {:error, term()}}
          | {:mask_landed, seat_id(), reference(), Mask.t() | :dot}
          | {:page_opened, map(), atom(), map() | nil}
          | {:track_looked_up, reference(), map() | nil}
          | {:chronicle_written, Ecto.UUID.t()}

  @typedoc "Something for the Room's process to do, in order. Play performs none of them."
  @type effect ::
          :broadcast
          | {:broadcast, {:bookends_ready | :voice_ready, integer()}}
          | {:insert_seat, seat_id(), String.t()}
          | {:persist_room, map()}
          | {:timer, Pacing.name(), Pacing.token(), non_neg_integer()}
          | {:open_page, map(), atom() | nil}
          | {:ask_author, reference(), map(), atom()}
          | {:ask_assayer, map()}
          | {:draw_mask, seat_id(), reference(), String.t(), String.t()}
          | {:speak, integer(), Voice.kind(), String.t()}
          | {:start_vamp, reference(), [String.t()]}
          | {:enqueue_track, reference(), [String.t()], integer()}
          | {:start_title, reference(), [String.t()]}
          | {:look_up_track, reference(), [String.t()]}
          | {:cache_track, [String.t()], map()}
          | {:record_never, String.t()}
          | {:log, reference(), String.t() | {atom(), term()}, integer() | nil}
          | {:log, Logger.level(), String.t()}
          | {:write_chronicle, Entry.t()}
          | {:write_page, Ecto.UUID.t(), term()}
          | {:record_overrule, map()}
          | {:record_fairness_tap, map()}

  @doc """
  The Play of a Room with these Seats, built from the Room's row, the
  Repertoire's eligible `members` and Pacing's `durations`. Pacing has
  already been told the Room starts at its Game, so a Room that comes back
  with every Seat taken is a Page already open.
  """
  @spec new(%{room: Room.t(), seats: [Game.seat()]}, %{
          members: [Repertoire.member()],
          durations: Pacing.durations(),
          now: Pacing.now()
        }) :: t()
  def new(%{room: %Room{} = room, seats: seats}, %{members: members, durations: durations} = opts) do
    game = Game.init(seat_limit: room.seat_limit, seats: seats, full_table: room.full_table)

    # Moving from a Game to itself crosses no phase edge, so asks for nothing.
    {pacing, []} = Pacing.moved(Pacing.new(durations), game, game, opts.now)

    %__MODULE__{
      game: game,
      pacing: pacing,
      pages: Pages.new(),
      occupancy: Occupancy.new(members),
      voice: Voice.new(),
      facts: Facts.new(room)
    }
  end

  @doc """
  Runs one command received at `now`. Answers the new Play and the effects to
  perform in order, or the reason it was refused.
  """
  @spec apply(t(), command(), Pacing.now()) :: {:ok, t(), [effect()]} | {:error, term()}
  def apply(play, command, now)

  # -- Seats --------------------------------------------------------------

  # The rules decide before Postgres hears anything, so a full Room costs no
  # write.
  def apply(%__MODULE__{} = play, {:seat_joined, id, name}, now) do
    with {:ok, play, effects} <- move(play, {:seat_joined, %{id: id, name: name}}, now) do
      {:ok, play, [{:insert_seat, id, name} | effects]}
    end
  end

  # -- Game commands --------------------------------------------------------

  def apply(%__MODULE__{} = play, {:give, seat_id, give}, now) do
    with {:ok, play, effects} <-
           move(play, {:give_committed, %{seat_id: seat_id, give: give}}, now) do
      colour = Game.seat_colour(play.game, seat_id)
      {:ok, play, effects ++ [{:draw_mask, seat_id, Pages.giving(play.pages), give, colour}]}
    end
  end

  def apply(%__MODULE__{} = play, {:start_page, seat_id}, now),
    do: move(play, {:start_page, %{seat_id: seat_id}}, now)

  def apply(%__MODULE__{} = play, {:retry_author, seat_id}, now),
    do: move(play, {:author_retried, %{seat_id: seat_id}}, now)

  def apply(%__MODULE__{} = play, {:commit_bridge, seat_id, bridge}, now),
    do: move(play, {:bridge_committed, %{seat_id: seat_id, bridge: bridge}}, now)

  def apply(%__MODULE__{} = play, {:nudge, seat_id, word}, now),
    do: move(play, {:nudge_sent, %{seat_id: seat_id, word: word}}, now)

  def apply(%__MODULE__{} = play, {:call, seat_id, band}, now),
    do: move(play, {:call_made, %{seat_id: seat_id, band: band}}, now)

  def apply(%__MODULE__{} = play, {:react, seat_id, reaction}, now),
    do: move(play, {:reacted, %{seat_id: seat_id, reaction: reaction}}, now)

  def apply(%__MODULE__{} = play, {:propose_overrule, seat_id, opts}, now),
    do: move(play, {:overrule_proposed, opts |> Map.new() |> Map.put(:seat_id, seat_id)}, now)

  def apply(%__MODULE__{} = play, {:agree_overrule, seat_id}, now),
    do: move(play, {:overrule_agreed, %{seat_id: seat_id}}, now)

  def apply(%__MODULE__{} = play, {:decline_overrule, seat_id}, now),
    do: move(play, {:overrule_declined, %{seat_id: seat_id}}, now)

  def apply(%__MODULE__{} = play, {:record_fairness_tap, seat_id, label}, now),
    do: move(play, {:fairness_tapped, %{seat_id: seat_id, label: label}}, now)

  def apply(%__MODULE__{} = play, {:tap_bookends, seat_id, label}, now),
    do: move(play, {:bookends_tapped, %{seat_id: seat_id, label: label}}, now)

  def apply(%__MODULE__{} = play, {:next_attempt, seat_id}, now) do
    with :ok <- Pacing.may_advance(play.pacing, now) do
      move(play, {:attempt_advanced, %{seat_id: seat_id}}, now)
    end
  end

  # Nothing is reset until the Game accepts it: a late tap from a second
  # phone, after the Author has already written the Page, must leave that
  # Page's music and times alone.
  def apply(%__MODULE__{} = play, {:reset_gives, seat_id}, now) do
    with {:ok, game, effects} <- Game.apply(play.game, {:gives_reset, %{seat_id: seat_id}}) do
      play = %{
        play
        | pacing: Pacing.gives_reset(play.pacing),
          occupancy: Occupancy.gives_reset(play.occupancy),
          pages: Pages.gives_reset(play.pages)
      }

      {play, effects} = advance(play, game, effects, now)
      {:ok, play, effects}
    end
  end

  # A closed Page must not vanish if Foley is still speaking when the Seats
  # tap next: Voice releases whatever Page it is holding before Pacing, Pages
  # and Occupancy forget the Page in play. That write lands after this
  # command, so the Pages it closed with are kept for its
  # `{:chronicle_written, page_id}`.
  def apply(%__MODULE__{} = play, {:next_page, seat_id, members}, now) do
    with :ok <- Pacing.may_advance(play.pacing, now),
         {:ok, game, effects} <- Game.apply(play.game, {:next_page, %{seat_id: seat_id}}) do
      {play, released} = voice(play, &Voice.page_turned/1)
      writes? = Enum.any?(released, &match?({:write_chronicle, _entry}, &1))

      play = %{
        play
        | pacing: Pacing.page_turned(play.pacing),
          pages: Pages.page_turned(play.pages),
          occupancy: Occupancy.page_turned(play.occupancy, members),
          pages_before_turn: if(writes?, do: play.pages)
      }

      {play, moved} = advance(play, game, effects, now)
      {:ok, play, released ++ moved}
    end
  end

  # -- Room facts and the Speaker -----------------------------------------

  # The write comes first, so a failed write leaves the Room as it was, and
  # the broadcast before the fact's effects, so a screen hears :room_changed
  # before any Voice message a Speaker claim releases.
  def apply(%__MODULE__{} = play, {:room_fact, command}, _now) do
    with {:ok, facts, attrs, fact_effects} <- Facts.apply(play.facts, command) do
      persist = if attrs == %{}, do: [], else: [{:persist_room, attrs}]
      broadcast = if facts != play.facts, do: [:broadcast], else: []

      {play, effects} = each(%{play | facts: facts}, fact_effects, &fact_changed/2)

      {:ok, play, persist ++ broadcast ++ effects}
    end
  end

  def apply(%__MODULE__{} = play, {:next, device_token}, _now),
    do: speaker_pressed(play, device_token, &Occupancy.next/2)

  def apply(%__MODULE__{} = play, {:never, device_token}, _now),
    do: speaker_pressed(play, device_token, &Occupancy.never/2)

  # -- what the Room hears --------------------------------------------------

  # A superseded, timed-out or duplicate Author changes nothing.
  def apply(%__MODULE__{} = play, {:author_completed, ref, result}, now) do
    case Pacing.author_answered(play.pacing, ref) do
      {:current, pacing} ->
        {play, effects} =
          apply_events(%{play | pacing: pacing}, [author_event(play, result)], now)

        {:ok, play, effects}

      :stale ->
        {:ok, play, []}
    end
  end

  # Pacing decides whether the Verdict is held for the Beat, applied or
  # dropped; Voice hears it as it arrives, so its line is ready by the reveal.
  def apply(%__MODULE__{} = play, {:assayed, event}, now) do
    {play, heard} = verdict_heard(play, event)
    {play, paced} = pace(play, &Pacing.assayed(&1, event), now)
    {:ok, play, heard ++ paced}
  end

  def apply(%__MODULE__{} = play, {:pacing, name, token}, now) do
    {play, effects} = pace(play, &Pacing.elapsed(&1, name, token, now), now)
    {:ok, play, effects}
  end

  def apply(%__MODULE__{} = play, {:voice_spoken, attempt, kind, result}, _now) do
    {play, effects} = voice(play, &Voice.spoken(&1, attempt, kind, result, voice_table(play)))
    {:ok, play, effects}
  end

  # Every Foley result goes to Occupancy, which decides whether it still
  # belongs to the Page in play.
  def apply(%__MODULE__{} = play, {tag, page_ref, result}, _now)
      when tag in [:vamped, :scored, :titled] do
    kind = %{vamped: :vamp, scored: :track, titled: :title}[tag]
    closed? = closed?(play)
    {play, effects} = occupy(play, &Occupancy.arrived(&1, page_ref, {kind, result}, closed?))
    {:ok, play, effects}
  end

  # A Mask for the Gives in play is the Game's to accept, whatever it is. One
  # for Gives already past only adds something if it was drawn: the dot is
  # never stored as a picture. Either way, Pages decides which Chronicle Page
  # it lands on.
  def apply(%__MODULE__{} = play, {:mask_landed, seat_id, giving_ref, mask}, now) do
    cond do
      giving_ref == Pages.giving(play.pages) ->
        case move(play, {:mask_landed, %{seat_id: seat_id, mask: mask}}, now) do
          {:ok, play, moved} ->
            {play, written} = write_page(play, giving_ref, {:mask, seat_id, mask})
            {:ok, play, moved ++ written}

          {:error, _reason} ->
            {:ok, play, []}
        end

      match?(%Mask{}, mask) ->
        case write_page(play, giving_ref, {:mask, seat_id, mask}) do
          {play, []} -> {:ok, play, []}
          {play, written} -> {:ok, play, written ++ [:broadcast]}
        end

      true ->
        {:ok, play, []}
    end
  end

  # -- follow-ups -------------------------------------------------------------

  # The Author is asked under a fresh ref, and Occupancy's Foley under a fresh
  # Page ref, so a retry's answers never land on the request it replaced.
  def apply(%__MODULE__{} = play, {:page_opened, request, assignment, cached}, now) do
    ref = make_ref()
    page_ref = make_ref()
    gives = Enum.map(request.gives, & &1.text)
    music = play.facts.music

    play = %{play | pages: Pages.page_opened(play.pages, page_ref, assignment)}
    {play, paced} = pace(play, &Pacing.author_asked(&1, ref, now), now)

    {play, occupied} =
      occupy_quietly(play, &Occupancy.page_opened(&1, page_ref, gives, cached, now.ms, music))

    {:ok, play, paced ++ [{:ask_author, ref, request, assignment.arm}] ++ occupied}
  end

  def apply(%__MODULE__{} = play, {:track_looked_up, page_ref, cached}, _now) do
    {play, effects} = occupy_quietly(play, &Occupancy.track_looked_up(&1, page_ref, cached))
    {:ok, play, effects}
  end

  # The outcome is in, so a tap released here finds it.
  def apply(%__MODULE__{pages_before_turn: nil} = play, {:chronicle_written, page_id}, _now) do
    {pages, writes} = Pages.written(play.pages, page_id)
    {:ok, %{play | pages: pages}, page_writes(writes)}
  end

  # The write a turn released answers here, before any other command, so
  # nothing has told Pages anything since the turn: the turned Page's Pages is
  # bound to its Chronicle Page and turned again, which is the whole of what
  # the turn did to Pages.
  def apply(%__MODULE__{pages_before_turn: turned} = play, {:chronicle_written, page_id}, _now) do
    {pages, writes} = Pages.written(turned, page_id)
    {:ok, %{play | pages: Pages.page_turned(pages), pages_before_turn: nil}, page_writes(writes)}
  end

  # -- reads ------------------------------------------------------------------

  @doc """
  What `viewer` (a Seat id, or nil) sees on the device holding
  `device_token` at `now`: the Game's view, Pacing's waits, the Room facts,
  what the Speaker is playing, and whether the Room has a Chronicle.
  """
  @spec view(t(), seat_id() | nil, device_token(), %{
          now: Pacing.now(),
          has_chronicle?: boolean()
        }) :: map()
  def view(%__MODULE__{} = play, viewer, device_token, %{now: now, has_chronicle?: chronicle?}) do
    play.game
    |> Game.view(viewer)
    |> Map.merge(Pacing.view(play.pacing, play.game, now))
    |> Map.merge(Facts.view(play.facts, device_token))
    |> Map.merge(Occupancy.view(play.occupancy, table(play)))
    |> Map.put(:has_chronicle?, chronicle?)
  end

  @doc "Voice's clip of `kind` for `attempt`, which must be the Attempt in play."
  @spec clip(t(), integer(), Voice.kind() | String.t()) ::
          {:ok, binary(), atom() | String.t()} | {:error, :not_found}
  def clip(%__MODULE__{} = play, attempt, kind),
    do: Voice.clip(play.voice, attempt, kind, voice_table(play))

  @doc "Whether a Page is being played: bridging, assaying or revealed."
  @spec in_play?(t()) :: boolean()
  def in_play?(%__MODULE__{} = play), do: Game.phase(play.game) in [:bridging, :assaying, :reveal]

  # Runs `fun` over `items` in order, threading the Play through, and answers
  # the effects of every step, in order.
  defp each(play, items, fun) do
    {effects, play} =
      Enum.flat_map_reduce(items, play, fn item, play ->
        {play, effects} = fun.(play, item)
        {effects, play}
      end)

    {play, effects}
  end

  # -- the Game ---------------------------------------------------------------

  defp move(play, event, now) do
    with {:ok, game, effects} <- Game.apply(play.game, event) do
      {play, effects} = advance(play, game, effects, now)
      {:ok, play, effects}
    end
  end

  # A Verdict for a Page that has moved on is nothing to act on and nothing
  # to crash over.
  defp apply_events(play, events, now) do
    each(play, events, fn play, event ->
      case Game.apply(play.game, event) do
        {:ok, game, effects} -> advance(play, game, effects, now)
        {:error, _reason} -> {play, []}
      end
    end)
  end

  defp advance(play, game, game_effects, now) do
    old_game = play.game
    {play, paced} = pace(%{play | game: game}, &Pacing.moved(&1, old_game, game, now), now)

    {play, performed} = each(play, game_effects, &game_effect(&1, &2, now))

    {play, voiced} = voice(play, &Voice.table_moved(&1, voice_table(play)))

    {play, paced ++ performed ++ voiced ++ [:broadcast]}
  end

  defp game_effect(play, :beat, now), do: pace(play, &Pacing.beat_owed(&1, now), now)

  # The Entry takes the Page's Assignment here, at the close, so a held write
  # still records the Assignment the Page was played under. Voice decides
  # whether the write waits for the closing Verdict's speech: ADR-0003 forbids
  # updating the Verdict row afterwards.
  defp game_effect(play, {:chronicle, %Entry{} = entry}, _now) do
    entry =
      entry
      |> struct!(Occupancy.chronicle_meta(play.occupancy, play.facts.music))
      |> struct!(assignment: Pages.assignment(play.pages))
      |> then(&Pacing.stamp(play.pacing, &1))

    play = %{play | pages: Pages.page_closed(play.pages), pages_before_turn: nil}
    voice(play, &Voice.page_closed(&1, entry))
  end

  defp game_effect(play, {:overrule, overrule}, _now), do: {play, [{:record_overrule, overrule}]}

  defp game_effect(play, {:fairness_tap, data}, _now),
    do: {play, [{:record_fairness_tap, data}]}

  # A tap is made on a closed Page, so it belongs to the Page in play, which
  # Voice may not have let into the Chronicle yet, and is recorded under that
  # Page's Assignment.
  defp game_effect(play, {:bookends_tap, data}, _now) do
    data = Map.put(data, :assignment, Pages.assignment(play.pages))
    write_page(play, Pages.giving(play.pages), {:bookends_tap, data})
  end

  defp game_effect(play, {:author, request}, _now),
    do: {play, [{:open_page, request, Pages.assignment(play.pages)}]}

  defp game_effect(play, {:assay, request}, now) do
    {play, paced} = pace(play, &Pacing.assayer_asked(&1, now), now)
    {play, [{:ask_assayer, request} | paced]}
  end

  defp author_event(play, {:ok, result}) do
    {:page_written,
     %{
       bookends: result.bookends,
       from: result[:from],
       meta: result.meta,
       full_table: play.facts.full_table
     }}
  end

  defp author_event(_play, {:error, reason}), do: {:author_failed, %{reason: reason}}

  # -- Pacing -----------------------------------------------------------------

  # A timer is never cancelled: one that fires late carries a token Pacing
  # ignores.
  defp pace(play, transition, now) do
    {pacing, effects} = transition.(play.pacing)

    each(%{play | pacing: pacing}, effects, fn
      play, {:apply, events} -> apply_events(play, events, now)
      play, effect -> {play, [effect]}
    end)
  end

  # -- Room facts -------------------------------------------------------------

  defp fact_changed(play, :speaker_claimed),
    do: voice(play, &Voice.speaker_claimed(&1, voice_table(play)))

  defp fact_changed(play, {:music_changed, music}),
    do: occupy_quietly(play, &Occupancy.music_changed(&1, music))

  defp fact_changed(play, {:full_table_changed, enabled}),
    do: {%{play | game: Game.set_full_table(play.game, enabled)}, []}

  # Next or Never, which only the device holding the Speaker may press. Any
  # other device's press is ignored rather than refused.
  defp speaker_pressed(play, device_token, press) do
    if Facts.holds_speaker?(play.facts, device_token) do
      with {:ok, occupancy, effects} <- press.(play.occupancy, table(play)) do
        {play, effects, _wrote?} = occupancy_effects(play, occupancy, effects)
        {:ok, play, effects ++ [:broadcast]}
      end
    else
      {:ok, play, []}
    end
  end

  # -- Occupancy ----------------------------------------------------------------

  # Broadcasts when what the Room shows has changed or a Page was written.
  defp occupy(play, transition) do
    before = Occupancy.view(play.occupancy, table(play))
    {occupancy, effects} = transition.(play.occupancy)
    {play, effects, wrote?} = occupancy_effects(play, occupancy, effects)

    if wrote? or Occupancy.view(play.occupancy, table(play)) != before do
      {play, effects ++ [:broadcast]}
    else
      {play, effects}
    end
  end

  # As `occupy/2`, where the caller broadcasts on its own.
  defp occupy_quietly(play, transition) do
    {occupancy, effects} = transition.(play.occupancy)
    {play, effects, _wrote?} = occupancy_effects(play, occupancy, effects)
    {play, effects}
  end

  # Occupancy's metadata goes onto a Page through Pages; every other effect
  # is the Room's to perform. Answers whether a Page was written.
  defp occupancy_effects(play, occupancy, effects) do
    {play, effects} =
      each(%{play | occupancy: occupancy}, effects, fn
        play, {:persist_vamp_meta, page_ref, meta} -> write_page(play, page_ref, {:vamp, meta})
        play, {:persist_music_meta, page_ref, meta} -> write_page(play, page_ref, {:music, meta})
        play, effect -> {play, [effect]}
      end)

    {play, effects, Enum.any?(effects, &match?({:write_page, _id, _write}, &1))}
  end

  # The Room's facts Occupancy is told on each call rather than keeping a copy.
  defp table(play), do: %{music: play.facts.music, closed?: closed?(play)}

  defp closed?(play), do: Game.phase(play.game) == :closed

  # -- Pages --------------------------------------------------------------------

  defp write_page(play, ref, write) do
    {pages, writes} = Pages.write(play.pages, ref, write)
    {%{play | pages: pages}, page_writes(writes)}
  end

  defp page_writes(writes),
    do: Enum.map(writes, fn {:write, id, write} -> {:write_page, id, write} end)

  # -- Voice --------------------------------------------------------------------

  defp verdict_heard(play, {:verdict_received, verdict}),
    do: voice(play, &Voice.verdict_received(&1, verdict, voice_table(play)))

  defp verdict_heard(play, _event), do: {play, []}

  # A held Chronicle write lands before the voice_ready that follows it.
  defp voice(play, transition) do
    {voice, effects} = transition.(play.voice)

    effects =
      Enum.map(effects, fn
        {:commit_chronicle, entry} -> {:write_chronicle, entry}
        effect -> effect
      end)

    {%{play | voice: voice}, effects}
  end

  # The Room's and the Game's facts Voice is told on each call.
  defp voice_table(play) do
    %{
      attempt: Game.attempt_number(play.game),
      phase: Game.phase(play.game),
      bookends: Game.attempt_bookends(play.game),
      speaker?: Facts.speaker_claimed?(play.facts),
      quips?: play.facts.quips == true
    }
  end
end
