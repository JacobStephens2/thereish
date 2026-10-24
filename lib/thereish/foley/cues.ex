defmodule Thereish.Foley.Cues do
  @moduledoc """
  The Cues a screen plays because the Room's view changed.

  It compares the view a screen last had with the one it has now, rather
  than hearing each move of the Room's play, so a screen that slept or
  reconnected hears where the Room has got to. It is pure: it touches no
  socket, process or route, and turning a Cue into what the browser plays is
  the web layer's business.

  ## The rules, in order

    1. On the Stage, the commit tick, when the count of committed Seats rises
       within one Attempt while bridging or assaying. It plays whether or not
       the Stage holds the Speaker.
    2. On a phone, the buzzes: another Seat committing, the Beat, the sting at
       the reveal, a Nudge landing, and the ending. A buzz is not the
       Speaker's business — a phone that holds no Speaker still lives in a
       hand — so it is answered outside the Speaker's arm.
    3. A screen that just lost the Speaker only stops all sound.
    4. A screen holding the Speaker hears, in order: a stale Voice clip
       stopped when the Attempt moved on, the Page's music, the Beat, the
       sting at the reveal, the ending, and the Prologue starting or stopping.

  A screen's first render has no previous view.
  """

  alias Thereish.Foley.Haptics

  @type screen :: :phone | :stage

  @type cue ::
          :stop
          | {:stop_voice, attempt :: integer()}
          | {:page, path :: String.t() | nil, title :: String.t() | nil, kind :: String.t() | nil}
          | :beat
          | {:sting, band :: atom()}
          | {:ending, :meld | :deep_meld | :unmelded}
          | {:prologue, reading :: String.t()}
          | :stop_prologue
          | :commit
          | {:haptic, [non_neg_integer()]}

  @doc """
  The Cues `screen` plays, in order, as the Room's view moves from `old` (nil
  on the screen's first render) to `new`.
  """
  @spec between(map() | nil, map(), screen()) :: [cue()]
  def between(old, new, screen) when screen in [:phone, :stage] do
    commit(old, new, screen) ++ haptics(old, new, screen) ++ speaker(old, new)
  end

  defp speaker(old, new) do
    cond do
      old != nil and old.speaker? and not new.speaker? ->
        [:stop]

      new.speaker? ->
        stale_voice(old, new) ++
          page(old, new) ++
          beat(old, new) ++ sting(old, new) ++ ending(old, new) ++ prologue(old, new)

      true ->
        []
    end
  end

  defp commit(old, new, :stage) when old != nil do
    if new.phase in [:bridging, :assaying] and new.attempt.number == old.attempt.number and
         committed(new) > committed(old),
       do: [:commit],
       else: []
  end

  defp commit(_old, _new, _screen), do: []

  defp committed(view), do: Enum.count(view.seats, & &1.committed?)

  # The Seats that are not this screen's. Its own commit is confirmed by the
  # push the commit itself makes; what the diff is for is the news that
  # somebody else has written, which until now reached the Stage's speakers
  # and nobody's hand.
  defp others_committed(view), do: Enum.count(view.seats, &(&1.committed? and not &1.you?))

  # The same five moments the Speaker hears, read a second time by the hand.
  # Nothing here asks who holds the Speaker: a phone with the sound off is
  # still the device the game is being played on.
  defp haptics(nil, _new, _screen), do: []
  defp haptics(_old, _new, :stage), do: []

  defp haptics(old, new, :phone) do
    patterns = [
      other_commit?(old, new) && Haptics.pattern(:other_commit),
      entered_assaying?(old, new) && Haptics.pattern(:beat),
      first_reveal?(old, new) && Haptics.for_sting(new.reveal.band),
      nudge_landed?(old, new) && Haptics.pattern(:nudge_landed),
      closed?(old, new) && Haptics.pattern(:ending)
    ]

    for pattern <- patterns, is_list(pattern), do: {:haptic, pattern}
  end

  defp other_commit?(old, new) do
    new.phase in [:bridging, :assaying] and new.attempt.number == old.attempt.number and
      others_committed(new) > others_committed(old)
  end

  defp nudge_landed?(old, new), do: length(new.nudges) > length(old.nudges)

  defp stale_voice(old, new) do
    if old != nil and old.attempt.number != new.attempt.number,
      do: [{:stop_voice, new.attempt.number}],
      else: []
  end

  # Music plays from the moment the Speaker is held, the wait for Seats, Gives
  # and the Author included, not only once bridging starts. A new Page still
  # gets its own cue when the waiting draw is the same file as its music.
  defp page(old, new) do
    cue = page_cue(new)

    if old == nil or not old.speaker? or entered_bridging?(old, new) or cue != page_cue(old),
      do: [cue],
      else: []
  end

  defp page_cue(%{playing: %{path: path, title: title, kind: kind}}),
    do: {:page, path, title, kind}

  defp page_cue(_view), do: {:page, nil, nil, nil}

  defp entered_bridging?(old, new),
    do: new.phase == :bridging and old.phase not in [:bridging, :assaying, :reveal]

  # Each of the three arrivals is one moment with two readings, heard and felt,
  # so the moment itself is stated once and read twice.
  defp beat(old, new), do: if(entered_assaying?(old, new), do: [:beat], else: [])

  defp sting(old, new) do
    if first_reveal?(old, new), do: [{:sting, new.reveal.band || :miss}], else: []
  end

  defp ending(old, new) do
    if closed?(old, new), do: [{:ending, ending_kind(new)}], else: []
  end

  defp entered_assaying?(old, new),
    do: new.phase == :assaying and (old == nil or old.phase != :assaying)

  defp first_reveal?(old, new), do: new.reveal != nil and (old == nil or old.reveal == nil)

  defp closed?(old, new), do: new.phase == :closed and (old == nil or old.phase != :closed)

  defp ending_kind(%{closed: %{because: :meld}, reveal: %{band: :deep_meld}}), do: :deep_meld
  defp ending_kind(%{closed: %{because: :meld}}), do: :meld
  defp ending_kind(_view), do: :unmelded

  defp prologue(old, new) do
    cond do
      new.prologue != nil and (old == nil or old.prologue == nil or not old.speaker?) ->
        [{:prologue, new.prologue.reading}]

      new.prologue == nil and old != nil and old.prologue != nil ->
        [:stop_prologue]

      true ->
        []
    end
  end
end
