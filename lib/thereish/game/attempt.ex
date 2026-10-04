defmodule Thereish.Game.Attempt do
  @moduledoc """
  One Attempt at a Page, as the Game holds it: its number, its Bookends and
  where each came from, the Bridges written so far, the one Verdict on them,
  an overrule the table has proposed and not yet settled, and each Seat's
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
    opinions: %{}
  ]

  @typedoc """
  `origins` say whose Give or Bridge each Bookend was. They can be shorter than
  the Bookends, when the Author named fewer sources than it wrote words.

  `overrule` is the proposal still waiting on the table, nil once it is agreed
  or declined. `opinions` is each Seat's Opinion label, by Seat id.
  """
  @type t :: %__MODULE__{
          number: pos_integer(),
          bookends: [String.t()],
          origins: [Bookends.origin() | Bookends.claimed()],
          bridges: %{String.t() => String.t()},
          verdict: Thereish.Game.verdict() | nil,
          overrule:
            %{proposer_id: String.t(), closeness: integer(), agreed: MapSet.t(String.t())} | nil,
          opinions: %{String.t() => String.t()}
        }

  @doc "Opens Attempt `number` on `bookends`, with nothing yet written against them."
  @spec open(pos_integer(), [String.t()], [map()]) :: t()
  def open(number, bookends, origins) do
    %__MODULE__{number: number, bookends: bookends, origins: origins}
  end
end
