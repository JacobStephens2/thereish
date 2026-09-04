defmodule MeaningGame.Pages do
  @moduledoc """
  Where a Room finds a Page. For now there is one, and it was written by hand.

  The Author writes these ahead of play — Anchors, the Bait, the pre-graded
  table — and a Room draws from that pool. None of that exists yet, and the
  rules do not care: a Page is two Anchors and an id, and everything the couple
  will eventually see hangs off the same shape.
  """

  @first %{id: "hand-written-1", anchors: ["lantern", "harbour"]}

  @doc "The Page every Room opens on until the Author has written any."
  @spec first() :: MeaningGame.Game.page()
  def first, do: @first
end
