defmodule Thereish.Repo.Migrations.AddVampMetaToChroniclePages do
  use Ecto.Migration

  def change do
    alter table(:chronicle_pages) do
      add :vamp_meta, :map
    end
  end
end
