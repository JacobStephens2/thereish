defmodule Thereish.Ladder do
  @moduledoc """
  The scale a closeness is read on, and the five bands it is read into.

  Everything here is configuration rather than constants in the rules, because
  everything here is a calibration question the couch answers: where a Meld
  starts, how wide the middle bands are, and whether 40 should feel like a miss
  or like an adjacent thought. The fairness tap exists to move these numbers.

  The meld threshold is not a number of its own — it is the floor of the `:meld`
  band. One number cannot drift from the other if there is only one number.

  Band *wording* is not here. `:deep_meld` is the rules' name for a rung; what
  the stage says when the couple land on it is the Assayer's line, written about
  the Bridges they actually wrote.
  """

  @doc """
  How one closeness reads: the number, the band it lands in, and whether it is a
  Meld.

  `nil` is a pair the Assayer could not grade, and it reads as nothing rather
  than as a zero — "we don't know" is not "you missed".
  """
  @spec read(integer() | nil) :: %{
          closeness: integer() | nil,
          band: atom() | nil,
          melded?: boolean()
        }
  def read(nil), do: %{closeness: nil, band: nil, melded?: false}

  def read(closeness) do
    closeness = clamp(closeness)

    %{closeness: closeness, band: band(closeness), melded?: melded?(closeness)}
  end

  @doc "The bands, lowest first, each with the closeness it starts at."
  @spec bands() :: keyword(integer())
  def bands, do: config(:bands)

  @doc "The names of the bands on the ladder, lowest first, as atoms."
  @spec band_names() :: [atom()]
  def band_names, do: Keyword.keys(bands())

  @doc "The closeness at which two Bridges count as one mind."
  @spec meld_threshold() :: integer()
  def meld_threshold, do: Keyword.fetch!(bands(), :meld)

  @doc "Whether a closeness is a Meld."
  @spec melded?(integer()) :: boolean()
  def melded?(closeness), do: closeness >= meld_threshold()

  @doc "The band a closeness lands in."
  @spec band(integer()) :: atom()
  def band(closeness) do
    bands()
    |> Enum.reverse()
    |> Enum.find_value(fn {name, floor} -> closeness >= floor && name end)
  end

  # The ladder's numbers are the game's, not the Assayer's: a model that answers
  # 140 has said "as close as it gets", and the players are shown the top rung
  # rather than a number the ladder has no rung for.
  defp clamp(closeness) do
    first..last//_ = config(:scale)

    closeness |> max(first) |> min(last)
  end

  defp config(key) do
    :thereish |> Application.fetch_env!(:ladder) |> Keyword.fetch!(key)
  end
end
