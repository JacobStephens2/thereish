defmodule Mix.Tasks.Scribe.Sync do
  @moduledoc """
  Synchronises the Scribe: refreshes vendored Vale packages, and writes recaps
  for any closed Pages that have none.

      # Refresh styles (if vale is present) and write recaps for all rooms
      $ mix scribe.sync

      # Write recaps for a specific room only
      $ mix scribe.sync dust

      # Only refresh Vale packages
      $ mix scribe.sync --styles

      # Only write recaps
      $ mix scribe.sync --recaps [ROOM_SLUG]
  """
  use Mix.Task

  @shortdoc "Refreshes Vale packages and syncs missing recaps for closed Pages"

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        switches: [styles: :boolean, recaps: :boolean],
        aliases: [s: :styles, r: :recaps]
      )

    styles_only? = Keyword.get(opts, :styles, false)
    recaps_only? = Keyword.get(opts, :recaps, false)
    room_slug = List.first(rest)

    cond do
      styles_only? ->
        sync_styles()

      recaps_only? or room_slug != nil ->
        sync_recaps(room_slug)

      true ->
        if System.find_executable("vale") do
          sync_styles()
        end

        sync_recaps(nil)
    end
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

  defp sync_recaps(room_slug) do
    Mix.Task.run("app.start")
    MeaningGame.Scribe.sync(room_slug)
  end
end
