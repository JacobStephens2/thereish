defmodule Mix.Tasks.Keeper.Assay do
  @shortdoc "PROTOTYPE: run the 20-item Mind-Meld set through every Assayer candidate. [--candidates glm,sonnet,opus,luna] [--fake] [--hedge N] [--cache] [--persist]"
  @moduledoc @shortdoc
  use Mix.Task

  alias Keeper.{Bench, EvalSet}

  @switches [candidates: :string, fake: :boolean, hedge: :integer, cache: :boolean, persist: :boolean]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")
    Keeper.start(persist: opts[:persist])

    cands = Bench.parse_candidates(opts[:candidates])
    items = EvalSet.items()
    use_cache = opts[:cache] || false

    IO.puts("Assaying #{length(items)} submissions with #{inspect(cands)}; cache #{if use_cache, do: "ON", else: "OFF"}; hedge #{opts[:hedge] || 1}\n")

    results =
      cands
      |> Enum.map(fn c ->
        Task.async(fn ->
          verdicts =
            for item <- items do
              case Keeper.assay(EvalSet.page(item), EvalSet.submission(item), candidate: c, fake: opts[:fake], cache: use_cache, hedge: opts[:hedge] || 1) do
                {:ok, v} -> {item.id, v}
                {:error, why} -> {item.id, %{"error" => inspect(why)}}
              end
            end

          {c, Map.new(verdicts)}
        end)
      end)
      |> Task.await_many(:infinity)
      |> Map.new()

    print_table(items, cands, results)
    print_reasoning(items, cands, results)
    print_ordering(cands, results)
    Keeper.Ledger.summary()
  end

  defp cell(%{"closeness" => c, "forward" => f, "reverse" => r, "cached" => cached}), do: "#{c}#{if cached, do: "†", else: ""} (#{f}/#{r})"
  defp cell(%{"error" => _}), do: "ERR"

  defp print_table(items, cands, results) do
    IO.puts("| # | anchors | A / B | expected | " <> Enum.map_join(cands, " | ", &to_string/1) <> " |")
    IO.puts("|---|---|---|---|" <> String.duplicate("---|", length(cands)))

    for item <- items do
      cells = Enum.map_join(cands, " | ", fn c -> cell(results[c][item.id]) end)
      IO.puts("| #{item.id} | #{Enum.join(item.anchors, "+")} | #{item.a} / #{item.b} | #{item.expect} | #{cells} |")
    end

    IO.puts("\ncells: reconciled closeness (forward/reverse); † = served from cache")
  end

  defp print_reasoning(items, cands, results) do
    IO.puts("\n## Reasoning (forward ordering)\n")

    for item <- items do
      IO.puts("**#{item.id}. #{Enum.join(item.anchors, " + ")}: #{item.a} / #{item.b}**")
      for c <- cands, do: IO.puts("- #{c}: #{results[c][item.id]["reasoning"] || results[c][item.id]["error"]}")
      IO.puts("")
    end
  end

  defp print_ordering(cands, results) do
    IO.puts("## Ordering agreement (|forward - reverse| per item)\n")
    IO.puts("| candidate | mean | max | within 5 | melded (≥75) | errors |")
    IO.puts("|---|---|---|---|---|---|")

    for c <- cands do
      vs = results[c] |> Map.values() |> Enum.reject(&Map.has_key?(&1, "error"))
      diffs = Enum.map(vs, &abs(&1["forward"] - &1["reverse"]))
      errors = results[c] |> Map.values() |> Enum.count(&Map.has_key?(&1, "error"))
      within = if diffs == [], do: 0, else: Enum.count(diffs, &(&1 <= 5)) / length(diffs) * 100
      IO.puts("| #{c} | #{Bench.fmt(Keeper.Stats.mean(diffs))} | #{Enum.max(diffs, fn -> 0 end)} | #{Bench.fmt(within)}% | #{Enum.count(vs, & &1["melded"])} | #{errors} |")
    end
  end
end
