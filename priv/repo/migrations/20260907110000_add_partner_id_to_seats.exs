defmodule Thereish.Repo.Migrations.AddPartnerIdToSeats do
  use Ecto.Migration

  def change do
    alter table(:seats) do
      add :partner_id, references(:seats, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:seats, [:partner_id])
  end
end
