defmodule Thereish.Repo.Migrations.CreateTheFairnessTaps do
  use Ecto.Migration

  # At the reveal, each player can tap fair, too kind, or too harsh, without
  # interrupting play. Those taps accumulate into a labelled set that Jacob can
  # export to calibrate the live Assayer (ADR-0005, ticket 11).
  #
  # Append-only event table (ADR-0003, design law 5): no updated_at.
  def change do
    create table(:chronicle_fairness_taps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :restrict), null: false
      add :page_id, references(:chronicle_pages, type: :binary_id, on_delete: :restrict)
      add :seat_id, references(:seats, type: :binary_id, on_delete: :restrict), null: false

      add :attempt_number, :integer, null: false
      add :anchors, {:array, :text}, null: false
      add :bridges, {:array, :text}, null: false
      add :closeness, :integer
      add :band, :text
      add :model, :text
      add :prompt_version, :text
      add :label, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_fairness_taps, [:room_id])
    create index(:chronicle_fairness_taps, [:seat_id])
    create index(:chronicle_fairness_taps, [:page_id])
  end
end
