defmodule Mix.Tasks.Scribe.Sync do
  @moduledoc """
  Synchronises the Scribe: refreshes vendored Vale packages, and writes recaps
  for any closed Pages that have none.

      # Refreshes Vale packages and writes recaps for all rooms
      $ mix scribe.sync

      # Writes recaps for one Room only (by Code)
      $ mix scribe.sync dust
  """
  use Mix.Task

  @shortdoc "Refreshes Vale packages and syncs missing recaps for closed Pages"

  @impl Mix.Task
  def run(args) do
    code = List.first(args)

    if code == nil do
      sync_styles()
    end

    Mix.Task.run("app.start")
    MeaningGame.Scribe.sync(code)
  end

  defp sync_styles do
    config = Path.join(File.cwd!(), "priv/vale/.vale.ini")

    bin =
      System.find_executable("vale") ||
        Mix.raise("`vale` is not on the PATH. It is pinned in mise.toml: run `mise install`.")

    {output, status} = System.cmd(bin, ["sync", "--config", config], stderr_to_stdout: true)

    Mix.shell().info(output)

    if status != 0 do
      Mix.raise("`vale sync` failed (exit #{status})")
    end
  end
end
