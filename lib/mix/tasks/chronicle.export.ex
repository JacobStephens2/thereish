defmodule Mix.Tasks.Chronicle.Export do
  @moduledoc """
  Exports the Chronicle for a Room as Markdown on demand.

  ## Command line options

    * `--room`, `-r` - the slug of the Room to export (defaults to configured `default_room_slug`)
    * `--output`, `-o` - destination file path (defaults to writing to stdout)

  ## Examples

      $ mix chronicle.export
      $ mix chronicle.export --room couch
      $ mix chronicle.export --room couch --output chronicle.md
  """
  use Mix.Task

  @shortdoc "Exports the Chronicle as Markdown on demand"

  @switches [room: :string, output: :string]
  @aliases [r: :room, o: :output]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    slug =
      opts[:room] ||
        List.first(argv) ||
        Thereish.Rooms.default_slug()

    slug =
      case Thereish.Rooms.ensure_started(slug) do
        {:ok, code, _pid} -> code
        {:error, _reason} -> Mix.raise("No Room has the Code #{slug}.")
      end

    markdown = Thereish.Chronicle.to_markdown(slug)

    case opts[:output] do
      nil ->
        Mix.shell().info(markdown)

      path ->
        File.write!(path, markdown)
        Mix.shell().info("Exported Chronicle to #{path}")
    end
  end
end
