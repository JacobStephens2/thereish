defmodule MeaningGame.Pages do
  @moduledoc """
  Where a Room finds a Page. For now there are five, and they were written by
  hand.

  The Author writes these ahead of play — Anchors, the Bait, the pre-graded
  table — and a Room draws from that pool. None of that exists yet, and the
  rules do not care: a Page is two Anchors and an id, and everything the couple
  will eventually see hangs off the same shape.

  A handful rather than one, because "one more?" has to be one more *Page*. The
  pool is a ring: the Page after the last one is the first one again, which is
  the least surprising thing a hand-written pool can do until the Author fills
  it.
  """

  @pool [
    %{id: "hand-written-1", anchors: ["lantern", "harbour"]},
    %{id: "hand-written-2", anchors: ["desert", "mirror"]},
    %{id: "hand-written-3", anchors: ["clock", "river"]},
    %{id: "hand-written-4", anchors: ["honey", "knife"]},
    %{id: "hand-written-5", anchors: ["letter", "attic"]}
  ]

  @doc "The Page every Room opens on until the Author has written any."
  @spec first() :: MeaningGame.Game.page()
  def first, do: hd(@pool)

  @doc """
  The Page after this one — what "one more?" hands the Room.

  A Page id the pool has never heard of is answered with the first Page rather
  than with nothing, because a Room that cannot find its next Page is a Room
  with no Page at all.
  """
  @spec next(String.t()) :: MeaningGame.Game.page()
  def next(page_id) do
    case Enum.find_index(@pool, &(&1.id == page_id)) do
      nil -> first()
      index -> Enum.at(@pool, rem(index + 1, length(@pool)))
    end
  end
end
