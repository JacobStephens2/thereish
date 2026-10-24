defmodule Thereish.Repo.Migrations.AddTheChannelToChronicleAttempts do
  use Ecto.Migration

  # The Nudges spent on an Attempt, the bands its Seats called, and the words
  # they sent at its reveal. Nullable with no default: a Page written before
  # this reads as nothing rather than as a backfilled lie, and the book shows
  # the Attempt the way the table played it (ADR-0003).
  def up do
    alter table(:chronicle_attempts) do
      add :nudges, {:array, :map}
      add :calls, {:array, :map}
      add :reactions, {:array, :map}
    end
  end

  def down do
    alter table(:chronicle_attempts) do
      remove :nudges
      remove :calls
      remove :reactions
    end
  end
end
