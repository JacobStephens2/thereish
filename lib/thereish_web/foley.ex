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
        |> maybe_push_page(old_room, new_room)
        |> maybe_push_beat(old_room, new_room)
        |> maybe_push_sting(old_room, new_room)
        |> maybe_push_ending(old_room, new_room)

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
  """
  def push_voice(socket, attempt) do
    room = socket.assigns[:room]

    if room && Map.get(room, :speaker?) do
      push_event(socket, "foley:voice", %{
        attempt: attempt,
        url: ~p"/r/#{socket.assigns.slug}/voice/#{attempt}"
      })
    else
      socket
    end
  end

  # Music plays on the Stage as soon as it holds the Speaker — including the
  # wait for seats, Gives, and the Author — not only once Bridging starts.
  # Tap-for-sound only resumes the audio context; without this push there is
  # nothing to hear.
  @music_phases [:waiting, :giving, :writing, :bridging, :assaying, :reveal]

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

    track_info = resolve_track(new_room)
    old_track_info = resolve_track(old_room)

    track_changed =
      is_music_phase? and not is_nil(old_room) and
        (track_info.path != old_track_info.path or track_info.title != old_track_info.title or
           track_info.kind != old_track_info.kind)

    if (is_music_phase? and entered_music_phase?) or (is_music_phase? and just_claimed) or
         entered_bridging? or track_changed do
      push_event(socket, "foley:page", track_info)
    else
      socket
    end
  end

  defp resolve_track(nil), do: %{path: nil, title: nil, kind: nil}

  defp resolve_track(room) do
    case to_string(Map.get(room, :music, "page")) do
      "off" ->
        %{path: nil, title: nil, kind: nil}

      "house" ->
        repertoire_payload(room)

      _ ->
        cond do
          room[:track] && room.track[:path] ->
            %{path: room.track.path, title: room.track[:title], kind: "track"}

          room[:playing] && room.playing[:path] ->
            kind = to_string(room.playing[:kind] || "repertoire")
            %{path: room.playing.path, title: room.playing[:title], kind: kind}

          true ->
            repertoire_payload(room)
        end
    end
  end

  defp repertoire_payload(room) do
    item =
      cond do
        room[:playing] && room.playing[:kind] in ["repertoire", :repertoire] && room.playing[:path] ->
          room.playing

        room[:loop] ->
          room.loop

        true ->
          hd(Thereish.Foley.Repertoire.shipped_loops())
      end

    title = item[:title] || item[:name] || "Track"
    path = item.path

    %{path: path, title: title, kind: "repertoire"}
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

      is_list(room.reveal[:sides]) ->
        bands = Enum.map(room.reveal.sides, & &1[:band])
        if :deep_meld in bands or "deep_meld" in bands, do: :deep_meld, else: :meld

      true ->
        nil
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
