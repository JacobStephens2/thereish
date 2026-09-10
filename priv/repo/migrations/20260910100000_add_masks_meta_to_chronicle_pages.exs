defmodule Thereish.Repo.Migrations.AddMasksMetaToChroniclePages do
  use Ecto.Migration

  def change do
    alter table(:chronicle_pages) do
      add :masks_meta, :map
    end
  end
end
