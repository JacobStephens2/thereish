defmodule ThereishWeb.Presence do
  @moduledoc """
  Tracks connected LiveViews on a Room's topic as either stage or phone.

  The Room process knows nothing of connected screens; Presence does.
  When a stage is present, phone views go quiet during the reveal so
  all eyes at the table look up at the stage screen.
  """
  use Phoenix.Presence,
    otp_app: :thereish,
    pubsub_server: Thereish.PubSub

  alias Thereish.Rooms

  @doc "Tracks a phone view on the Room's topic."
  def track_phone(socket, code) do
    track(self(), Rooms.topic(code), socket.id, %{role: :phone})
  end

  @doc "Tracks a stage view on the Room's topic."
  def track_stage(socket, code) do
    track(self(), Rooms.topic(code), socket.id, %{role: :stage})
  end

  @doc "Returns true if any stage view is currently tracked on the Room's topic."
  def stage_present?(code) when is_binary(code) do
    code
    |> Rooms.topic()
    |> list()
    |> Enum.any?(fn {_key, %{metas: metas}} ->
      Enum.any?(metas, &(&1[:role] == :stage))
    end)
  end
end
