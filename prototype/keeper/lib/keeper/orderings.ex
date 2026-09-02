defmodule Keeper.Orderings do
  @moduledoc "Grade (A,B) and (B,A) in parallel; reconcile by averaging; keep the disagreement visible (design law 12)."

  @doc "fun.(:forward | :reverse) -> {:ok, %{closeness, reasoning, result}} | {:error, why}"
  def grade_both(fun) do
    [f, r] =
      [Task.async(fn -> fun.(:forward) end), Task.async(fn -> fun.(:reverse) end)]
      |> Task.await_many(:infinity)

    with {:ok, fv} <- f, {:ok, rv} <- r do
      {:ok,
       %{
         closeness: round((fv.closeness + rv.closeness) / 2),
         forward: fv.closeness,
         reverse: rv.closeness,
         disagreement: abs(fv.closeness - rv.closeness),
         reasoning: fv.reasoning,
         reasoning_reverse: rv.reasoning,
         results: %{forward: fv[:result], reverse: rv[:result]}
       }}
    end
  end
end
