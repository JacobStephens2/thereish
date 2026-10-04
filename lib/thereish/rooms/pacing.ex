defmodule Thereish.Rooms.Pacing do
  @moduledoc """
  The Room's rules about time: the Beat before a reveal, the hold after it,
  how long the Author and the Assayer are waited on, and when each part of a
  Page happened.

  It is a pure reducer in the shape of the Game. The Room tells it what
  happened and when, and gets back a new Pacing and a list of effects to
  perform. It reads no clock and no configuration: every call that depends on
  time is handed `now`, and the durations come in once, through `new/1`.

  It never stores the Page's Phase. The Room hands it the Game, and it reads
  the Phase through `Game.phase/1`, so the two cannot drift.

  ## Effects

    * `{:timer, name, token, ms}` — arm a timer that answers with
      `elapsed(pacing, name, token, now)` after `ms` milliseconds
    * `{:apply, events}` — apply these Game events, in order
    * `:broadcast` — what every screen says about the wait has changed

  ## When each part of a Page happened

  The Chronicle records when the Page opened, when each Give arrived, and when
  each Attempt started, went to the Assayer, was revealed and was advanced.
  Pacing writes each one down at the phase edge it names, in `moved/4`, and
  never writes the same one twice. `stamp/2` hands them to the closing Page's
  entry; new Gives and a turned Page forget them.

  A Page opens when it is on screen, not when the Room process booted. The
  difference is everyone typing their names, which is not the ten to fifteen
  minutes a Page is supposed to take, and it is this time the couch-night
  measurement reads.

  ## It owns time, and the rules do not

  The rules answer the last commit with two things owed: one assay carrying
  every Bridge, and a Beat. The Room performs both — a Task for the Assayer, a
  timer for the Beat — and Pacing holds the Verdict that comes back until the
  Beat is over. After the reveal is up, it holds advancement the same way: a
  shared deadline every screen reads, which a reconnect cannot restart and a
  second device cannot skip. That is the whole of the reveal's theatre, and it
  is why the Game itself can be driven in a test as a list of events with no
  clock in sight.

  A Verdict is never waited on inline. The Room stays answerable while the
  Assayer thinks, because a phone asking what it missed must not be stuck
  behind a model. An Assayer that raises or exits is a Verdict the Game does not
  have, which is a rule it already knows: the Attempt goes ungraded and the call
  goes to the players.

  ## An Assayer that is slow, rather than absent

  Design law 10 gives the reveal a ceiling: visible activity through four
  seconds, a provisional reading at eight, and at ten the game states it has no
  Verdict. Pacing runs that ladder, because it is made of time. Each step moves
  what every screen says; the last one is not a step but the end of the wait —
  the Verdict still outstanding is recorded as absent and the call goes to the
  couple, which is design law 3's joint authority arriving by the back door
  rather than an invented number. A Verdict that turns up after that is
  dropped: an Attempt is graded once (ADR-0010).

  The ladder is armed when the Assayer is asked and stood down when it answers,
  not when the reveal appears. Those differ by the Beat, and an Assayer that
  answered in 200 ms is not slow just because the theatre is still running.

  ## Stale timers

  Every timer Pacing arms carries a token, and Pacing keeps the token of each
  wait it is still running. A timer that fires after its wait ended — a rung
  whose Assayer answered in the same instant, a Beat from a Page that moved on
  — carries a token Pacing no longer holds, and changes nothing. So the Room
  never cancels a timer, and nothing depends on the order of its mailbox. That
  rule lives in `elapsed/4` and nowhere else.
  """

  alias Thereish.Chronicle.Timing
  alias Thereish.Game

  defstruct durations: nil,
            tokens: 0,
            beat: nil,
            held: [],
            assayer: nil,
            author: nil,
            hold: nil,
            opened_at: nil,
            times: %{gives: %{}, attempts: %{}}

  @typedoc "A moment, on the monotonic clock (`ms`) and the wall clock (`at`)."
  @type now :: %{ms: integer(), at: DateTime.t()}

  @typedoc """
  How long each wait lasts, in milliseconds. Each ladder's rungs count from the
  moment its wait began.
  """
  @type durations :: %{
          beat: non_neg_integer(),
          hold: non_neg_integer(),
          assayer: [slow: pos_integer(), unavailable: pos_integer()],
          author: [still_writing: pos_integer(), deadline: pos_integer()]
        }

  @attempt_times [:started_at, :assaying_started_at, :revealed_at, :advanced_at]

  @type name :: :beat | :assayer | :author | :hold
  @type token :: non_neg_integer()

  @type t :: %__MODULE__{
          durations: durations(),
          tokens: token(),
          beat: token() | nil,
          held: [Game.event()],
          assayer: %{step: :grading | :slow, token: token()} | nil,
          author: %{ref: reference(), step: :writing | :still_writing, token: token()} | nil,
          hold: %{revealed_ms: integer(), token: token() | nil} | nil,
          opened_at: DateTime.t() | nil,
          times: %{
            gives: %{String.t() => DateTime.t()},
            attempts: %{pos_integer() => %{atom() => DateTime.t()}}
          }
        }

  @typedoc """
  Something for the Room to do. Effects are descriptions: Pacing performs none
  of them.
  """
  @type effect ::
          {:timer, name(), token(), non_neg_integer()}
          | {:apply, [Game.event()]}
          | :broadcast

  @typedoc "What every screen is told about the Room's waits."
  @type view :: %{
          assayer_step: :grading | :slow | nil,
          author_step: :writing | :still_writing | nil,
          can_advance?: boolean()
        }

  @doc "A Pacing waiting on nothing, with these durations."
  @spec new(durations()) :: t()
  def new(durations), do: %__MODULE__{durations: durations}

  @doc """
  The Game moved from `old_game` to `new_game` at `now`. Leaving waiting opens
  the Page, and each phase edge records the time it names. A reveal, closing
  or not, arms the hold; leaving the reveal clears it.
  """
  @spec moved(t(), Game.t(), Game.t(), now()) :: {t(), [effect()]}
  def moved(%__MODULE__{} = pacing, old_game, new_game, now) do
    old_phase = Game.phase(old_game)
    new_phase = Game.phase(new_game)

    pacing =
      pacing
      |> opened(new_phase, now)
      |> record_times(old_game, new_game, old_phase, new_phase, now)

    cond do
      old_phase == :assaying and revealed?(new_phase) -> hold(pacing, now)
      revealed?(old_phase) and not revealed?(new_phase) -> {%{pacing | hold: nil}, []}
      true -> {pacing, []}
    end
  end

  @doc "The Game owes a Beat: Verdicts are held until it is over."
  @spec beat_owed(t(), now()) :: {t(), [effect()]}
  def beat_owed(%__MODULE__{} = pacing, _now) do
    {pacing, token} = mint(pacing)
    {%{pacing | beat: token, held: []}, [{:timer, :beat, token, pacing.durations.beat}]}
  end

  @doc "The Assayer was asked: its ladder starts at grading."
  @spec assayer_asked(t(), now()) :: {t(), [effect()]}
  def assayer_asked(%__MODULE__{} = pacing, _now), do: assayer_step(pacing, :grading)

  @doc """
  The Assayer answered with `event`. That stands its ladder down. The event is
  held while the Beat runs, applied at once after it, and dropped when no
  Assayer is being waited on.
  """
  @spec assayed(t(), Game.event()) :: {t(), [effect()]}
  def assayed(%__MODULE__{assayer: nil} = pacing, _event), do: {pacing, []}

  def assayed(%__MODULE__{beat: nil} = pacing, event) do
    {%{pacing | assayer: nil}, [{:apply, [event]}]}
  end

  def assayed(%__MODULE__{} = pacing, event) do
    {%{pacing | assayer: nil, held: pacing.held ++ [event]}, []}
  end

  @doc """
  The Author was asked to write, under `ref`. Any earlier Author wait is stood
  down and a fresh ladder starts at writing.
  """
  @spec author_asked(t(), reference(), now()) :: {t(), [effect()]}
  def author_asked(%__MODULE__{} = pacing, ref, _now), do: author_step(pacing, ref, :writing)

  @doc """
  The Author answered the request made under `ref`. `{:current, pacing}`, with
  the ladder stood down, when that is the request being waited on; `:stale`
  when it was superseded, timed out or never made.
  """
  @spec author_answered(t(), reference()) :: {:current, t()} | :stale
  def author_answered(%__MODULE__{author: %{ref: ref}} = pacing, ref) do
    {:current, %{pacing | author: nil}}
  end

  def author_answered(%__MODULE__{}, _ref), do: :stale

  @doc """
  The Gives were reset: the Author is no longer waited on, and the Page's
  opened time and occurrence times are forgotten.
  """
  @spec gives_reset(t()) :: t()
  def gives_reset(%__MODULE__{} = pacing), do: forget_page(pacing)

  @doc """
  The Page was turned: the Author is no longer waited on, and the closed
  Page's opened time and occurrence times are forgotten.
  """
  @spec page_turned(t()) :: t()
  def page_turned(%__MODULE__{} = pacing), do: forget_page(pacing)

  @doc """
  The closing Page's Chronicle `entry`, with when each part of it happened:
  each Give's `arrived_at`, each Attempt's `started_at`, `assaying_started_at`,
  `revealed_at` and `advanced_at`, and the entry's own `revealed_at` and
  `opened_at`. A time never recorded is `nil`.
  """
  @spec stamp(t(), map()) :: map()
  def stamp(%__MODULE__{times: times} = pacing, entry) do
    gives =
      Enum.map(entry[:gives] || [], fn give ->
        seat_id = give[:seat_id] || give["seat_id"]
        Map.put(give, :arrived_at, Map.get(times.gives, seat_id))
      end)

    attempts =
      Enum.map(entry.attempts, fn attempt ->
        recorded = Map.get(times.attempts, attempt.number, %{})

        Enum.reduce(@attempt_times, attempt, &Map.put(&2, &1, recorded[&1]))
      end)

    entry
    |> Map.put(:gives, gives)
    |> Map.put(:attempts, attempts)
    |> Map.put(:revealed_at, Timing.last_revealed(attempts))
    |> Map.put(:opened_at, pacing.opened_at)
  end

  @doc """
  A timer armed as `name` with `token` fired at `now`. A token Pacing no longer
  holds changes nothing.
  """
  @spec elapsed(t(), name(), token(), now()) :: {t(), [effect()]}
  def elapsed(%__MODULE__{beat: token} = pacing, :beat, token, _now) when token != nil do
    held = pacing.held
    pacing = %{pacing | beat: nil, held: []}

    if held == [], do: {pacing, []}, else: {pacing, [{:apply, held}]}
  end

  # Ten seconds is where the game stops waiting and says so. The Verdict is
  # recorded as absent, which the rules already answer by revealing without a
  # number and handing the ruling to the couple.
  def elapsed(%__MODULE__{assayer: %{token: token, step: :slow}} = pacing, :assayer, token, _now) do
    {%{pacing | assayer: nil}, [{:apply, [{:verdict_unavailable, %{}}]}]}
  end

  def elapsed(%__MODULE__{assayer: %{token: token, step: :grading}} = pacing, :assayer, token, _) do
    {pacing, effects} = assayer_step(pacing, :slow)
    {pacing, effects ++ [:broadcast]}
  end

  def elapsed(
        %__MODULE__{author: %{token: token, step: :still_writing}} = pacing,
        :author,
        token,
        _
      ) do
    {%{pacing | author: nil}, [{:apply, [{:author_failed, %{reason: "timed out"}}]}]}
  end

  def elapsed(
        %__MODULE__{author: %{token: token, step: :writing} = author} = pacing,
        :author,
        token,
        _
      ) do
    {pacing, effects} = author_step(pacing, author.ref, :still_writing)
    {pacing, effects ++ [:broadcast]}
  end

  # The deadline itself is the clock's to judge, in `may_advance/2`: this only
  # tells every screen to look again.
  def elapsed(%__MODULE__{hold: %{token: token} = hold} = pacing, :hold, token, _now)
      when token != nil do
    {%{pacing | hold: %{hold | token: nil}}, [:broadcast]}
  end

  def elapsed(%__MODULE__{} = pacing, _name, _token, _now), do: {pacing, []}

  @doc """
  Whether anyone may advance past the reveal at `now`: `:ok`, or
  `{:error, :reveal_held}` until the hold's deadline.
  """
  @spec may_advance(t(), now()) :: :ok | {:error, :reveal_held}
  def may_advance(%__MODULE__{hold: nil}, _now), do: :ok

  def may_advance(%__MODULE__{hold: hold} = pacing, now) do
    if now.ms - hold.revealed_ms >= pacing.durations.hold, do: :ok, else: {:error, :reveal_held}
  end

  @doc """
  What every screen is told about the waits in `game` at `now`. Nothing about
  the Assayer once it has answered: a Page still in its Beat is a Page whose
  grade is in.
  """
  @spec view(t(), Game.t(), now()) :: view()
  def view(%__MODULE__{} = pacing, game, now) do
    %{
      assayer_step: pacing.assayer && pacing.assayer.step,
      author_step: pacing.author && pacing.author.step,
      can_advance?: revealed?(Game.phase(game)) and may_advance(pacing, now) == :ok
    }
  end

  defp revealed?(phase), do: phase in [:reveal, :closed]

  defp forget_page(pacing) do
    %{pacing | author: nil, opened_at: nil, times: %{gives: %{}, attempts: %{}}}
  end

  defp opened(%{opened_at: nil} = pacing, phase, now) when phase != :waiting do
    %{pacing | opened_at: now.at}
  end

  defp opened(pacing, _phase, _now), do: pacing

  # Each edge names the times it records. A Give is recorded when its Seat
  # first appears among the Gives; coming back to giving from elsewhere starts
  # the Gives' times over.
  defp record_times(pacing, old_game, new_game, old_phase, new_phase, now) do
    times = pacing.times

    gives =
      if old_phase != :giving and new_phase == :giving, do: %{}, else: times.gives

    gives =
      (Map.keys(new_game.gives) -- Map.keys(old_game.gives))
      |> Enum.reduce(gives, &Map.put_new(&2, &1, now.at))

    attempts =
      case {old_phase, new_phase} do
        {:bridging, :assaying} ->
          put_attempt(times.attempts, new_game.attempt, :assaying_started_at, now)

        {:assaying, phase} when phase in [:reveal, :closed] ->
          put_attempt(times.attempts, new_game.attempt, :revealed_at, now)

        {:reveal, :bridging} ->
          times.attempts
          |> put_attempt(old_game.attempt, :advanced_at, now)
          |> put_attempt(new_game.attempt, :started_at, now)

        {:writing, :bridging} ->
          put_attempt(times.attempts, new_game.attempt, :started_at, now)

        _edge ->
          times.attempts
      end

    %{pacing | times: %{gives: gives, attempts: attempts}}
  end

  defp put_attempt(attempts, number, field, now) do
    Map.update(attempts, number, %{field => now.at}, &Map.put_new(&1, field, now.at))
  end

  # A hold of zero is no hold worth a timer, but the reveal's moment is still
  # kept, so `may_advance/2` judges it the same way either way.
  defp hold(pacing, now) do
    case pacing.durations.hold do
      ms when is_integer(ms) and ms > 0 ->
        {pacing, token} = mint(pacing)
        {%{pacing | hold: %{revealed_ms: now.ms, token: token}}, [{:timer, :hold, token, ms}]}

      _ms ->
        {%{pacing | hold: %{revealed_ms: now.ms, token: nil}}, []}
    end
  end

  defp assayer_step(pacing, step) do
    {pacing, token} = mint(pacing)
    pacing = %{pacing | assayer: %{step: step, token: token}}

    {pacing, [{:timer, :assayer, token, rung_ms(pacing.durations, step)}]}
  end

  defp author_step(pacing, ref, step) do
    {pacing, token} = mint(pacing)
    pacing = %{pacing | author: %{ref: ref, step: step, token: token}}

    {pacing, [{:timer, :author, token, rung_ms(pacing.durations, step)}]}
  end

  # How long a ladder stands on `step` before its next rung. Rungs count from
  # the start of the wait, so after the first this is the gap between two.
  defp rung_ms(%{assayer: rungs}, :grading), do: rungs[:slow]
  defp rung_ms(%{assayer: rungs}, :slow), do: rungs[:unavailable] - rungs[:slow]
  defp rung_ms(%{author: rungs}, :writing), do: rungs[:still_writing]
  defp rung_ms(%{author: rungs}, :still_writing), do: rungs[:deadline] - rungs[:still_writing]

  defp mint(pacing), do: {%{pacing | tokens: pacing.tokens + 1}, pacing.tokens}
end
