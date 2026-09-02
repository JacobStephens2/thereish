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

    # Losers are told to halt their stream on the next chunk (Keeper.HTTP honours :keeper_cancel), which lets
    # Finch close the connection properly. Killing a process mid-stream exhausted the pool on the VPS.
    for t <- tasks, t != winner do
      Process.unlink(t.pid)
      Process.demonitor(t.ref, [:flush])
      send(t.pid, :keeper_cancel)
    end

    result
  end
end
