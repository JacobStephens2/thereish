defmodule Thereish.Foley.Voice do
  @moduledoc """
  Foley announcing an Attempt's Bookends, and the Verdict at the reveal.

  It is a pure reducer in the shape of Occupancy. The Room tells it what
  happened (the table moved, the Speaker was claimed, a Verdict arrived, a
  line was spoken, a Page closed, the Page turned) and gets back a new Voice
  and a list of effects to carry out. It does no I/O and sends no messages.

  It never stores what the Room or the Game already knows. The current attempt
  number, the Phase, the Bookends, whether a Speaker is held and the quips
  setting come in as a `table` on each call that needs them, so none of them
  can drift.

  ## Effects

    * `{:speak, attempt, kind, line}`: answer with `spoken/5`
    * `{:broadcast, {:bookends_ready, attempt}}`
    * `{:broadcast, {:voice_ready, attempt}}`
    * `{:commit_chronicle, entry}`: the Entry already carries its voice
      metadata
    * `{:log, level, message}`

  ## Stale clips

  Clips belong to the Attempt Voice is tracking. When the table's attempt
  moves on, the clips and any Bookends still being spoken are forgotten
  together, and a clip that arrives for an earlier Attempt is dropped and
  logged. That rule lives in `track/2` and nowhere else.

  ## The Chronicle hold

  ADR-0003 writes a Verdict row once. A closed Page whose Verdict is still
  being spoken is held until that Verdict's voice metadata lands, success or
  failure, and is committed before `voice_ready` goes out, so a screen that
  reads the Page on `voice_ready` finds it. Turning the Page releases whatever
  is held, so a Page cannot vanish.
  """

  alias Thereish.Chronicle.Entry
  alias Thereish.Ladder

  defstruct attempt: nil,
            clips: %{},
            speaking: %{bookends: nil, verdict: nil},
            voice_meta: %{},
            held_page: nil

  @type kind :: :bookends | :verdict
  @type clip :: %{audio: binary(), format: atom() | String.t()}

  @type t :: %__MODULE__{
          attempt: integer() | nil,
          clips: %{optional(kind()) => clip()},
          speaking: %{bookends: integer() | nil, verdict: integer() | nil},
          voice_meta: %{optional(integer()) => map()},
          held_page: Entry.t() | nil
        }

  @typedoc """
  Something for the Room to do. Effects are descriptions: Voice performs none
  of them.
  """
  @type effect ::
          {:speak, integer(), kind(), String.t()}
          | {:broadcast, {:bookends_ready | :voice_ready, integer()}}
          | {:commit_chronicle, Entry.t()}
          | {:log, Logger.level(), String.t()}

  @typedoc "The Room's and the Game's facts for this call."
  @type table :: %{
          attempt: integer(),
          phase: atom(),
          bookends: [String.t()] | nil,
          speaker?: boolean(),
          quips?: boolean()
        }

  @doc "A Voice holding nothing."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  The table moved: the Game advanced. A new Attempt forgets the last one's
  clips and any Bookends still being spoken for it. The Bookends are spoken
  when a Speaker is held, the Phase is bridging, there are Bookends, and this
  Attempt has neither a Bookends clip nor one on the way.
  """
  @spec table_moved(t(), table()) :: {t(), [effect()]}
  def table_moved(%__MODULE__{} = voice, table) do
    voice = track(voice, table.attempt)

    if speak_bookends?(voice, table) do
      speak(voice, table.attempt, :bookends, Enum.join(table.bookends, ". "))
    else
      {voice, []}
    end
  end

  @doc """
  A device claimed the Speaker. Clips already held for this Attempt are
  offered to it, then the table-moved rule runs.
  """
  @spec speaker_claimed(t(), table()) :: {t(), [effect()]}
  def speaker_claimed(%__MODULE__{} = voice, table) do
    voice = track(voice, table.attempt)
    offers = offers(voice, table)
    {voice, effects} = table_moved(voice, table)
    {voice, offers ++ effects}
  end

  @doc """
  The Assayer's Verdict arrived for the table's Attempt. With a Speaker held,
  the Verdict line is spoken: the band word, then the Quip when quips are on.
  """
  @spec verdict_received(t(), map(), table()) :: {t(), [effect()]}
  def verdict_received(%__MODULE__{} = voice, verdict, table) do
    voice = track(voice, table.attempt)

    if table.speaker? do
      speak(voice, table.attempt, :verdict, verdict_line(verdict, table.quips?))
    else
      {voice, []}
    end
  end

  @doc """
  A `{:speak, ...}` effect was answered: `{:ok, %{audio: ..., format: ...,
  meta: ...}}`, or `{:error, failure_meta}` with the failure metadata the
  Chronicle records. A Verdict's metadata releases a held Page.
  """
  @spec spoken(t(), integer(), kind(), {:ok, map()} | {:error, map()}, table()) ::
          {t(), [effect()]}
  def spoken(%__MODULE__{} = voice, attempt, kind, {:ok, result}, table) do
    voice = track(voice, table.attempt)

    if attempt == voice.attempt do
      clip = %{audio: result.audio, format: Map.get(result, :format, :mp3)}
      voice = %{voice | clips: Map.put(voice.clips, kind, clip)} |> done_speaking(attempt, kind)
      landed(voice, attempt, kind, result, table)
    else
      {voice,
       [
         {:log, :warning,
          "Voice for attempt #{attempt} (#{kind}) arrived after next attempt started " <>
            "(current: #{voice.attempt}), dropping"}
       ]}
    end
  end

  def spoken(%__MODULE__{} = voice, attempt, kind, {:error, failure_meta}, table) do
    voice = voice |> track(table.attempt) |> done_speaking(attempt, kind)

    log =
      {:log, :warning,
       "Voice synthesis failed for attempt #{attempt} (#{kind}): #{failure_meta["failure"]}"}

    if kind == :verdict do
      {voice, release} =
        release(%{voice | voice_meta: Map.put(voice.voice_meta, attempt, failure_meta)})

      {voice, [log | release]}
    else
      {voice, [log]}
    end
  end

  @doc """
  A Page closed with this Chronicle Entry. It is committed now, or held while
  one of its Attempts' Verdict is still being spoken.
  """
  @spec page_closed(t(), Entry.t()) :: {t(), [effect()]}
  def page_closed(%__MODULE__{} = voice, %Entry{} = entry) do
    if waiting?(voice, entry) do
      {%{voice | held_page: entry}, []}
    else
      {voice, [commit(voice, entry)]}
    end
  end

  @doc """
  The Page turned. A held Page is committed with whatever voice metadata has
  landed, and everything else is forgotten.
  """
  @spec page_turned(t()) :: {t(), [effect()]}
  def page_turned(%__MODULE__{} = voice) do
    {_voice, effects} = release(voice)
    {new(), effects}
  end

  @doc """
  The clip of `kind` for `attempt`, which must be the table's. `kind` may be
  an atom or a string, as the web parsed it.
  """
  @spec clip(t(), integer(), kind() | String.t(), table()) ::
          {:ok, binary(), atom() | String.t()} | {:error, :not_found}
  def clip(%__MODULE__{} = voice, attempt, kind, table) do
    with true <- attempt == table.attempt and attempt == voice.attempt,
         {:ok, kind} <- kind(kind),
         %{audio: audio, format: format} when is_binary(audio) <- voice.clips[kind] do
      {:ok, audio, format}
    else
      _ -> {:error, :not_found}
    end
  end

  # -- the Attempt being tracked ----------------------------------------------

  defp track(%{attempt: attempt} = voice, attempt), do: voice

  defp track(voice, attempt) do
    %{voice | attempt: attempt, clips: %{}, speaking: %{voice.speaking | bookends: nil}}
  end

  defp speak_bookends?(voice, table) do
    table.speaker? and table.phase == :bridging and is_list(table.bookends) and
      table.bookends != [] and not clip?(voice, :bookends) and
      voice.speaking.bookends != table.attempt
  end

  defp speak(voice, attempt, kind, line) do
    {%{voice | speaking: Map.put(voice.speaking, kind, attempt)}, [{:speak, attempt, kind, line}]}
  end

  defp done_speaking(voice, attempt, kind) do
    if voice.speaking[kind] == attempt do
      %{voice | speaking: Map.put(voice.speaking, kind, nil)}
    else
      voice
    end
  end

  defp landed(voice, attempt, :verdict, result, _table) do
    meta = provider_meta(result[:meta] || %{})
    {voice, release} = release(%{voice | voice_meta: Map.put(voice.voice_meta, attempt, meta)})
    {voice, release ++ [{:broadcast, {:voice_ready, attempt}}]}
  end

  defp landed(voice, attempt, :bookends, _result, table) do
    if table.phase == :bridging do
      {voice, [{:broadcast, {:bookends_ready, attempt}}]}
    else
      {voice, []}
    end
  end

  defp offers(voice, table) do
    cond do
      table.phase == :bridging and clip?(voice, :bookends) ->
        [{:broadcast, {:bookends_ready, table.attempt}}]

      table.phase == :reveal and clip?(voice, :verdict) ->
        [{:broadcast, {:voice_ready, table.attempt}}]

      true ->
        []
    end
  end

  defp clip?(voice, kind), do: match?(%{audio: audio} when is_binary(audio), voice.clips[kind])

  defp kind(kind) when kind in [:bookends, "bookends"], do: {:ok, :bookends}
  defp kind(kind) when kind in [:verdict, "verdict"], do: {:ok, :verdict}
  defp kind(_kind), do: :error

  # -- the Verdict line --------------------------------------------------------

  defp verdict_line(verdict, quips?) do
    closeness = verdict[:closeness] || verdict["closeness"]

    band =
      (verdict[:band] && to_string(verdict[:band])) ||
        (closeness && Ladder.read(closeness).band |> to_string()) ||
        "miss"

    band_word = String.replace(band, "_", " ")
    quip = (verdict[:quip] || verdict["quip"] || "") |> to_string() |> String.trim()

    if quips? and quip != "", do: "#{band_word}. #{quip}", else: band_word
  end

  defp provider_meta(raw) do
    voice = pick(raw, [:voice, :voice_id]) || "default"
    provider = pick(raw, [:provider])

    %{
      "provider" => provider && to_string(provider),
      "voice" => to_string(voice),
      "model" => to_string(pick(raw, [:model]) || voice),
      "cost_usd" => pick(raw, [:cost_usd, :cost]),
      "latency_ms" => pick(raw, [:latency_ms, :latency])
    }
  end

  # The first key present, each tried as an atom and then as a string.
  defp pick(raw, keys) do
    Enum.find_value(keys, fn key -> raw[key] || raw[Atom.to_string(key)] end)
  end

  # -- the Chronicle hold ------------------------------------------------------

  defp waiting?(voice, entry) do
    pending = voice.speaking.verdict

    pending != nil and is_nil(Map.get(voice.voice_meta, pending)) and
      Enum.any?(entry.attempts, &(&1.number == pending))
  end

  defp release(%{held_page: nil} = voice), do: {voice, []}

  defp release(%{held_page: entry} = voice),
    do: {%{voice | held_page: nil}, [commit(voice, entry)]}

  defp commit(voice, entry), do: {:commit_chronicle, attach_meta(entry, voice.voice_meta)}

  defp attach_meta(%Entry{} = entry, meta) do
    attempts =
      Enum.map(entry.attempts, fn %Entry.Attempt{} = attempt ->
        case Map.get(meta, attempt.number) do
          nil ->
            attempt

          v_meta ->
            %{attempt | verdicts: Enum.map(attempt.verdicts, &%{&1 | voice_meta: v_meta})}
        end
      end)

    %{entry | attempts: attempts}
  end
end
