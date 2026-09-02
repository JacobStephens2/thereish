defmodule Keeper.Hedge do
  @moduledoc "Fire N identical requests at one model, take the first reply, kill the rest. Never races different models (design law 11)."

  def race(n, fun) when n <= 1, do: fun.()

  def race(n, fun) do
    tasks = for _ <- 1..n, do: Task.async(fun)
    refs = Map.new(tasks, &{&1.ref, &1})

    {winner, result} =
      receive do
        {ref, result} when is_map_key(refs, ref) ->
          Process.demonitor(ref, [:flush])
          {Map.fetch!(refs, ref), result}
      end

    for t <- tasks, t != winner, do: Task.shutdown(t, :brutal_kill)
    result
  end
end
