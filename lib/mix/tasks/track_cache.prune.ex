defmodule Mix.Tasks.TrackCache.Prune do
  @moduledoc """
  Prunes dangling rows from the track cache table whose audio files do not exist on disk.

  ## Examples

      $ mix track_cache.prune
  """
  use Mix.Task

  @shortdoc "Prunes dangling rows from the track cache"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    {:ok, count} = Thereish.Steward.TrackCache.prune_dangling()

    if count == 1 do
      Mix.shell().info("Pruned 1 dangling track cache row.")
    else
      Mix.shell().info("Pruned #{count} dangling track cache rows.")
    end
  end
end
