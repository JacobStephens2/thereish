defmodule MeaningGameWeb.RoomComponents do
  @moduledoc """
  The parts of a Room that both the phones and the stage draw.

  The roster is one component on purpose: "the stage lists who has joined;
  phones show the same roster" is a rule, and a rule with two implementations is
  a rule with two answers.
  """
  use MeaningGameWeb, :html

  attr :room, :map, required: true, doc: "a snapshot from MeaningGame.Rooms.snapshot/2"

  def roster(assigns) do
    ~H"""
    <div data-role="roster">
      <ul class="flex flex-col gap-2">
        <li :for={seat <- @room.seats} data-seat={seat.id} class="flex items-center gap-2 text-lg">
          <span class="size-2 rounded-full bg-primary" aria-hidden="true"></span>
          <span>{seat.name}</span>
          <span :if={seat.you?} class="text-sm opacity-60">(you)</span>
        </li>
        <li :if={@room.seats == []} class="text-lg opacity-60">Nobody yet</li>
      </ul>

      <p data-role="open-seats" class="mt-3 text-sm opacity-60">{waiting(@room)}</p>
    </div>
    """
  end

  defp waiting(%{open_seats: 0, seat_limit: seat_limit}),
    do: "All #{seat_limit} seats taken"

  defp waiting(%{open_seats: 1}), do: "Waiting for 1 more"
  defp waiting(%{open_seats: open}), do: "Waiting for #{open} more"
end
