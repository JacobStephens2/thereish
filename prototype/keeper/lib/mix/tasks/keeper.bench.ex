defmodule Mix.Tasks.Keeper.Bench do
  @shortdoc "PROTOTYPE: Assayer latency + consistency bench, cache off, streaming. --n 20 --label mac [--candidates ...] [--hedge 2] [--fake]"
  @moduledoc @shortdoc
  use Mix.Task

  alias Keeper.{Bench, EvalSet, Stats}

  @switches [n: :integer, label: :string, candidates: :string, fake: :boolean, hedge: :integer, repeats: :integer]
  @latency_item 9
  @repeat_items [1, 7, 9, 18]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")
    Keeper.start()

    n = opts[:n] || 20
    label = opts[:label] || "local"
    hedge = opts[:hedge] || 2
    repeats = opts[:repeats] || 5
    cands = Bench.parse_candidates(opts[:candidates])
    IO.puts("bench #{label}: n=#{n}, hedge=#{hedge}, repeats=#{repeats}, candidates=#{inspect(cands)}; cache OFF, streaming, retries OFF\n")

    per =
      cands
      |> Enum.map(fn c ->
        Task.async(fn ->
          cfg = Bench.cfg(c, opts[:fake])
          item = EvalSet.item(@latency_item)
          warm = Bench.call(cfg, item, :forward, 1)
          latency = for _ <- 1..n, do: Bench.call(cfg, item, :forward, 1)
          hedged = for _ <- 1..n, do: Bench.call(cfg, item, :forward, hedge)

          repeat =
            for id <- @repeat_items do
              it = EvalSet.item(id)
              {id, for(_ <- 1..repeats, do: Bench.call(cfg, it, :forward, 1))}
            end

          ordering =
            for it <- EvalSet.items() do
              [f, r] = Task.await_many([Task.async(fn -> Bench.call(cfg, it, :forward, 1) end), Task.async(fn -> Bench.call(cfg, it, :reverse, 1) end)], :infinity)
              {it.id, f, r}
            end

          {c, %{model: "#{cfg.model} (#{cfg.effort})", warm: warm, latency: latency, hedged: hedged, repeat: repeat, ordering: ordering}}
        end)
      end)
      |> Task.await_many(:infinity)

    report = Enum.map(per, fn {c, r} -> {c, summarize(r)} end)
    md = render(label, n, hedge, repeats, report, per)
    IO.puts("\n" <> md)
    File.mkdir_p!("results")
    File.write!("results/bench-#{label}.md", md)
    raw = Map.new(per, fn {c, r} -> {c, %{r | repeat: Map.new(r.repeat), ordering: Enum.map(r.ordering, fn {id, f, rv} -> %{item: id, forward: f, reverse: rv} end)}} end)
    File.write!("results/bench-#{label}.json", Jason.encode!(%{label: label, n: n, hedge: hedge, report: Map.new(report), raw: raw}, pretty: true))
    IO.puts("wrote results/bench-#{label}.md and .json")
    Keeper.Ledger.summary()
  end

  defp summarize(r) do
    ok = Enum.filter(r.latency, & &1.ok)
    ttfts = Enum.map(ok, & &1.ttft) |> Enum.reject(&is_nil/1)
    totals = Enum.map(ok, & &1.total)
    tps = for x <- ok, x.ttft && x.total > x.ttft, do: x.out / ((x.total - x.ttft) / 1000)
    hok = Enum.filter(r.hedged, & &1.ok)

    ttft_p50 = Stats.percentile(ttfts, 50)
    tps_p50 = Stats.percentile(tps, 50)
    total_p95 = Stats.percentile(totals, 95)
    rule_ms = if ttft_p50 && tps_p50 && tps_p50 > 0, do: ttft_p50 + 60 / tps_p50 * 1000, else: nil

    %{
      model: r.model,
      calls: length(r.latency),
      failures: Enum.count(r.latency, &(!&1.ok)),
      ttft_p50: ttft_p50,
      ttft_p95: Stats.percentile(ttfts, 95),
      total_p50: Stats.percentile(totals, 50),
      total_p95: total_p95,
      out_tokens_mean: Stats.mean(Enum.map(ok, & &1.out)),
      tps_p50: tps_p50,
      rule_ms: rule_ms,
      pass_p50: rule_ms != nil and rule_ms <= 2500,
      pass_p95: total_p95 != nil and total_p95 <= 4000,
      hedged_ttft_p95: Stats.percentile(Enum.map(hok, & &1.ttft) |> Enum.reject(&is_nil/1), 95),
      hedged_total_p50: Stats.percentile(Enum.map(hok, & &1.total), 50),
      hedged_total_p95: Stats.percentile(Enum.map(hok, & &1.total), 95),
      hedged_failures: Enum.count(r.hedged, &(!&1.ok)),
      repeat:
        for {id, calls} <- r.repeat do
          vals = calls |> Enum.filter(& &1.ok) |> Enum.map(& &1.closeness)
          %{item: id, values: vals, identical: length(Enum.uniq(vals)) == 1, range: if(vals == [], do: nil, else: Enum.max(vals) - Enum.min(vals))}
        end,
      ordering:
        (fn ->
           diffs = for {_, f, rv} <- r.ordering, f.ok and rv.ok, do: abs(f.closeness - rv.closeness)
           %{mean_abs: Stats.mean(diffs), max_abs: Enum.max(diffs, fn -> nil end), within5_pct: if(diffs == [], do: nil, else: Enum.count(diffs, &(&1 <= 5)) / length(diffs) * 100), n: length(diffs)}
         end).(),
      cost: Enum.sum(for x <- r.latency ++ r.hedged ++ Enum.flat_map(r.repeat, &elem(&1, 1)) ++ Enum.flat_map(r.ordering, fn {_, f, rv} -> [f, rv] end), x.ok, do: x.cost)
    }
  end

  defp render(label, n, hedge, repeats, report, per) do
    f = &Bench.fmt/1
    pf = fn b -> if b, do: "PASS", else: "FAIL" end

    latency =
      [
        "### Latency (#{label}, n=#{n} sequential calls per candidate, item #{@latency_item}, cache off)",
        "",
        "| candidate | model | ttft p50 | ttft p95 | total p50 | total p95 | out tok | tok/s p50 | ttft+60/tps | p50 rule ≤2.5s | p95 rule ≤4s | failures |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|"
      ] ++
        for {c, s} <- report do
          "| #{c} | #{s.model} | #{f.(s.ttft_p50)} | #{f.(s.ttft_p95)} | #{f.(s.total_p50)} | #{f.(s.total_p95)} | #{f.(s.out_tokens_mean)} | #{f.(s.tps_p50)} | #{f.(s.rule_ms)} | #{pf.(s.pass_p50)} | #{pf.(s.pass_p95)} | #{s.failures}/#{s.calls} |"
        end

    hedged =
      [
        "",
        "### Hedging (#{hedge} identical requests to one model, first wins; n=#{n})",
        "",
        "| candidate | unhedged total p95 | hedged total p95 | unhedged total p50 | hedged total p50 | unhedged ttft p95 | hedged ttft p95 | hedged failures |",
        "|---|---|---|---|---|---|---|---|"
      ] ++
        for {c, s} <- report do
          "| #{c} | #{f.(s.total_p95)} | #{f.(s.hedged_total_p95)} | #{f.(s.total_p50)} | #{f.(s.hedged_total_p50)} | #{f.(s.ttft_p95)} | #{f.(s.hedged_ttft_p95)} | #{s.hedged_failures} |"
        end

    repeat =
      [
        "",
        "### Repeat agreement (same submission ×#{repeats}, cache off)",
        "",
        "| candidate | item | closeness values | identical | range ≤ 5 |",
        "|---|---|---|---|---|"
      ] ++
        for {c, s} <- report, rp <- s.repeat do
          "| #{c} | #{rp.item} | #{Enum.join(rp.values, ", ")} | #{rp.identical} | #{rp.range != nil and rp.range <= 5} (range #{f.(rp.range)}) |"
        end

    ordering =
      [
        "",
        "### Ordering agreement ((A,B) vs (B,A) over the #{length(EvalSet.items())}-item set)",
        "",
        "| candidate | mean abs diff | max abs diff | within 5 | graded pairs |",
        "|---|---|---|---|---|"
      ] ++
        for {c, s} <- report do
          "| #{c} | #{f.(s.ordering.mean_abs)} | #{f.(s.ordering.max_abs)} | #{f.(s.ordering.within5_pct)}% | #{s.ordering.n} |"
        end

    warm = ["", "Warm-up call (discarded): " <> Enum.map_join(per, "; ", fn {c, r} -> "#{c} ttft=#{f.(r.warm[:ttft])} total=#{f.(r.warm[:total])}" end)]
    cost = ["", "Bench spend: " <> Enum.map_join(report, "; ", fn {c, s} -> "#{c} $#{Keeper.Ledger.usd(s.cost)}" end)]

    Enum.join(latency ++ hedged ++ repeat ++ ordering ++ warm ++ cost, "\n")
  end
end
