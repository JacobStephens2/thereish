defmodule Keeper do
  @moduledoc """
  PROTOTYPE. The one seam through which the game talks to language models.

      Keeper.author_page(%{kind: :clover | :mindmeld, give: String.t | nil, chronicle_digest: String.t}) -> {:ok, page}
      Keeper.assay(page, submission) -> {:ok, verdict}
      Keeper.scribe(page, verdict) -> {:ok, recap_line}

  Behind it: per-role model config, adapters, the verdict cache, both-orderings grading, hedging,
  schema validation, the clue-legality gate, and A/B arm assignment. Options exist only so the
  prototype's tasks can run experiments (`fake:`, `author:`, `candidate:`, `cache:`, `hedge:`).
  """

  alias Keeper.{Cache, Config, Hedge, Orderings, Pages, Prompts, Schema}

  def start(opts \\ []) do
    Keeper.Ledger.start()
    Cache.start(opts)
    :ok
  end

  # --- Author ----------------------------------------------------------------

  def author_page(%{kind: kind} = spec, opts \\ []) when kind in [:clover, :mindmeld] do
    cfg = pick(opts[:config] || Config.role(opts[:author] || :author), opts)
    req = Prompts.author(kind, spec[:give], spec[:chronicle_digest])

    case Schema.generate(cfg, req, &Pages.validate(kind, &1), 2) do
      {:ok, res, attempts} ->
        page =
          kind
          |> Pages.from_author(res.json, spec[:give], opts[:seed] || 1)
          |> Map.put("meta", %{
            "author" => res.model,
            "prompt_version" => Prompts.version(),
            "attempts" => length(attempts),
            "rejections" => for({:rejected, why, _} <- attempts, do: why),
            "cost_usd" => Float.round(Enum.sum(for {_, r} <- flat(attempts), do: r.cost), 4),
            "wall_ms" => Enum.sum(for {_, r} <- flat(attempts), do: r.timings.total_ms),
            "usage" => res.usage,
            "raw_author_json" => res.json
          })

        {:ok, page}

      {:error, why, attempts} ->
        {:error, why, attempts}
    end
  end

  defp flat(attempts), do: Enum.map(attempts, fn {tag, r} -> {tag, r}; {tag, _why, r} -> {tag, r} end)

  # --- Assayer ---------------------------------------------------------------

  def assay(page, submission, opts \\ [])

  def assay(%{"kind" => "clover"} = page, submission, _opts), do: {:ok, Pages.grade_clover(page, submission)}

  def assay(_page, %{"anchors" => anchors, "words" => %{"A" => wa, "B" => wb}}, opts) do
    cfg = pick(opts[:config] || if(opts[:candidate], do: Config.candidate(opts[:candidate]), else: Config.role(:assayer)), opts)
    use_cache = Keyword.get(opts, :cache, true)
    key = Cache.key(cfg.model, Prompts.version(), :mindmeld, %{anchors: anchors, words: [wa, wb]})

    case if(use_cache, do: Cache.get(key), else: :miss) do
      {:ok, cached} ->
        {:ok, Map.put(cached, "cached", true)}

      :miss ->
        hedge = opts[:hedge] || 1

        grade = fn order ->
          {p1, p2} = if order == :forward, do: {wa, wb}, else: {wb, wa}

          Hedge.race(hedge, fn -> Schema.generate(cfg, Prompts.assay(anchors, p1, p2), &Prompts.check_verdict/1, 2) end)
          |> case do
            {:ok, res, _} -> {:ok, %{closeness: res.json["closeness"], reasoning: res.json["reasoning"], result: res}}
            {:error, why, _} -> {:error, why}
          end
        end

        with {:ok, o} <- Orderings.grade_both(grade) do
          verdict = %{
            "kind" => "mindmeld",
            "closeness" => o.closeness,
            "melded" => o.closeness >= 75,
            "forward" => o.forward,
            "reverse" => o.reverse,
            "words" => %{"A" => wa, "B" => wb},
            "anchors" => anchors,
            "reasoning" => o.reasoning,
            "reasoning_reverse" => o.reasoning_reverse,
            "orderings" => "both orderings graded (#{o.forward} / #{o.reverse})",
            "model" => cfg.model,
            "prompt_version" => Prompts.version(),
            "cached" => false,
            "timings" => %{
              "forward" => %{"ttft_ms" => o.results.forward.timings.ttft_ms, "total_ms" => o.results.forward.timings.total_ms},
              "reverse" => %{"ttft_ms" => o.results.reverse.timings.ttft_ms, "total_ms" => o.results.reverse.timings.total_ms}
            },
            "cost_usd" => o.results.forward.cost + o.results.reverse.cost
          }

          if use_cache, do: Cache.put(key, verdict)
          {:ok, verdict}
        end
    end
  end

  @doc "A joint overrule becomes the precedent: it replaces the cached verdict under the same key (design law 3)."
  def overrule(_page, %{"anchors" => anchors, "words" => %{"A" => wa, "B" => wb}}, verdict, opts \\ []) do
    cfg = pick(Config.role(:assayer), opts)
    key = Cache.key(verdict["model"] || cfg.model, Prompts.version(), :mindmeld, %{anchors: anchors, words: [wa, wb]})

    overruled =
      verdict
      |> Map.merge(%{"closeness" => 100, "melded" => true, "overruled" => true, "reasoning" => "Overruled jointly by both players. Recorded as precedent."})

    {:ok, Cache.put(key, overruled)}
  end

  # --- Scribe ----------------------------------------------------------------

  def scribe(page, verdict, opts \\ []) do
    cfg = pick(opts[:config] || Config.role(:scribe), opts)
    check = fn %{"recap" => r} -> if(is_binary(r) and String.starts_with?(String.trim(r), "Last time"), do: :ok, else: {:error, "recap must start with \"Last time\""}) end

    case Schema.generate(cfg, Prompts.scribe(page, verdict), check, 1) do
      {:ok, res, _} -> {:ok, res.json["recap"]}
      {:error, why, _} -> {:error, why}
    end
  end

  defp pick(cfg, opts), do: if(opts[:fake], do: Config.fake(cfg), else: cfg)
end
