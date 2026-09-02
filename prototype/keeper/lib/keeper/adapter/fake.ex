defmodule Keeper.Adapter.Fake do
  @moduledoc "Deterministic stand-in so every task runs without keys. Same inputs, same output, always."
  @behaviour Keeper.Adapter

  @impl true
  def complete(req, _opts \\ []) do
    Process.sleep(20)
    t0 = System.monotonic_time(:millisecond)
    text = req |> fake_json() |> Jason.encode!()

    st = %{
      text: [text],
      usage: %{input_tokens: div(byte_size(req.user), 4), output_tokens: div(byte_size(text), 4)},
      model: "fake",
      stop_reason: "end_turn",
      ttft_ms: 7,
      total_ms: System.monotonic_time(:millisecond) - t0 + 20,
      fake: true
    }

    {:ok, Keeper.Adapter.finish(req, st)}
  end

  defp fake_json(%{role: :assayer, user: user}) do
    words = Regex.scan(~r/bridged with: (\S+)/, user) |> Enum.map(fn [_, w] -> w end) |> Enum.sort()
    h = :erlang.phash2(words, 101)
    %{"reasoning" => "Fake assay of #{Enum.join(words, " and ")}: a hash, not a judgment.", "closeness" => h}
  end

  defp fake_json(%{role: :author, kind: :clover}) do
    clover = fn words, decoy ->
      pairs =
        words
        |> Enum.with_index()
        |> Enum.map(fn {w, i} ->
          w2 = Enum.at(words, rem(i + 1, 4))
          clue = String.slice(w2, -3, 3) <> String.slice(w, 0, 2) <> "ish"
          %{"clue" => clue, "bridge" => "fake bridge between #{w} and #{w2}"}
        end)

      %{"words" => words, "pairs" => pairs, "decoy" => %{"word" => decoy, "targets_pair" => 1, "why_it_tempts" => "fake", "why_the_bridge_excludes_it" => "fake"}}
    end

    %{
      "theme" => "fake theme",
      "clovers" => %{
        "A" => clover.(["lantern", "harbour", "anchor", "whistle"], "beacon"),
        "B" => clover.(["orchard", "ribbon", "compass", "marble"], "feather")
      }
    }
  end

  defp fake_json(%{role: :author, kind: :mindmeld}) do
    %{"theme" => "fake theme", "anchors" => ["ocean", "night"], "likely_bridges" => ["moon", "tide", "deep"], "why_these" => "fake"}
  end

  defp fake_json(%{role: :scribe}), do: %{"recap" => "Last time, the fake Scribe wrote this sentence."}
  defp fake_json(_), do: %{"ok" => true}
end
