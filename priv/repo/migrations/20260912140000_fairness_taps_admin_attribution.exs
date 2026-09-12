defmodule Thereish.Repo.Migrations.FairnessTapsAdminAttribution do
  use Ecto.Migration

  # Retrospective Chronicle opinions reuse fairness taps (ADR-0019). Admin
  # reviews are the same labels with distinct attribution, so a tap may belong
  # to a Seat or to the operator identity, never both.
  def change do
    alter table(:chronicle_fairness_taps) do
      add :source, :text, null: false, default: "participant"
      add :admin_id, references(:admins, type: :binary_id, on_delete: :restrict)
    end

    execute(
      "ALTER TABLE chronicle_fairness_taps ALTER COLUMN seat_id DROP NOT NULL",
      "ALTER TABLE chronicle_fairness_taps ALTER COLUMN seat_id SET NOT NULL"
    )
  end
end
