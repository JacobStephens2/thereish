defmodule Mix.Tasks.Scribe.Sync do
  @moduledoc """
  Re-downloads the Vale packages the Scribe's prose gate is built on.

  The packages under `priv/vale/styles` are vendored rather than fetched at
  runtime, so that the gate works on a laptop with no network and inside a
  release image that never had one. This is how they are refreshed, and the diff
  it leaves is the change of opinion — a package that decided something new
  about prose since the last sync will start refusing recaps that used to pass,
  and that is worth reading before it is committed.

  The `Scribe` style itself is this repo's own and is never touched by a sync.

      $ mix scribe.sync
  """
  use Mix.Task

  @shortdoc "Re-downloads the Vale packages behind the Scribe's prose gate"

  @impl Mix.Task
  def run(_args) do
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
