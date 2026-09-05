defmodule MeaningGame.Steward.Vale do
  @moduledoc """
  The Scribe's prose gate: the only thing in this codebase that shells out.

  Design law 14 says never send a model to do a linter's job, and it says it
  about prose specifically — the Steward prototype measured `claude-fable-5-1`
  writing recaps that were valid and too long, which is a fault a linter can
  state in one line and a model will argue about for three. So a recap is run
  through `vale` as Markdown before anybody reads it, and what comes back is
  either nothing or a list of named faults that goes straight back to the model
  as the repair pass (ADR-0009).

  The rules are configuration and not code: `priv/vale/.vale.ini` turns on a
  `Scribe` style of this game's own house rules — no grade restated, no
  exclamation marks, under eighty words, none of the vocabulary that gives a
  model away — alongside proselint, write-good, and Vale's own AiTells package.
  The packages are vendored under `priv/vale/styles` rather than fetched, so the
  gate is the same on a laptop with no network as in a release image that never
  had one.

  Vale's exit code counts errors only, and the gate refuses warnings too, so
  what this reads is the JSON rather than the status. An empty object is clean
  prose.
  """

  require Logger

  @doc """
  Whether one piece of prose is fit to be shown.

  `{:error, why}` names every rule that fired, in Vale's own words, because
  `why` is what the repair pass is handed and a model told "your prose was
  rejected" fixes nothing.

  A Vale that is not installed is not a pass. The gate is part of the role
  (design law 14): with no linter there is no recap, and the Chronicle is
  missing a paragraph rather than carrying one nobody checked.
  """
  @spec check(String.t()) :: :ok | {:error, String.t()}
  def check(text) when is_binary(text) do
    if String.trim(text) == "" do
      {:error, "the prose was blank"}
    else
      lint(text)
    end
  end

  @doc """
  Whether the `vale` binary this gate needs is on the machine.

  Pinned in `mise.toml` and installed into the release image, so a `false` here
  is a deployment that is missing a tool rather than a machine that was never
  meant to have one.
  """
  @spec installed?() :: boolean()
  def installed?, do: executable() != nil

  defp lint(text) do
    case executable() do
      nil ->
        {:error, "the prose gate is not installed on this machine (no `vale` on the PATH)"}

      bin ->
        run(bin, text)
    end
  end

  # Vale lints files, and Elixir cannot hand a command anything on stdin without
  # dropping to a port, so the recap goes to a scratch file with a `.md`
  # extension and is deleted in the same breath. It is the players' words, so
  # `after` rather than a happy path: prose that failed the gate does not get to
  # stay on the disk either.
  defp run(bin, text) do
    path = scratch_file(text)

    try do
      case System.cmd(bin, ["--config", config_path(), "--output=JSON", path],
             stderr_to_stdout: true
           ) do
        {output, status} when status in [0, 1] ->
          verdict(output)

        {output, status} ->
          # Vale exits 2 when it could not run at all — a broken config, a
          # missing style. That is this repo's fault rather than the model's,
          # and prose that was never checked does not pass.
          Logger.error("the prose gate could not run (exit #{status}): #{String.trim(output)}")

          {:error, "the prose gate could not run"}
      end
    after
      File.rm(path)
    end
  rescue
    error ->
      Logger.error("the prose gate could not run: #{Exception.message(error)}")

      {:error, "the prose gate could not run"}
  end

  defp scratch_file(text) do
    name = "scribe-#{System.unique_integer([:positive])}.md"
    path = Path.join(System.tmp_dir!(), name)

    File.write!(path, text)

    path
  end

  defp verdict(output) do
    case Jason.decode(output) do
      {:ok, alerts} when alerts == %{} ->
        :ok

      {:ok, files} when is_map(files) ->
        {:error, files |> Map.values() |> List.flatten() |> faults()}

      _other ->
        {:error, "the prose gate answered with something that was not JSON"}
    end
  end

  # Vale's own message, prefixed by the rule that wrote it. The rule name is
  # what makes the repair pass specific: "Scribe.Length" and "AiTells.Dash" are
  # two different rewrites, and a model handed both at once does both.
  defp faults(alerts) do
    Enum.map_join(alerts, "; ", fn alert ->
      "#{alert["Check"]}: #{alert["Message"]}"
    end)
  end

  defp config_path do
    Application.app_dir(:meaning_game, "priv/vale/.vale.ini")
  end

  defp executable do
    :meaning_game
    |> Application.get_env(:steward, [])
    |> Keyword.get(:vale_bin, "vale")
    |> System.find_executable()
  end
end
