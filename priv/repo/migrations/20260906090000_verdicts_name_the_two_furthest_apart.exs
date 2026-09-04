defmodule MeaningGame.Repo.Migrations.VerdictsNameTheTwoFurthestApart do
  use Ecto.Migration

  # The Assayer now reads every Bridge of an Attempt together and answers once
  # (ADR-0010). One of the things it answers with is which two Bridges landed
  # furthest apart, because that is where the next Attempt's Anchors come from:
  # the carry-forward becomes a thing the players are told rather than a thing
  # the game works out behind them, and the book should be able to say it.
  #
  # Additive and nullable. A Verdict the Assayer could not give names no words,
  # and every row written before this was a pair, whose two furthest-apart
  # Bridges were the only two it had.
  def change do
    alter table(:chronicle_verdicts) do
      add :furthest, {:array, :text}
    end
  end
end
