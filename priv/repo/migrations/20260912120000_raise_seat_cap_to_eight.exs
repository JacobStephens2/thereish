defmodule Thereish.Repo.Migrations.RaiseSeatCapToEight do
  use Ecto.Migration

  def up do
    # Rooms created at the previous cap of six, and any smaller Room opened
    # before count-free creation, should take eight so their Codes still work
    # for a larger group. Rooms inserted after this with an explicit smaller
    # limit are left alone.
    execute "UPDATE rooms SET seat_limit = 8 WHERE seat_limit < 8"
  end

  def down do
    execute "UPDATE rooms SET seat_limit = 6 WHERE seat_limit = 8"
  end
end
