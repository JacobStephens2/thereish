defmodule Keeper.AB do
  @moduledoc "Deterministic arm assignment: the same page id and seed always land in the same arm. Interface only."

  def assign(page_id, seed, arms \\ [:a, :b]), do: Enum.at(arms, :erlang.phash2({page_id, seed}, length(arms)))
end
