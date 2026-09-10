defmodule ThereishWeb.EndpointTest do
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
    url = String.to_charlist(ThereishWeb.Endpoint.url() <> "/check")

    assert {:ok, {{_version, 200, _reason}, _headers, body}} =
             :httpc.request(:get, {url, []}, [], [])

    assert to_string(body) =~ "Socket not connected"
  end

  test "the endpoint serves media tracks over real HTTP" do
    test_dir = Thereish.Steward.TrackCache.media_dir()
    tracks_dir = Path.join(test_dir, "tracks")
    File.mkdir_p!(tracks_dir)
    file_path = Path.join(tracks_dir, "test-serve.mp3")
    File.write!(file_path, "fake mp3 content")

    on_exit(fn -> File.rm(file_path) end)

    url = String.to_charlist(ThereishWeb.Endpoint.url() <> "/media/tracks/test-serve.mp3")

    assert {:ok, {{_version, 200, _reason}, headers, body}} =
             :httpc.request(:get, {url, []}, [], [])

    assert to_string(body) == "fake mp3 content"
    headers_map = Map.new(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
    assert headers_map["content-type"] =~ "audio/mpeg"
  end

  test "the endpoint serves mask files over real HTTP" do
    test_dir = Thereish.Steward.TrackCache.media_dir()
    masks_dir = Path.join(test_dir, "masks")
    File.mkdir_p!(masks_dir)
    file_path = Path.join(masks_dir, "test-serve-mask.png")
    png_bytes = Thereish.Steward.Limner.png("#c4a35a", 32)
    File.write!(file_path, png_bytes)

    on_exit(fn -> File.rm(file_path) end)

    url = String.to_charlist(ThereishWeb.Endpoint.url() <> "/media/masks/test-serve-mask.png")

    assert {:ok, {{_version, 200, _reason}, headers, body}} =
             :httpc.request(:get, {url, []}, [], [])

    assert body == :erlang.binary_to_list(png_bytes)
    headers_map = Map.new(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
    assert headers_map["content-type"] =~ "image/png"
  end
end
