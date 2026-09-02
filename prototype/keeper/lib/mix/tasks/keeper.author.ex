defmodule Mix.Tasks.Keeper.Author do
  @shortdoc "PROTOTYPE: author one Page. --kind clover|mindmeld --give \"...\" [--author fable|sol|both] [--fake] [--seed N]"
  @moduledoc @shortdoc
  use Mix.Task

  @switches [kind: :string, give: :string, author: :string, fake: :boolean, seed: :integer, digest: :string, persist: :boolean]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")
    Keeper.start(persist: opts[:persist])

    kind = String.to_atom(opts[:kind] || "clover")
    give = opts[:give]
    seed = opts[:seed] || 1
    digest = opts[:digest] || "Nothing yet; this is the first Page."

    arms =
      case opts[:author] do
        "sol" -> [:author_b]
        "both" -> [:author, :author_b]
        _ -> [:author]
      end

    labels = blind_labels(arms, seed)

    for arm <- arms do
      IO.puts("\n=== #{labels[arm]} authoring a #{kind} Page. Give: #{inspect(give)} ===")

      case Keeper.author_page(%{kind: kind, give: give, chronicle_digest: digest}, author: arm, fake: opts[:fake], seed: seed) do
        {:ok, page} -> print_page(labels[arm], page)
        {:error, why, attempts} -> IO.puts("FAILED after #{length(attempts)} attempt(s): #{inspect(why)}")
      end
    end

    Keeper.Ledger.summary()

    if length(arms) == 2 do
      IO.puts("\n(blind key, keep at the very bottom: " <> Enum.map_join(arms, "; ", fn a -> "#{labels[a]} = #{Keeper.Config.role(a).model}" end) <> ")")
    end
  end

  defp blind_labels([arm], _seed), do: %{arm => "Author (#{Keeper.Config.role(arm).model})"}

  defp blind_labels([x, y], seed) do
    case Keeper.AB.assign("author-blind", seed) do
      :a -> %{x => "Author A", y => "Author B"}
      :b -> %{x => "Author B", y => "Author A"}
    end
  end

  def print_page(label, page) do
    meta = page["meta"]
    IO.puts("#{label}: valid Page #{page["id"]} after #{meta["attempts"]} attempt(s); #{meta["wall_ms"]} ms wall; $#{meta["cost_usd"]}; usage #{inspect(meta["usage"])}")
    for r <- meta["rejections"], do: IO.puts("   rejected earlier: #{r}")
    IO.puts("theme: #{page["theme"]}")

    case page["kind"] do
      "clover" ->
        for seat <- ["A", "B"] do
          c = page["clovers"][seat]
          words = Enum.map(c["ring"], fn id -> Enum.find(c["cards"], &(&1["id"] == id))["word"] end)
          IO.puts("\n  clover #{seat}: ring = #{Enum.join(words, " -> ")} -> (back to #{hd(words)})")

          for i <- 0..3 do
            IO.puts("    pair #{i + 1} #{Enum.at(words, i)} / #{Enum.at(words, rem(i + 1, 4))}: clue \"#{Enum.at(c["exemplars"], i)}\"  [#{Enum.at(c["bridges"], i)}]")
          end

          IO.puts("    decoy \"#{c["decoy"]["word"]}\" -> #{c["decoy"]["rationale"]}")
          IO.puts("    shuffled hand: #{Enum.join(c["shuffled"], " ")}")
        end

      "mindmeld" ->
        IO.puts("  anchors: #{Enum.join(page["anchors"], " / ")}")
        IO.puts("  likely bridges: #{Enum.join(page["likely_bridges"], ", ")}")
        IO.puts("  why: #{page["why_these"]}")
    end

    IO.puts("\n  Page JSON (Stage 0 contract):")
    IO.puts(page |> Map.update!("meta", &Map.drop(&1, ["raw_author_json"])) |> Jason.encode!(pretty: true) |> indent())
  end

  defp indent(s), do: s |> String.split("\n") |> Enum.map_join("\n", &("  " <> &1))
end
