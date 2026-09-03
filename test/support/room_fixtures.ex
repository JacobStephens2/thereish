defmodule MeaningGame.RoomFixtures do
  @moduledoc """
  Opens a Room of its own for one test.

  Rooms are global — found by slug in a registry — so a test that reused a slug
  would inherit the previous test's Seats even after the sandbox rolled the rows
  back. Every test gets a slug nobody else has, and a Room process the test
  supervisor takes down at the end.
  """

  alias MeaningGame.Rooms
  alias MeaningGame.Rooms.Server

  @doc "Opens a Room with a slug of its own, and returns the slug."
  def open_room(opts \\ []) do
    slug = Keyword.get_lazy(opts, :slug, &unique_slug/0)
    seat_limit = Keyword.get(opts, :seat_limit, Rooms.default_seat_limit())

    ExUnit.Callbacks.start_supervised!(
      Supervisor.child_spec({Server, slug: slug, seat_limit: seat_limit}, id: {Server, slug})
    )

    slug
  end

  @doc "A token standing in for one browser's."
  def device_token, do: "device-#{System.unique_integer([:positive])}"

  defp unique_slug, do: "test-#{System.unique_integer([:positive])}"
end
