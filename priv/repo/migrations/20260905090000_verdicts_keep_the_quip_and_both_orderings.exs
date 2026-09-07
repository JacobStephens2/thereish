defmodule Thereish.Repo.Migrations.VerdictsKeepTheQuipAndBothOrderings do
  use Ecto.Migration

  # A live Assayer grades every pair twice, once in each ordering, because which
  # Bridge is listed first changes the answer, and the Steward prototype caught an
  # 85-point swing from reversing the players (design law 12). The
  # number the couple were shown is the mean of the two, and the two are kept
  # beside it: a wide gap is the most useful thing to know about a grade that
  # looks wrong, and the couple cannot argue with evidence that was thrown away.
  #
  # The quip is the line the reveal was funny with, written about the two words
  # they actually wrote (ADR-0005). It belongs in the record for the same reason
  # the reasoning does — the Chronicle is a book they read, not a metrics table.
  #
  # Every column is nullable: a pair the Assayer could not grade is still a row.
  def change do
    alter table(:chronicle_verdicts) do
      add :quip, :text
      add :forward, :integer
      add :reverse, :integer
      add :reasoning_reverse, :text
    end
  end
end
