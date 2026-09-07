# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
alias Thereish.Rooms
alias Thereish.Rooms.Store

# The couch. Rooms are created and never conjured, so the one Room that predates
# the New Room button has to be written down somewhere: without this, a fresh
# database has no Room at all and COUCH opens nothing.
couch = Rooms.default_slug()

case Store.get_room(couch) do
  nil ->
    {:ok, room} = Store.insert_room(couch, Rooms.default_seat_limit())
    IO.puts("Seeded the Room #{String.upcase(room.slug)}")

  _room ->
    IO.puts("The Room #{String.upcase(couch)} is already here")
end
