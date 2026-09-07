defmodule Thereish.Repo.Migrations.CreateTheOverrules do
  use Ecto.Migration

  # The couple can jointly overrule any grade, and the overrule is recorded in
  # the Chronicle with both what the machine said and what the couple said
  # (design law 3, ticket 07).
  def change do
    alter table(:chronicle_verdicts) do
      add :overruled, :boolean, default: false, null: false
    end

    create table(:chronicle_overrules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :restrict), null: false
      add :page_id, references(:chronicle_pages, type: :binary_id, on_delete: :restrict)
      add :attempt_number, :integer, null: false

      add :proposer_seat_id, references(:seats, type: :binary_id, on_delete: :restrict),
        null: false

      add :anchors, {:array, :text}, null: false
      add :bridges, {:array, :text}, null: false
      add :machine_closeness, :integer
      add :machine_reasoning, :text
      add :machine_quip, :text
      add :couple_closeness, :integer, null: false
      add :couple_reasoning, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_overrules, [:room_id])
    create index(:chronicle_overrules, [:proposer_seat_id])
  end
end
