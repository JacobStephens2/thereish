defmodule Thereish.Repo.Migrations.EnableCitext do
  use Ecto.Migration

  # No game tables yet. This exists so the migration path itself is exercised on
  # both machines, and because a Seat is found by the name a player typed, which
  # wants case-insensitive comparison rather than a downcased shadow column.
  def up, do: execute("CREATE EXTENSION IF NOT EXISTS citext")

  def down, do: execute("DROP EXTENSION IF EXISTS citext")
end
