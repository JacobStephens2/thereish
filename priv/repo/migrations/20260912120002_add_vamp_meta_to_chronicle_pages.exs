defmodule Thereish.Repo.Migrations.AddVampMetaToChroniclePages do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE chronicle_pages ADD COLUMN IF NOT EXISTS vamp_meta jsonb")
  end

  def down do
    execute("ALTER TABLE chronicle_pages DROP COLUMN IF EXISTS vamp_meta")
  end
end
