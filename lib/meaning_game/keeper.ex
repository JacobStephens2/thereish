defmodule MeaningGame.Keeper do
  @moduledoc """
  The one seam through which the game talks to language models.

  Nothing else in the codebase knows a provider exists. Model choice, per-role
  effort, hedging, caching, and schema validation all end up behind here; today
  the only role that has crossed it is the Assayer, and the only adapter is
  `MeaningGame.Keeper.Fake`.

  Which adapter is in use is configuration, so a test and the couch differ by a
  setting rather than by a code path:

      config :meaning_game, :keeper, adapter: MeaningGame.Keeper.Fake

  An assay is asked for a pair of Bridges at a time. That is what the Room has
  to route a verdict back to, and it is what a Page with more than two Seats
  turns into: one request per unordered pair, all fired at once.
  """

  @typedoc "The Anchors, and the two Bridges written between them."
  @type request :: %{anchors: [String.t()], bridges: [String.t()]}

  @typedoc "A grade on the ladder's scale, and the sentence the players argue with."
  @type verdict :: %{closeness: integer(), reasoning: String.t()}

  @callback assay(request()) :: {:ok, verdict()} | {:error, term()}

  @doc """
  Grades how close two Bridges landed.

  An error is not a crash and not a zero: the Room turns it into
  `:verdict_unavailable` and the game admits it has no verdict rather than
  inventing one.
  """
  @spec assay(request()) :: {:ok, verdict()} | {:error, term()}
  def assay(request), do: adapter().assay(request)

  defp adapter do
    :meaning_game |> Application.fetch_env!(:keeper) |> Keyword.fetch!(:adapter)
  end
end
