defmodule Thereish.Steward.Latency do
  @moduledoc """
  What a grade actually costs in seconds, measured where it will be paid.

  The reveal is a fixed 2.5 second beat and the p95 the Assayer has to fit
  inside is 4 seconds (design law 10). Those numbers were met from the VPS by
  the Steward prototype against a bench harness; this is the same measurement
  against the thing that shipped — the same prompt, the same schema, the same
  hedging, the same both-orderings grading, on the machine the couple will play
  against.

  It is not a test. It calls a provider and spends money, and it is meant to be
  run by hand from the VPS after a deploy that touched the Assayer:

      docker compose -f docker-compose.app.yml exec app \
        bin/thereish eval 'Thereish.Steward.Latency.measure()'

  The requests are fixed so that two runs are comparable, and they are spread
  across the ladder — an identical pair, a near miss, a wide miss — because a
  grade the model finds easy and a grade it has to think about are not the same
  round trip.

  One of them is a table of four rather than a couple. The reveal beat is the
  same beat at four Seats as at two (ADR-0010), so the number it has to fit
  inside has to be measured at the table size it now serves: four words is a
  longer prompt, a wider judgement and a furthest pair to pick, and none of that
  is free.
  """

  alias Thereish.Steward

  # The p95 the reveal has to absorb, in milliseconds.
  @target_ms 4_000

  @requests [
    %{bookends: ["ocean", "night"], bridges: ["moon", "moon"]},
    %{bookends: ["ocean", "night"], bridges: ["tide", "moon"]},
    %{bookends: ["coffee", "morning"], bridges: ["cup", "mug"]},
    %{bookends: ["mirror", "river"], bridges: ["reflection", "reflect"]},
    %{bookends: ["paper", "scar"], bridges: ["cut", "history"]},
    # A table of four: three words in one neighbourhood and one wandering off,
    # which is the reading ADR-0010 asks the Assayer to make and the longest
    # prompt it is asked to make it from.
    %{bookends: ["harbour", "dusk"], bridges: ["lighthouse", "beacon", "lamp", "gull"]}
  ]

  @doc """
  Grades `runs` requests one after another and reports what it took.

  Sequentially, because what is being measured is one reveal's round trip and
  the couch only ever has one in flight.
  """
  @spec measure(keyword()) :: %{p50: non_neg_integer(), p95: non_neg_integer(), met?: boolean()}
  def measure(opts \\ []) do
    runs = Keyword.get(opts, :runs, 20)
    benchmark(runs, &one/2, &report/1)
  end

  # One grade, announced as it happens: a run against a provider that has gone
  # slow should be visible while it is still running rather than at the end.
  defp one(number, runs) do
    request = Enum.at(@requests, rem(number - 1, length(@requests)))
    result = Steward.assay(request)

    IO.puts("  #{number}/#{runs} #{Enum.join(request.bridges, " / ")}: #{said(result)}")

    result
  end

  defp said({:ok, verdict}) do
    "#{verdict.closeness} " <>
      "(#{verdict.meta.forward}/#{verdict.meta.reverse}) in #{verdict.meta.latency_ms} ms"
  end

  defp said({:error, reason}), do: "no verdict — #{inspect(reason)}"

  defp report(measured) do
    met? = measured.p95 <= @target_ms

    IO.puts("""

    Assayer round trip, #{measured.runs} grades, #{measured.failures} without a verdict
      p50 #{measured.p50} ms
      p95 #{measured.p95} ms   (target #{@target_ms} ms: #{if met?, do: "MET", else: "MISSED"})
      max #{measured.max} ms
      spent $#{Float.round(measured.cost_usd, 4)}
    """)

    Map.put(measured, :met?, met?)
  end

  @author_target_ms 5_000

  @author_requests [
    %{
      gives: [
        %{name: "Melissa", text: "coastal lighthouse in storm"},
        %{name: "Jacob", text: "old library with rolling ladders"},
        %{name: "Ada", text: "artisan glassblowing workshop"},
        %{name: "Sam", text: "mountain observatory at dusk"}
      ]
    },
    %{
      gives: [
        %{name: "Melissa", text: "candlelit cathedral"},
        %{name: "Jacob", text: "cyberpunk nightclub"},
        %{name: "Ada", text: "deep sea trench"},
        %{name: "Sam", text: "vintage bookstore in autumn"}
      ]
    }
  ]

  @doc """
  Measures the Author writing Bookends from four Gives.
  """
  @spec measure_author(keyword()) :: %{
          p50: non_neg_integer(),
          p95: non_neg_integer(),
          met?: boolean()
        }
  def measure_author(opts \\ []) do
    runs = Keyword.get(opts, :runs, 10)
    benchmark(runs, &one_author/2, &report_author/1)
  end

  defp benchmark(runs, runner, reporter) do
    {:ok, _started} = Application.ensure_all_started(:thereish)

    results = Enum.map(1..runs, &runner.(&1, runs))
    successful = Enum.filter(results, &match?({:ok, _item}, &1))
    latencies = for {:ok, item} <- successful, do: item.meta.latency_ms

    reporter.(%{
      runs: runs,
      failures: runs - length(successful),
      p50: percentile(latencies, 50),
      p95: percentile(latencies, 95),
      max: Enum.max(latencies, fn -> 0 end),
      cost_usd: Enum.sum(for {:ok, item} <- successful, do: item.meta.cost_usd)
    })
  end

  defp one_author(number, runs) do
    request = Enum.at(@author_requests, rem(number - 1, length(@author_requests)))
    result = Steward.author(request)

    IO.puts("  #{number}/#{runs} Author (4 gives): #{said_author(result)}")

    result
  end

  defp said_author({:ok, answer}) do
    "#{Enum.join(answer.bookends, " · ")} in #{answer.meta.latency_ms} ms ($#{Float.round(answer.meta.cost_usd, 5)})"
  end

  defp said_author({:error, reason}), do: "no bookends — #{inspect(reason)}"

  defp report_author(measured) do
    met? = measured.p95 <= @author_target_ms

    IO.puts("""

    Author round trip (4 Gives), #{measured.runs} requests, #{measured.failures} failures
      p50 #{measured.p50} ms
      p95 #{measured.p95} ms   (target #{@author_target_ms} ms: #{if met?, do: "MET", else: "MISSED"})
      max #{measured.max} ms
      spent $#{Float.round(measured.cost_usd, 4)}
    """)

    Map.put(measured, :met?, met?)
  end

  # The nearest-rank percentile, which is the honest one for twenty samples:
  # interpolating between two of twenty measurements invents a number that was
  # never measured.
  defp percentile([], _rank), do: 0

  defp percentile(latencies, rank) do
    sorted = Enum.sort(latencies)
    index = ceil(rank / 100 * length(sorted)) - 1

    Enum.at(sorted, max(index, 0))
  end
end
