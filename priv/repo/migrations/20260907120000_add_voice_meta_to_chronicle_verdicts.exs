defmodule Thereish.Repo.Migrations.AddVoiceMetaToChronicleVerdicts do
  use Ecto.Migration

  def change do
    alter table(:chronicle_verdicts) do
      add :voice_meta, :map
    end
  end
end
