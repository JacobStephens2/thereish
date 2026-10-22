defmodule Thereish.DeployEnvTest do
  use ExUnit.Case, async: true

  @env_sh Path.expand("../../deploy/env.sh", __DIR__)
  @compose_app_yml Path.expand("../../docker-compose.app.yml", __DIR__)
  @deploy_sh Path.expand("../../deploy/deploy.sh", __DIR__)
  @provision_sh Path.expand("../../deploy/provision.sh", __DIR__)
  @proxy_conf Path.expand("../../deploy/apache/proxy.conf", __DIR__)

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

  test "deploy/deploy.sh runs media ownership on the media directory" do
    lines = directive_lines(@deploy_sh)

    assert Enum.any?(lines, &calls_media_ownership?(&1, "${ROOT}/media"))
    refute Enum.any?(lines, &String.contains?(&1, "chown"))
    refute Enum.any?(lines, &(&1 =~ "0777"))
  end

  test "the proxy sets X-Forwarded-For to the browser and drops a value the request already carried" do
    lines = directive_lines(@proxy_conf)

    assert "ProxyAddHeaders Off" in lines
    assert "RequestHeader unset X-Forwarded-For early" in lines
    assert "RequestHeader set X-Forwarded-For expr=%{REMOTE_ADDR}" in lines
    assert "RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}" in lines
    assert Enum.any?(lines, &String.contains?(&1, "upgrade=websocket"))
  end

  test "deploy/provision.sh runs media ownership on the media directory" do
    lines = directive_lines(@provision_sh)

    assert Enum.any?(lines, &calls_media_ownership?(&1, "${APP_DIR}/media"))
    refute Enum.any?(lines, &String.contains?(&1, "chown"))
    refute Enum.any?(lines, &(&1 =~ "0777"))
  end

  # Command text only. A comment that names nobody and 0755 is not the deploy.
  defp directive_lines(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reject(&(&1 =~ ~r/^\s*#/))
    |> Enum.map(&String.replace(&1, ~r/\s+#.*$/, ""))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp calls_media_ownership?(line, dir) do
    String.contains?(line, "ensure_media_ownership") and String.contains?(line, dir)
  end
end
