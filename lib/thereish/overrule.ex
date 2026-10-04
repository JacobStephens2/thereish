defmodule Thereish.Overrule do
  @moduledoc """
  The rules for an Overrule: a table's joint ruling that replaces one Attempt's
  grade.

  One Seat proposes a Closeness and every Seat playing the Page agrees. Once
  they have, the ruled Verdict is what the table sees, and the ruling is what
  the Room hands on: the Chronicle keeps it beside what the Assayer said, and
  it rewrites the Precedent (ADR-0006). An open proposal is this module's
  struct, held by the Attempt (`Thereish.Game.Attempt`).

  Pure: no Repo and no Room. When a Seat may propose, agree or decline is the
  Game's rule (its `may`), and recording the ruling is the Steward's.
  """

  alias Thereish.Ladder

  @reasoning "Overruled jointly across all Seats. Recorded as precedent."
  @quip "House law."

  @enforce_keys [:proposer_id, :closeness, :agreed]
  defstruct [:proposer_id, :closeness, :agreed]

  @typedoc "An open proposal: who proposed it, the grade, and the Seats that agree."
  @type t :: %__MODULE__{
          proposer_id: String.t(),
          closeness: integer(),
          agreed: MapSet.t(String.t())
        }

  @typedoc "The Attempt being overruled, as the ruling records it."
  @type attempt :: %{
          number: pos_integer(),
          bookends: [String.t()],
          bridges: [String.t()]
        }

  @typedoc """
  What the Room hands on once the table agrees: what the machine said and what
  the table said. The `couple_*` keys are the Chronicle's columns (ADR-0003).
  """
  @type ruling :: %{
          attempt_number: pos_integer(),
          proposer_seat_id: String.t(),
          bookends: [String.t()],
          bridges: [String.t()],
          machine_closeness: integer() | nil,
          machine_reasoning: String.t() | nil,
          machine_quip: String.t() | nil,
          couple_closeness: integer(),
          couple_reasoning: String.t(),
          couple_quip: String.t()
        }

  @doc """
  Opens a proposal from `proposer_id` at `closeness`, or at the floor of the meld
  band when the proposer named none. The proposer agrees with it.
  """
  @spec propose(String.t(), integer() | nil) :: t()
  def propose(proposer_id, closeness \\ nil) do
    %__MODULE__{
      proposer_id: proposer_id,
      closeness: closeness || Ladder.meld_threshold(),
      agreed: MapSet.new([proposer_id])
    }
  end

  @doc "Adds one Seat's agreement."
  @spec agree(t(), String.t()) :: t()
  def agree(%__MODULE__{} = proposal, seat_id),
    do: %{proposal | agreed: MapSet.put(proposal.agreed, seat_id)}

  @doc """
  Whether every Seat playing the Page has agreed. A Seat that wrote no Bridge
  still plays the Page, so it still counts.
  """
  @spec unanimous?(t(), [String.t()]) :: boolean()
  def unanimous?(%__MODULE__{agreed: agreed}, page_seat_ids),
    do: Enum.all?(page_seat_ids, &MapSet.member?(agreed, &1))

  @doc """
  Rules an agreed proposal on `verdict`, the Attempt's Verdict.

  Answers the ruled Verdict the table then sees, with the Assayer's Closeness,
  reasoning and Quip kept beside it, and the ruling the Room hands on. They are
  built together so they cannot disagree about either grade. An ungraded
  Verdict is overruled into a number like any other.
  """
  @spec rule(t(), Thereish.Game.verdict(), attempt()) :: {map(), ruling()}
  def rule(%__MODULE__{} = proposal, verdict, attempt) do
    ruled_verdict =
      Map.merge(verdict, %{
        graded?: true,
        closeness: proposal.closeness,
        reasoning: @reasoning,
        quip: @quip,
        overruled?: true,
        original_closeness: verdict.closeness,
        original_reasoning: verdict.reasoning,
        original_quip: verdict.quip
      })

    ruling = %{
      attempt_number: attempt.number,
      proposer_seat_id: proposal.proposer_id,
      bookends: attempt.bookends,
      bridges: attempt.bridges,
      machine_closeness: verdict.closeness,
      machine_reasoning: verdict.reasoning,
      machine_quip: verdict.quip,
      couple_closeness: proposal.closeness,
      couple_reasoning: @reasoning,
      couple_quip: @quip
    }

    {ruled_verdict, ruling}
  end

  @doc "Whether a Verdict has already been overruled. No Verdict has not."
  @spec overruled?(Thereish.Game.verdict() | nil) :: boolean()
  def overruled?(nil), do: false
  def overruled?(verdict), do: Map.get(verdict, :overruled?, false)

  @doc """
  A pending proposal as `viewer` sees it, or `nil` when none is pending.
  `viewer` is a Seat id, or `nil` for a viewer that holds no Seat.
  """
  @spec view(t() | nil, String.t() | nil) :: map() | nil
  def view(nil, _viewer), do: nil

  def view(%__MODULE__{} = proposal, viewer) do
    %{
      pending?: true,
      proposer_id: proposal.proposer_id,
      closeness: proposal.closeness,
      agreed_seat_ids: MapSet.to_list(proposal.agreed),
      you_proposed?: viewer == proposal.proposer_id,
      you_agreed?: MapSet.member?(proposal.agreed, viewer)
    }
  end
end
