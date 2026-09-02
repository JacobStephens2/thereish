defmodule Mix.Tasks.Keeper.Scribe do
  @shortdoc "PROTOTYPE: one \"Last time, ...\" sentence from a canned Page + verdict. [--fake]"
  @moduledoc @shortdoc
  use Mix.Task

  @switches [fake: :boolean]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")
    Keeper.start()

    item = Keeper.EvalSet.item(9)
    page = Map.merge(Keeper.EvalSet.page(item), %{"theme" => "the world St. Thérèse of Lisieux grew up in", "give" => "the world St. Thérèse of Lisieux grew up in"})

    verdict = %{
      "kind" => "mindmeld",
      "anchors" => item.anchors,
      "words" => %{"A" => item.a, "B" => item.b},
      "closeness" => 52,
      "melded" => false,
      "forward" => 55,
      "reverse" => 49,
      "reasoning" => "Both ride the sea-at-night image, but tide is the ocean's motion and moon the night's light: neighbours, not the same word.",
      "attempt" => 1,
      "next_anchors" => [item.a, item.b]
    }

    case Keeper.scribe(page, verdict, fake: opts[:fake]) do
      {:ok, recap} -> IO.puts("\nrecap: #{recap}")
      {:error, why} -> IO.puts("FAILED: #{inspect(why)}")
    end

    Keeper.Ledger.summary()
  end
end
