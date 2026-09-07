defmodule Mix.Tasks.Foley.Forge do
  @moduledoc """
  Generates, ranks, and commits the game's static audio assets.

  Usage:
      # Step 1: Generate N candidates per brief, rank them with Gemini, and print file paths
      mix foley.forge [--candidates 4] [--dir .scratch/foley/candidates]

      # Step 2: Given a manifest of chosen indices, copy winners to priv/static/audio
      mix foley.forge --manifest manifest.json [--dir .scratch/foley/candidates] [--dest priv/static/audio]
  """

  use Mix.Task

  alias Thereish.Foley.Briefs
  alias Thereish.Steward

  @shortdoc "Generates and ranks Foley audio assets, or copies chosen assets from a manifest"

  @switches [
    candidates: :integer,
    manifest: :string,
    dir: :string,
    dest: :string,
    only: :string
  ]

  @aliases [
    n: :candidates,
    m: :manifest,
    d: :dir,
    o: :only
  ]

  @default_dir ".scratch/foley/candidates"
  @default_dest "priv/static/audio"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _errors} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    dir = Keyword.get(opts, :dir, @default_dir)
    dest = Keyword.get(opts, :dest, @default_dest)
    manifest_path = Keyword.get(opts, :manifest)

    if manifest_path do
      copy_manifest(manifest_path, dir, dest)
    else
      n = Keyword.get(opts, :candidates, 4)
      only = Keyword.get(opts, :only)
      forge_all(n, dir, only)
    end
  end

  defp forge_all(n, dir, only) do
    File.mkdir_p!(dir)

    briefs =
      if only do
        case Briefs.get(only) do
          nil -> Mix.raise("Unknown brief: #{only}")
          brief -> [brief]
        end
      else
        Briefs.all()
      end

    Mix.shell().info(
      "=== Foley Forge: Generating #{n} candidates for #{length(briefs)} briefs ==="
    )

    Mix.shell().info("Output directory: #{dir}\n")

    {total_spend, _results} =
      Enum.reduce(briefs, {0.0, []}, fn brief, {acc_spend, acc_results} ->
        Mix.shell().info("--> Generating: #{brief.name} (#{brief.key}) [#{brief.kind}]")

        candidates =
          case Steward.forge(brief, n: n, kind: brief.kind) do
            {:ok, res} ->
              res

            {:error, reason} ->
              Mix.raise("Failed generating candidates for #{brief.key}: #{inspect(reason)}")
          end

        paths_with_indices =
          Enum.map(Enum.with_index(candidates, 1), fn {candidate, index} ->
            path = Path.join(dir, "#{brief.key}-#{index}.mp3")
            File.write!(path, candidate.bytes)
            {index, path, candidate}
          end)

        ranking =
          case Steward.rank(candidates, brief) do
            {:ok, res} ->
              res

            {:error, reason} ->
              Mix.raise("Failed ranking candidates for #{brief.key}: #{inspect(reason)}")
          end

        gen_spend = Enum.sum(Enum.map(candidates, &(&1.meta[:cost_usd] || 0.0)))

        ear_spend =
          case ranking do
            [%{meta: %{cost_usd: c}} | _] -> c || 0.0
            _ -> 0.0
          end

        brief_spend = gen_spend + ear_spend

        Mix.shell().info("    Candidates written:")

        Enum.each(paths_with_indices, fn {idx, path, _} ->
          Mix.shell().info("      [#{idx}] #{path}")
        end)

        Mix.shell().info("    Ear Ranking:")

        Enum.each(Enum.with_index(ranking, 1), fn {item, rank_pos} ->
          Mix.shell().info("      #{rank_pos}. [Candidate #{item.index}] #{item.reason}")
        end)

        Mix.shell().info(
          "    Brief spend: $#{:erlang.float_to_binary(brief_spend, decimals: 4)}\n"
        )

        {acc_spend + brief_spend, [{brief, paths_with_indices, ranking} | acc_results]}
      end)

    Mix.shell().info("=== Generation Complete ===")
    Mix.shell().info("Total spend: $#{:erlang.float_to_binary(total_spend, decimals: 4)}")

    Mix.shell().info("""

    To select winners:
    1. Listen to the candidates in #{dir}.
    2. Create a manifest JSON (e.g. manifest.json) mapping brief keys to chosen candidate index:
       {
         "beat": 1,
         "sting_miss": 2,
         ...
       }
    3. Run: mix foley.forge --manifest manifest.json
    """)
  end

  defp copy_manifest(manifest_path, dir, dest) do
    manifest = read_manifest!(manifest_path)
    File.mkdir_p!(dest)
    briefs = Briefs.all()

    Mix.shell().info("=== Copying Foley Assets from Manifest: #{manifest_path} ===")
    Mix.shell().info("Destination: #{dest}\n")

    copied =
      Enum.flat_map(briefs, fn brief ->
        case lookup_chosen(manifest, brief) do
          nil ->
            []

          chosen_idx ->
            src_file = Path.join(dir, "#{brief.key}-#{chosen_idx}.mp3")

            unless File.exists?(src_file) do
              Mix.raise(
                "Candidate file not found: #{src_file}. Run mix foley.forge first to generate candidates."
              )
            end

            dest_file = Path.join(dest, brief.target_filename)
            File.cp!(src_file, dest_file)
            Mix.shell().info("  Copied #{Path.basename(src_file)} -> #{brief.target_filename}")
            [brief]
        end
      end)

    Mix.shell().info("\n#{length(copied)} assets copied to #{dest}.")
  end

  defp read_manifest!(path) do
    path |> File.read!() |> Jason.decode!()
  end

  defp lookup_chosen(manifest, brief) do
    case manifest[to_string(brief.key)] do
      idx when is_integer(idx) -> idx
      %{"candidate" => idx} when is_integer(idx) -> idx
      _ -> nil
    end
  end
end
