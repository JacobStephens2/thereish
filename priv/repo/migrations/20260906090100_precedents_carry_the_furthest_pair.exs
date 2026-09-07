defmodule Thereish.Repo.Migrations.PrecedentsCarryTheFurthestPair do
  use Ecto.Migration

  # A precedent is what the players were shown, returned unchanged when the same
  # words meet again (design law 1, ADR-0006). Now that what they were shown
  # includes which two Bridges landed furthest apart — and now that those two
  # words are the next Attempt's Anchors — a cache hit that did not carry them
  # would replay the grade but not the game.
  #
  # Additive and nullable, like the Chronicle's. The prompt version bumps in the
  # same change, so no row written before this is ever read again.
  def change do
    alter table(:precedents) do
      add :furthest, {:array, :text}
    end
  end
end
