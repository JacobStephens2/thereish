defmodule Thereish.Foley.Voice do
  @moduledoc """
  Foley announcing an Attempt's Bookends, and the Verdict at the reveal.

  It is a pure reducer in the shape of Occupancy. The Room tells it what
  happened (the table moved, the Speaker was claimed, a Verdict arrived, a
  line was spoken, the Page turned) and gets back a new Voice
  and a list of effects to carry out. It does no I/O and sends no messages.

  It never stores what the Room or the Game already knows. The current attempt
  number, the Phase, the Bookends, whether a Speaker is held and the quips
  setting come in as a `table` on each call that needs them, so none of them
  can drift.

  ## Effects

    * `{:speak, request, line}`: echo the opaque request to `spoken/4`
    * `{:broadcast, {:bookends_ready, attempt}}`
    * `{:broadcast, {:voice_ready, attempt}}`
    * `{:verdict_pending, attempt}`: Verdict synthesis was requested
    * `{:verdict_spoken, attempt, meta}`: accepted success or failure metadata
    * `{:log, level, message}`

  ## Speech identity and lifetime

  Voice mints a fresh reference for each synthesis and keeps its Attempt and
  kind here. Callers carry only that reference and the line, and echo the
  reference with either result. Replacement retires the previous request for
  the same Attempt and kind; the first completion consumes a known request.
  Unknown, replaced and consumed requests change nothing.

  Clips belong to the Attempt Voice is tracking. `track/2` forgets clips and
  earlier Bookends requests when the Attempt changes. Outstanding Verdict
  requests survive within a Page so earlier failures can report their own
  Attempt's metadata; earlier successes are dropped. A Page turn forgets
  every request and clip, even when the next Page reuses Attempt 1.

  ## Recording speech

  Voice reports synthesis requests and normalized completion metadata. Room
  play folds those facts through Pages before forwarding the remaining
  effects, so Pages can submit an Entry before `voice_ready`. Voice keeps
  only speech and clips; a Page turn forgets them.
  """

  alias Thereish.Ladder

  defstruct attempt: nil,
            clips: %{},
            requests: %{}

  @type kind :: :bookends | :verdict
  @type clip :: %{audio: binary(), format: atom() | String.t()}
  @opaque request :: reference()
  @type result :: {:ok, map()} | {:error, map()}

  @type t :: %__MODULE__{
          attempt: integer() | nil,
          clips: %{optional(kind()) => clip()},
          requests: %{optional(request()) => {integer(), kind()}}
        }

  @typedoc """
  Something for the Room to do. Effects are descriptions: Voice performs none
  of them.
  """
  @type effect ::
          {:speak, request(), String.t()}
          | {:broadcast, {:bookends_ready | :voice_ready, integer()}}
          | {:verdict_pending, integer()}
          | {:verdict_spoken, integer(), map()}
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
  A `{:speak, request, line}` effect was answered with that same opaque
  request and `{:ok, %{audio: ..., format: ..., meta: ...}}`, or
  `{:error, failure_meta}` with the failure metadata the Chronicle records.
  Voice recovers the Attempt and kind, consuming the request once. Unknown
  requests are rejected before any state change. Accepted current Verdict
  results report metadata before readiness; failures keep metadata unchanged.
  """
  @spec spoken(t(), request(), result(), table()) :: {t(), [effect()]}
  def spoken(%__MODULE__{} = voice, request, result, table) do
    case Map.pop(voice.requests, request) do
      {nil, _requests} ->
        {voice, [{:log, :warning, "Unknown or completed Voice request, dropping"}]}

      {{attempt, kind}, requests} ->
        voice = %{voice | requests: requests} |> track(table.attempt)
        completed(voice, attempt, kind, result, table)
    end
  end

  defp completed(voice, attempt, kind, {:ok, result}, table) do
    if attempt == voice.attempt do
      clip = %{audio: result.audio, format: Map.get(result, :format, :mp3)}
      voice = %{voice | clips: Map.put(voice.clips, kind, clip)}
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

  defp completed(voice, attempt, kind, {:error, failure_meta}, _table) do
    log =
      {:log, :warning,
       "Voice synthesis failed for attempt #{attempt} (#{kind}): #{failure_meta["failure"]}"}

    if kind == :verdict do
      {voice, [log, {:verdict_spoken, attempt, failure_meta}]}
    else
      {voice, [log]}
    end
  end

  @doc "The Page turned: forget speech in flight and clips."
  @spec page_turned(t()) :: {t(), [effect()]}
  def page_turned(%__MODULE__{}), do: {new(), []}

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
    requests = Map.filter(voice.requests, fn {_ref, {_attempt, kind}} -> kind == :verdict end)
    %{voice | attempt: attempt, clips: %{}, requests: requests}
  end

  defp speak_bookends?(voice, table) do
    table.speaker? and table.phase == :bridging and is_list(table.bookends) and
      table.bookends != [] and not clip?(voice, :bookends) and
      not requested?(voice, table.attempt, :bookends)
  end

  defp speak(voice, attempt, kind, line) do
    request = make_ref()
    requests = Map.reject(voice.requests, fn {_ref, work} -> work == {attempt, kind} end)
    requests = Map.put(requests, request, {attempt, kind})
    pending = if kind == :verdict, do: [{:verdict_pending, attempt}], else: []

    {%{voice | requests: requests}, pending ++ [{:speak, request, line}]}
  end

  defp requested?(voice, attempt, kind),
    do: Enum.any?(voice.requests, fn {_ref, work} -> work == {attempt, kind} end)

  defp landed(voice, attempt, :verdict, result, _table) do
    meta = provider_meta(result[:meta] || %{})
    {voice, [{:verdict_spoken, attempt, meta}, {:broadcast, {:voice_ready, attempt}}]}
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
end
