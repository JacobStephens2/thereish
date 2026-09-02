defmodule Keeper.Stats do
  @moduledoc "Nearest-rank percentiles and small helpers for the bench."

  def percentile([], _), do: nil

  def percentile(list, p) do
    sorted = Enum.sort(list)
    n = length(sorted)
    idx = max(0, min(n - 1, ceil(p / 100 * n) - 1))
    Enum.at(sorted, idx)
  end

  def mean([]), do: nil
  def mean(list), do: Enum.sum(list) / length(list)
end
