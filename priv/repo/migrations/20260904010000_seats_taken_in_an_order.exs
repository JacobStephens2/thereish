defmodule Thereish.Repo.Migrations.SeatsTakenInAnOrder do
  use Ecto.Migration

  # The order Seats were taken in is the order the roster and the reveal are
  # drawn in, so it has to survive a Room restarting. At second resolution two
  # players joining the same evening usually share a timestamp, and the
  # tie-break was a random UUID — so a crash could reshuffle the couch. Both
  # tables get the finer clock; only `seats` is ordered by it, and rooms follow
  # so that the two tables do not disagree about what a timestamp is.
  def change do
    for table <- [:rooms, :seats], column <- [:inserted_at, :updated_at] do
      alter table(table) do
        modify column, :utc_datetime_usec, from: :utc_datetime
      end
    end
  end
end
