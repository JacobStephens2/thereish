defmodule Thereish.DeployEnvTest do
  use ExUnit.Case, async: true

  @env_sh Path.expand("../../deploy/env.sh", __DIR__)
  @compose_app_yml Path.expand("../../docker-compose.app.yml", __DIR__)
  @deploy_sh Path.expand("../../deploy/deploy.sh", __DIR__)
  @provision_sh Path.expand("../../deploy/provision.sh", __DIR__)

  @bin_deploy Path.expand("../../bin/deploy", __DIR__)

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

  test "bin/deploy verifies socket, database connection, and root page" do
    content = File.read!(@bin_deploy)

    assert content =~ ~s(grep -q 'data-check="socket"')
    assert content =~ ~s(grep -q 'data-check="database" data-status="connected"')
    assert content =~ ~s(curl -fs --max-time 5 "https://${HOST}/")
  end

  test "bin/deploy warns when the Limner's Recraft key is missing" do
    content = File.read!(@bin_deploy)

    assert content =~ "RECRAFT_AI_API_KEY"
    assert content =~ "every Seat will wear a colour dot"
  end

  test "deploy/deploy.sh makes the media volume writable by the app user" do
    content = File.read!(@deploy_sh)

    assert content =~ "media"
    assert content =~ "chmod"
  end

  test "deploy/provision.sh chmods the media directory even if it already exists" do
    content = File.read!(@provision_sh)

    assert content =~ ~s(sudo install -d -m 0777 "${APP_DIR}/media")
    assert content =~ ~s(sudo chmod 0777 "${APP_DIR}/media")
  end
end
