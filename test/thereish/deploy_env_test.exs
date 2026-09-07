defmodule Thereish.DeployEnvTest do
  use ExUnit.Case, async: true

  @env_sh Path.expand("../../deploy/env.sh", __DIR__)

  test "deploy/env.sh sets REPO to thereish.git" do
    {output, 0} =
      System.cmd("bash", [
        "-c",
        "source \"$1\" && printf '%s' \"$REPO\"",
        "source-env",
        @env_sh
      ])

    assert output == "https://github.com/JacobStephens2/thereish.git"
  end
end
