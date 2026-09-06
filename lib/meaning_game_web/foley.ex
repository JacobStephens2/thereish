defmodule MeaningGameWeb.Foley do
  @moduledoc """
  Coordinates pushed audio events to the speaking view.
  """
  import Phoenix.LiveView, only: [push_event: 3]

  @doc """
  Pushes foley audio events to the socket when this view is the speaker.
  Silences this view if it lost the speaker.
  """
  def push_foley_events(socket, old_room, new_room) do
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

  defp maybe_push_page(socket, old_room, new_room) do
    is_active_page = new_room.phase in [:bridging, :assaying, :reveal]

    entered_active_page =
      is_nil(old_room) or old_room.phase not in [:bridging, :assaying, :reveal]

    just_claimed = is_nil(old_room) or !Map.get(old_room, :speaker?)

    if (new_room.phase == :bridging and entered_active_page) or (is_active_page and just_claimed) do
      push_event(socket, "foley:page", %{path: "/audio/house-loop.mp3"})
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
end
