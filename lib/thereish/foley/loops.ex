defmodule Thereish.Foley.Loops do
  @moduledoc """
  Lists the house loops shipped with the game, with their display names and audio paths.
  """

  @loops [
    %{name: "The Porch", path: "/audio/house-loop.mp3"},
    %{name: "Sunlit Drift", path: "/audio/house-loop-2.mp3"},
    %{name: "Morning Breeze", path: "/audio/house-loop-3.mp3"},
    %{name: "Cottage Warmth", path: "/audio/house-loop-4.mp3"},
    %{name: "Open Horizon", path: "/audio/house-loop-5.mp3"}
  ]

  @type loop :: %{name: String.t(), path: String.t()}

  @doc """
  Answers every loop in the manifest as name and path, the existing loop first.
  """
  @spec all() :: [loop()]
  def all, do: @loops

  @doc """
  Picks a house loop at random, excluding the previous loop if one is given.
  """
  @spec pick(loop() | nil) :: loop()
  def pick(previous \\ nil)

  def pick(nil), do: Enum.random(@loops)

  def pick(%{} = previous) do
    candidates =
      Enum.reject(@loops, fn loop ->
        loop.path == previous[:path] or loop.name == previous[:name]
      end)

    Enum.random(candidates)
  end
end
