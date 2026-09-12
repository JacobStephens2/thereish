defmodule Thereish.Repo.Migrations.DropPartnerIdFromSeats do
  use Ecto.Migration

  def change do
    drop_if_exists index(:seats, [:partner_id])

    alter table(:seats) do
      remove :partner_id
    end
  end
end
