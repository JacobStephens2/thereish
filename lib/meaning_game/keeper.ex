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

  @typedoc """
  Which model answered, at what prompt version, how long it took and what it
  cost. Every verdict carries it and the Chronicle writes it down, so that the
  model policy is measured rather than remembered.
  """
  @type meta :: %{
          model: String.t(),
          prompt_version: String.t(),
          cost_usd: float() | nil,
          latency_ms: non_neg_integer()
        }

  @typedoc "A grade on the ladder's scale, and the sentence the players argue with."
  @type verdict :: %{closeness: integer(), reasoning: String.t(), meta: meta()}

  @callback assay(request()) :: {:ok, verdict()} | {:error, term()}

  @doc """
  Grades how close two Bridges landed.

  How long it took is measured here rather than by the caller, because the
  provenance of a model call is the seam's business and nothing on the other
  side of it should have to remember to hold a stopwatch.

  An error is not a crash and not a zero: the Room turns it into
  `:verdict_unavailable` and the game admits it has no verdict rather than
  inventing one.
  """
  @spec assay(request()) :: {:ok, verdict()} | {:error, term()}
  def assay(request) do
    started = System.monotonic_time(:millisecond)

    case adapter().assay(request) do
      {:ok, verdict} -> {:ok, timed(verdict, System.monotonic_time(:millisecond) - started)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp timed(verdict, latency_ms) do
    Map.update(verdict, :meta, %{latency_ms: latency_ms}, &Map.put(&1, :latency_ms, latency_ms))
  end

  defp adapter do
    :meaning_game |> Application.fetch_env!(:keeper) |> Keyword.fetch!(:adapter)
  end
end
