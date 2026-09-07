defmodule Thereish.Rooms.NoSuchRoomError do
  @moduledoc """
  A slug that no Room has and none could be opened under.

  `plug_status` makes Phoenix render this as a 404: a mistyped URL should find
  nothing rather than conjure a Room out of whatever was typed.
  """
  defexception [:slug, plug_status: 404]

  @impl true
  def message(%{slug: slug}), do: "no Room at #{inspect(slug)}"
end
