defmodule MeaningGameWeb.EndpointTest do
  @moduledoc """
  The one test that boots the endpoint for real: a live Bandit listener, over a
  real TCP socket, rather than `Plug.Test`. Everything else in the suite goes
  through `Phoenix.ConnTest`, which never proves the server starts.
  """
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Application.ensure_all_started(:inets)
    :ok
  end

  test "the endpoint serves the check page over real HTTP" do
    url = String.to_charlist(MeaningGameWeb.Endpoint.url() <> "/check")

    assert {:ok, {{_version, 200, _reason}, _headers, body}} =
             :httpc.request(:get, {url, []}, [], [])

    assert to_string(body) =~ "Socket not connected"
  end
end
