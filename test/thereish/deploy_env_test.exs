defmodule Thereish.DeployEnvTest do
  use ExUnit.Case, async: true

  @env_sh Path.expand("../../deploy/env.sh", __DIR__)
  @compose_app_yml Path.expand("../../docker-compose.app.yml", __DIR__)

  test "deploy/env.sh sets REPO to thereish.git" do
    content = File.read!(@env_sh)

    assert content =~ ~s(REPO="https://github.com/JacobStephens2/thereish.git")
    refute content =~ "meaning-game.git"
  end

  test "docker-compose.app.yml mounts the media directory into the container" do
    content = File.read!(@compose_app_yml)

    assert content =~
             ~r/volumes:\s*\n\s*-\s*\.\/media:\/app\/lib\/thereish-[^\/]+\/priv\/static\/media/
  end
end
