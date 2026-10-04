defmodule Thereish.Foley.TrackTest do
  @moduledoc """
  A Page's Track has one shape from Foley's result to the Chronicle: a
  `%Track{}`, kept or failed, stored flat through its own type (ticket 201).
  """
  use ExUnit.Case, async: true

  alias Thereish.Foley.Track

  @score %{
    path: "/media/tracks/a.mp3",
    duration: 120,
    format: :mp3,
    meta: %{provider: "fake", model: "fake-music", cost_usd: 0.04, latency_ms: 10}
  }

  @title_meta %{provider: "fake", model: "fake-scribe", cost_usd: 0.0001}

  describe "landed/3" do
    test "a scored Track carries its path, title, and provenance with string keys" do
      track = Track.landed(@score, "Harbour", @title_meta)

      assert track == %Track{
               path: "/media/tracks/a.mp3",
               title: "Harbour",
               failure: nil,
               meta: %{
                 "provider" => "fake",
                 "model" => "fake-music",
                 "cost_usd" => 0.04,
                 "latency_ms" => 10,
                 "title_cost_usd" => 0.0001
               }
             }
    end

    test "a Track with no title yet carries no title cost" do
      track = Track.landed(@score, nil, nil)

      assert track.title == nil
      refute Map.has_key?(track.meta, "title_cost_usd")
    end

    test "a TrackCache hit lands with its stored meta and no title cost known" do
      cached = %{
        title: "Harbour",
        path: "/media/tracks/a.mp3",
        duration: 120,
        format: :mp3,
        meta: %{"provider" => "fake", "model" => "fake-music"}
      }

      track = Track.landed(cached, "Harbour", %{})

      assert track.title == "Harbour"

      assert track.meta == %{
               "provider" => "fake",
               "model" => "fake-music",
               "title_cost_usd" => 0.0
             }
    end
  end

  describe "titled/3" do
    test "adds a title that arrived after the Track, with its cost" do
      track = @score |> Track.landed(nil, nil) |> Track.titled("Harbour", @title_meta)

      assert track == Track.landed(@score, "Harbour", @title_meta)
    end
  end

  describe "failed/1" do
    test "is a failure with the reason as a string and the Foley provenance" do
      assert %Track{path: nil, title: nil, failure: "music_unavailable", meta: meta} =
               Track.failed(:music_unavailable)

      assert meta == %{"provider" => "fake", "model" => "fake-music", "cost_usd" => 0.0}
    end
  end

  describe "kept?/1" do
    test "a landed Track is kept, titled or not" do
      assert Track.kept?(Track.landed(@score, "Harbour", @title_meta))
      assert Track.kept?(Track.landed(@score, nil, nil))
    end

    test "a failure, a Track with no path, and no Track are not kept" do
      refute Track.kept?(Track.failed(:unfinished))
      refute Track.kept?(%Track{path: "", meta: %{}})
      refute Track.kept?(%Track{path: "/media/tracks/a.mp3", failure: "x", meta: %{}})
      refute Track.kept?(nil)
    end
  end

  describe "as an Ecto.Type" do
    test "dumps flat with string keys, omitting nil fields" do
      track = Track.landed(@score, nil, nil)

      assert Ecto.Type.dump(Track, track) ==
               {:ok,
                %{
                  "path" => "/media/tracks/a.mp3",
                  "provider" => "fake",
                  "model" => "fake-music",
                  "cost_usd" => 0.04,
                  "latency_ms" => 10
                }}
    end

    test "a Track and a failure round-trip through dump, JSON and load" do
      for track <- [Track.landed(@score, "Harbour", @title_meta), Track.failed(:unfinished)] do
        assert {:ok, dumped} = Ecto.Type.dump(Track, track)
        json = dumped |> Jason.encode!() |> Jason.decode!()
        assert track |> Jason.encode!() |> Jason.decode!() == json
        assert Ecto.Type.load(Track, json) == {:ok, track}
      end
    end

    test "loads a stored row with string keys" do
      row = %{"path" => "/a.mp3", "title" => "Harbour", "model" => "m", "title_cost_usd" => 0.0}

      assert Ecto.Type.load(Track, row) ==
               {:ok,
                %Track{
                  path: "/a.mp3",
                  title: "Harbour",
                  meta: %{"model" => "m", "title_cost_usd" => 0.0}
                }}
    end

    test "loads a row with atom keys" do
      row = %{path: "/a.mp3", title: "Harbour", model: "m"}

      assert Ecto.Type.load(Track, row) ==
               {:ok, %Track{path: "/a.mp3", title: "Harbour", meta: %{"model" => "m"}}}
    end

    test "loads a row written with every key twice" do
      row = %{:path => "/a.mp3", "path" => "/a.mp3", :model => "m", "model" => "m"}

      assert Ecto.Type.load(Track, row) ==
               {:ok, %Track{path: "/a.mp3", meta: %{"model" => "m"}}}
    end

    test "loads a failure row" do
      row = %{
        "provider" => "mureka",
        "model" => "auto",
        "cost_usd" => 0.0,
        "failure" => "timeout"
      }

      assert Ecto.Type.load(Track, row) ==
               {:ok,
                %Track{
                  failure: "timeout",
                  meta: %{"provider" => "mureka", "model" => "auto", "cost_usd" => 0.0}
                }}
    end

    test "an empty row holds no Track" do
      assert Ecto.Type.load(Track, %{}) == {:ok, nil}
    end

    test "casts only a Track" do
      track = Track.failed(:unfinished)

      assert Ecto.Type.cast(Track, track) == {:ok, track}
      assert Ecto.Type.cast(Track, nil) == {:ok, nil}
      assert Ecto.Type.cast(Track, %{"path" => "/a.mp3"}) == :error
    end
  end
end
