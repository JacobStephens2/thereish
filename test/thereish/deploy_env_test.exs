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

  test "deploy/deploy.sh owns the media directory as nobody at mode 0755 on every run" do
    lines = command_lines(@deploy_sh)

    assert Enum.any?(lines, &owns_media_as_nobody?(&1, "${ROOT}/media"))
    assert Enum.any?(lines, &modes_media_0755?(&1, "${ROOT}/media"))
    refute Enum.any?(lines, &(&1 =~ "0777"))
  end

  test "deploy/provision.sh owns the media directory as nobody at mode 0755 even if it already exists" do
    lines = command_lines(@provision_sh)

    assert Enum.any?(lines, &owns_media_as_nobody?(&1, "${APP_DIR}/media"))
    assert Enum.any?(lines, &modes_media_0755?(&1, "${APP_DIR}/media"))
    refute Enum.any?(lines, &(&1 =~ "0777"))
  end

  # Command text only. A comment that names nobody and 0755 is not the deploy.
  defp command_lines(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reject(&(&1 =~ ~r/^\s*#/))
    |> Enum.map(&String.replace(&1, ~r/\s+#.*$/, ""))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp owns_media_as_nobody?(line, dir) do
    String.contains?(line, "chown") and String.contains?(line, "nobody") and
      String.contains?(line, dir)
  end

  defp modes_media_0755?(line, dir) do
    String.contains?(line, "chmod") and String.contains?(line, "0755") and
      String.contains?(line, dir)
  end
end
