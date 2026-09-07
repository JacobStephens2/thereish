defmodule Mix.Tasks.Calibration.Export do
  @moduledoc """
  Exports the labelled fairness taps dataset for calibrating the Assayer (ADR-0005, ticket 11).

  ## Command line options

    * `--room`, `-r` - the slug of the Room to export (default: all rooms)
    * `--format`, `-f` - output format: `json` (default) or `jsonl`
    * `--output`, `-o` - destination file path (defaults to writing to stdout)

  ## Examples

      $ mix calibration.export
      $ mix calibration.export --room couch
      $ mix calibration.export --format jsonl --output calibration.jsonl
  """
  use Mix.Task

  @shortdoc "Exports labelled fairness taps for calibrating the Assayer"

  @switches [room: :string, format: :string, output: :string]
  @aliases [r: :room, f: :format, o: :output]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    slug = opts[:room] || List.first(argv)

    format =
      case opts[:format] do
        "jsonl" -> :jsonl
        _ -> :json
      end

    exported = Thereish.Chronicle.export_calibration(slug, format)

    case opts[:output] do
      nil ->
        Mix.shell().info(exported)

      path ->
        File.write!(path, exported)
        Mix.shell().info("Exported calibration dataset to #{path}")
    end
  end
end
