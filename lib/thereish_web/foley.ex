defmodule ThereishWeb.Foley do
  @moduledoc """
  Coordinates pushed audio events to the speaking view.
  """
  use ThereishWeb, :verified_routes

  import Phoenix.LiveView, only: [push_event: 3]

  @doc """
  Pushes foley audio events to the socket when this view is the speaker.
  Silences this view if it lost the speaker.
  When `stage?: true` (or when view is StageLive), pushes `foley:commit` to
  the Stage view whenever the count of committed Seats rises within a Page.
  """
  def push_foley_events(socket, old_room, new_room, opts \\ []) do
    stage? = Keyword.get(opts, :stage?, socket.view == ThereishWeb.StageLive)

    socket =
      if stage? do
        maybe_push_commit(socket, old_room, new_room)
      else
        socket
      end

    cond do
      not is_nil(old_room) and Map.get(old_room, :speaker?) and not Map.get(new_room, :speaker?) ->
        push_event(socket, "foley:stop", %{})

      Map.get(new_room, :speaker?) ->
        socket
        |> maybe_stop_stale_voice(old_room, new_room)
        |> maybe_push_page(old_room, new_room)
        |> maybe_push_beat(old_room, new_room)
        |> maybe_push_sting(old_room, new_room)
        |> maybe_push_ending(old_room, new_room)
        |> maybe_push_prologue(old_room, new_room)

      true ->
        socket
    end
  end

  @doc """
  Pushes a foley:own-commit event to the committing phone's view only when no
  Stage holds the Room. With a Stage present, the Stage sounds the commit and
  the phone stays quiet.
  """
  def push_own_commit(socket) do
    if Map.get(socket.assigns, :stage_present?, false) do
      socket
    else
      push_event(socket, "foley:own-commit", %{})
    end
  end

  @doc """
  Pushes a foley:voice event to the socket if this view is the speaker.

  `kind` is `:bookends` (Attempt announcement) or `:verdict` (Assayer at the reveal).
  """
  def push_voice(socket, attempt, kind \\ :verdict) do
    room = socket.assigns[:room]

    if room && Map.get(room, :speaker?) do
      url =
        case kind do
          :bookends -> ~p"/r/#{socket.assigns.slug}/voice/#{attempt}/bookends"
          _ -> ~p"/r/#{socket.assigns.slug}/voice/#{attempt}"
        end

      push_event(socket, "foley:voice", %{
        attempt: attempt,
        kind: to_string(kind),
        url: url
      })
    else
      socket
    end
  end

  # Music plays on the Stage as soon as it holds the Speaker — including the
  # wait for seats, Gives, and the Author — not only once Bridging starts.
  # Tap-for-sound only resumes the audio context; without this push there is
  # nothing to hear.
  @music_phases [:waiting, :giving, :writing, :bridging, :assaying, :reveal, :closed]

  defp maybe_push_page(socket, old_room, new_room) do
    is_music_phase? = new_room.phase in @music_phases

    entered_music_phase? =
      is_nil(old_room) or old_room.phase not in @music_phases

    just_claimed = is_nil(old_room) or !Map.get(old_room, :speaker?)

    # A new Page still gets its own push, even when the waiting fallback
    # resolved to the same file as the Page's loop.
    entered_bridging? =
      new_room.phase == :bridging and
        (is_nil(old_room) or old_room.phase not in [:bridging, :assaying, :reveal])

    payload = page_payload(new_room)
    old_payload = page_payload(old_room)

    track_changed =
      is_music_phase? and not is_nil(old_room) and
        (payload.path != old_payload.path or payload.title != old_payload.title or
           payload.kind != old_payload.kind)

    if (is_music_phase? and entered_music_phase?) or (is_music_phase? and just_claimed) or
         entered_bridging? or track_changed do
      push_event(socket, "foley:page", payload)
    else
      socket
    end
  end

  # The Room has already resolved the music setting into `playing`, which is
  # nil when nothing plays.
  defp page_payload(%{playing: %{path: path} = playing}) when not is_nil(path) do
    %{path: path, title: playing[:title], kind: to_string(playing[:kind] || "repertoire")}
  end

  defp page_payload(_room), do: %{path: nil, title: nil, kind: nil}

  defp maybe_stop_stale_voice(socket, old_room, new_room) do
    if not is_nil(old_room) and attempt_number(old_room) != attempt_number(new_room) do
      push_event(socket, "foley:stop_voice", %{attempt: attempt_number(new_room)})
    else
      socket
    end
  end

  defp maybe_push_beat(socket, old_room, new_room) do
    if new_room.phase == :assaying and (is_nil(old_room) or old_room.phase != :assaying) do
      push_event(socket, "foley:beat", %{})
    else
      socket
    end
  end

  defp maybe_push_sting(socket, old_room, new_room) do
    reveal_arrived? =
      not is_nil(new_room[:reveal]) and
        (is_nil(old_room) or is_nil(old_room[:reveal]))

    if reveal_arrived? do
      band = (new_room[:reveal] && new_room.reveal[:band]) || :miss
      push_event(socket, "foley:sting", %{band: band})
    else
      socket
    end
  end

  defp maybe_push_ending(socket, old_room, new_room) do
    closed_now? = new_room.phase == :closed or not is_nil(Map.get(new_room, :closed))

    was_closed? =
      not is_nil(old_room) and
        (old_room.phase == :closed or not is_nil(Map.get(old_room, :closed)))

    if closed_now? and not was_closed? do
      kind = ending_kind(new_room)
      push_event(socket, "foley:ending", %{kind: kind})
    else
      socket
    end
  end

  defp ending_kind(room) do
    close_reason = room[:closed] && room.closed[:because]

    if close_reason in [:meld, "meld"] do
      case closing_band(room) do
        band when band in [:deep_meld, "deep_meld"] -> :deep_meld
        _ -> :meld
      end
    else
      :unmelded
    end
  end

  defp closing_band(room) do
    cond do
      is_nil(room[:reveal]) ->
        nil

      room.reveal[:band] ->
        room.reveal[:band]

      true ->
        nil
    end
  end

  defp maybe_push_prologue(socket, old_room, new_room) do
    prologue_started? =
      not is_nil(new_room[:prologue]) and
        (is_nil(old_room) or is_nil(old_room[:prologue]) or !Map.get(old_room, :speaker?))

    prologue_ended? =
      is_nil(new_room[:prologue]) and
        not is_nil(old_room) and not is_nil(old_room[:prologue])

    cond do
      prologue_started? ->
        push_event(socket, "foley:prologue", %{path: new_room.prologue.reading})

      prologue_ended? ->
        push_event(socket, "foley:stop_prologue", %{})

      true ->
        socket
    end
  end

  defp maybe_push_commit(socket, old_room, new_room) do
    if commit_rose?(old_room, new_room) do
      push_event(socket, "foley:commit", %{})
    else
      socket
    end
  end

  defp commit_rose?(nil, _new_room), do: false

  defp commit_rose?(old_room, new_room) do
    new_room.phase in [:bridging, :assaying] and
      attempt_number(old_room) == attempt_number(new_room) and
      count_committed(new_room) > count_committed(old_room)
  end

  defp attempt_number(room) do
    case room[:attempt] do
      %{number: n} -> n
      n when is_integer(n) -> n
      _ -> nil
    end
  end

  defp count_committed(room) do
    if room && is_list(room[:seats]) do
      Enum.count(room.seats, & &1[:committed?])
    else
      0
    end
  end
end
