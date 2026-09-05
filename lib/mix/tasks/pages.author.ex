defmodule Mix.Tasks.Pages.Author do
  @moduledoc """
  Pre-generates authored Pages against a named Chapter and fills the pool in Postgres.

  ## Command line options

    * `--chapter`, `-c` - the theme or domain to author pages for (required)
    * `--count`, `-n` - number of Pages to author (default: 1)
    * `--give`, `-g` - optional give/hint steer to seed into the prompt

  ## Examples

      $ mix pages.author --chapter "suburban family life" --count 3
      $ mix pages.author -c "the harbour" -n 5
  """
  use Mix.Task

  @shortdoc "Authors Pages ahead of play against a named Chapter"

  @switches [chapter: :string, count: :integer, give: :string]
  @aliases [c: :chapter, n: :count, g: :give]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    chapter = opts[:chapter] || List.first(argv)

    if is_nil(chapter) or String.trim(chapter) == "" do
      Mix.raise(
        "A chapter is required. Example: mix pages.author --chapter \"suburban family life\""
      )
    end

    count = Keyword.get(opts, :count, 1)
    give = Keyword.get(opts, :give)

    Mix.shell().info("Authoring #{count} Page(s) for chapter #{inspect(chapter)}...")

    case MeaningGame.Pages.author_chapter(chapter, count, give: give) do
      {:ok, pages} ->
        Enum.each(pages, fn page ->
          Mix.shell().info("""
          ✓ Page #{page.id}
            Bookends:       #{Enum.join(page.bookends, " + ")}
            Bait:           #{page.bait}
            Deep bridges:   #{Enum.join(page.deep_bridges, ", ")}
            Likely bridges: #{Enum.join(page.likely_bridges, ", ")}
            Model:          #{page.meta[:model] || page.meta["model"]} (cost: $#{:io_lib.format("~.4f", [page.meta[:cost_usd] || page.meta["cost_usd"] || 0.0])})
          """)
        end)

        Mix.shell().info("Successfully added #{length(pages)} Page(s) to the pool.")

      {:error, reason} ->
        Mix.raise("Failed to author pages: #{inspect(reason)}")
    end
  end
end
