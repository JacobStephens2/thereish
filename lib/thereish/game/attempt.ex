defmodule Thereish.Game.Attempt do
  @moduledoc """
  One Attempt at a Page, as the Game holds it: its number, its Bookends and
  where each came from, the Bridges written so far, the one Verdict on them,
  an overrule the table has proposed and not yet settled or has declined,
  each Seat's Call
  during the Beat, each Seat's Reaction at the reveal, and each Seat's
  Opinion of the grade.

  Everything here starts over when an Attempt does, and nothing else does.
  `open/3` is the only fresh Attempt, so writing a Page, advancing an Attempt
  and turning to the next Page cannot disagree about what a new one holds.
  The Attempts a Page has already played are kept whole, in this same shape.

  Pure, and owned by `Thereish.Game`: it is read and written there and tested
  through the Game's interface.
  """

  alias Thereish.Bookends

  @enforce_keys [:number, :bookends, :origins]
  defstruct [
    :number,
    :bookends,
    :origins,
    bridges: %{},
    verdict: nil,
    overrule: nil,
    declined: nil,
    calls: %{},
    reactions: %{},
    opinions: %{}
  ]

  @typedoc "Where one Bookend came from: the Give that dealt it, or the Bridge a miss carried."
  @type origin :: Bookends.origin() | Bookends.claimed()

  @typedoc """
  `origins` say whose Give or Bridge each Bookend was. They can be shorter than
  the Bookends, when the Author named fewer sources than it wrote words.

  `overrule` is the proposal still waiting on the table (`Thereish.Overrule`),
  nil once it is agreed or declined. `declined` is the Seat that declined one,
  kept for the rest of the Attempt so a withdrawn proposal is a sentence rather
  than a banner that disappeared. `opinions` is each Seat's Opinion label, by
  Seat id.

  `calls` is the band each Seat named during the Beat and `reactions` the one
  word each sent at the reveal, both by Seat id and both latest-wins: a Seat
  may change its mind, and neither is ever counted.
  """
  @type t :: %__MODULE__{
          number: pos_integer(),
          bookends: [String.t()],
          origins: [origin()],
          bridges: %{String.t() => String.t()},
          verdict: Thereish.Game.verdict() | nil,
          overrule: Thereish.Overrule.t() | nil,
          declined: String.t() | nil,
          calls: %{String.t() => atom()},
          reactions: %{String.t() => atom()},
          opinions: %{String.t() => String.t()}
        }

  @doc "Opens Attempt `number` on `bookends`, with nothing yet written against them."
  @spec open(pos_integer(), [String.t()], [origin()]) :: t()
  def open(number, bookends, origins) do
    %__MODULE__{number: number, bookends: bookends, origins: origins}
  end
end
