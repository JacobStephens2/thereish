defmodule Thereish.DeployEnvTest do
  use ExUnit.Case, async: true

  @env_sh Path.expand("../../deploy/env.sh", __DIR__)

  test "deploy/env.sh sets REPO to thereish.git" do
    content = File.read!(@env_sh)

    assert content =~ ~s(REPO="https://github.com/JacobStephens2/thereish.git")
    refute content =~ "meaning-game.git"
  end
end
