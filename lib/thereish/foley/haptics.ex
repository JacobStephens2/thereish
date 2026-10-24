defmodule Thereish.Foley.Haptics do
  @moduledoc """
  The buzz patterns a phone plays, as data.

  A buzz is a Cue like any other (ADR-0023's noise, felt rather than heard), so
  the vocabulary lives in Elixir beside the rest of Foley and not in a hook:
  tuning how a Meld lands in the hand is a sentence of config here, not a
  rebuilt asset bundle.

  Each pattern is the list `navigator.vibrate` takes — milliseconds on, then
  off, then on, alternating. A pattern that opens with `0` waits before it
  starts, which is how the Meld gets its little run-up.
  """

  @patterns %{
    # The phone in your own hand, confirming the word is gone.
    own_commit: [12],
    # Somebody else at the table just committed. Lighter than your own: it is
    # news, not a confirmation.
    other_commit: [8],
    # The Beat. Two taps and a longer one, so the hand knows the wait started.
    beat: [20, 60, 20],
    sting_miss: [10],
    sting_almost: [16, 40, 16],
    sting_meld: [0, 40, 60, 40, 60, 140],
    # A Nudge landing: the one word that moved between Seats.
    nudge_landed: [14, 30, 14],
    # Somebody shouted at the reveal. The lightest thing in the vocabulary,
    # because a Reaction is noise and noise is not news: it is how a Room of
    # phones and no Stage still knows the table made a sound (ADR-0023).
    reaction_landed: [6],
    ending: [0, 30, 90, 30]
  }

  @type name ::
          :own_commit
          | :other_commit
          | :beat
          | :sting_miss
          | :sting_almost
          | :sting_meld
          | :nudge_landed
          | :reaction_landed
          | :ending

  @doc """
  The pattern named, or `nil` for a name the vocabulary does not hold.
  """
  @spec pattern(name() | atom()) :: [non_neg_integer()] | nil
  def pattern(name), do: Map.get(@patterns, name)

  @doc """
  The sting a band is felt as.

  Six bands, three buzzes: the hand reads near, nearer and landed, which is as
  much as a hand reads. An ungraded Attempt is felt as a miss, exactly as it is
  heard.
  """
  @spec for_sting(atom() | nil) :: [non_neg_integer()]
  def for_sting(band) when band in [:meld, :deep_meld], do: pattern(:sting_meld)
  def for_sting(band) when band in [:close, :almost], do: pattern(:sting_almost)
  def for_sting(_band), do: pattern(:sting_miss)
end
