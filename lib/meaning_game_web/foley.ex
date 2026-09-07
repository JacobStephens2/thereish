defmodule MeaningGameWeb.Foley do
  @moduledoc """
  Coordinates pushed audio events to the speaking view.
  """
  use MeaningGameWeb, :verified_routes

  import Phoenix.LiveView, only: [push_event: 3]

  @doc """
  Pushes foley audio events to the socket when this view is the speaker.
  Silences this view if it lost the speaker.
  When `stage?: true` (or when view is StageLive), pushes `foley:commit` to
  the Stage view whenever the count of committed Seats rises within a Page.
  """
  def push_foley_events(socket, old_room, new_room, opts \\ []) do
    stage? = Keyword.get(opts, :stage?, socket.view == MeaningGameWeb.StageLive)

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
  Pushes a foley:own-commit event to the committing phone's view.
  """
  def push_own_commit(socket) do
    push_event(socket, "foley:own-commit", %{})
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

  defp maybe_push_page(socket, old_room, new_room) do
    is_active_page = new_room.phase in [:bridging, :assaying, :reveal]

    entered_active_page =
      is_nil(old_room) or old_room.phase not in [:bridging, :assaying, :reveal]

    just_claimed = is_nil(old_room) or !Map.get(old_room, :speaker?)

    track_path = resolve_track_path(new_room)
    old_track_path = resolve_track_path(old_room)

    track_changed = is_active_page and not is_nil(old_room) and track_path != old_track_path

    if (new_room.phase == :bridging and entered_active_page) or (is_active_page and just_claimed) or
         track_changed do
      push_event(socket, "foley:page", %{path: track_path})
    else
      socket
    end
  end

  defp resolve_track_path(nil), do: nil

  defp resolve_track_path(room) do
    case to_string(Map.get(room, :music, "page")) do
      "off" ->
        nil

      "house" ->
        "/audio/house-loop.mp3"

      _ ->
        if room[:track] && room.track[:path] do
          room.track.path
        else
          "/audio/house-loop.mp3"
        end
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
      kind =
        if new_room[:closed] && new_room.closed[:because] == :meld do
          :meld
        else
          :unmelded
        end

      push_event(socket, "foley:ending", %{kind: kind})
    else
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
