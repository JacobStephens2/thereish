defmodule MeaningGame.Steward.TrackCacheTest do
  use MeaningGame.DataCase, async: false

  alias MeaningGame.Steward.TrackCache

  @meta %{
    "provider" => "mureka",
    "model" => "auto",
    "cost_usd" => 0.04,
    "latency_ms" => 1250
  }

  describe "normalization" do
    test "downcases, trims, collapses whitespace, and applies NFC" do
      assert TrackCache.normalize_give("  Summer  Camp  ") == "summer camp"
      assert TrackCache.normalize_give("VIKING \t\n BEACHES") == "viking beaches"
      # Decomposed cafe (e + combining acute accent) normalizes to composed NFC
      assert TrackCache.normalize_give("cafe\u0301") == "café"
      assert TrackCache.normalize_give("  Café  ") == "café"
    end

    test "normalizes and sorts gives alphabetically" do
      gives = ["Viking Beaches", "summer camp", "  Alps "]
      assert TrackCache.normalize_gives(gives) == ["alps", "summer camp", "viking beaches"]
    end
  end

  describe "cache key" do
    test "order of gives does not fork a key" do
      k1 = TrackCache.key(["summer camp", "viking beaches"])
      k2 = TrackCache.key(["viking beaches", "summer camp"])
      assert k1 == k2
    end

    test "surface whitespace and casing do not fork a key" do
      k1 = TrackCache.key(["summer camp", "viking beaches"])
      k2 = TrackCache.key([" SUMMER   CAMP\n", "  Viking beaches  "])
      assert k1 == k2
    end
  end

  describe "get and put" do
    test "returns :miss when key is absent" do
      assert TrackCache.get(["unheard theme", "quiet room"]) == :miss
    end

    test "stores and retrieves a track with path, duration, format and meta" do
      gives = ["lantern", "harbour"]

      track_attrs = %{
        path: "/media/tracks/test-lantern-harbour.mp3",
        duration: 180,
        format: :mp3,
        meta: @meta
      }

      assert {:ok, _} = TrackCache.put(gives, track_attrs)

      # Querying in reverse order hits the same cached entry
      assert {:ok, track} = TrackCache.get(["harbour", "lantern"])

      assert track.path == "/media/tracks/test-lantern-harbour.mp3"
      assert track.duration == 180
      assert track.format == :mp3
      assert track.meta == @meta
    end

    test "subsequent put for the same key does not fail or overwrite" do
      gives = ["forest", "mountain"]

      track_attrs = %{
        path: "/media/tracks/forest.mp3",
        duration: 120,
        format: :mp3,
        meta: @meta
      }

      assert {:ok, _} = TrackCache.put(gives, track_attrs)

      different_attrs = %{
        track_attrs
        | path: "/media/tracks/different.mp3"
      }

      assert {:ok, _} = TrackCache.put(gives, different_attrs)

      assert {:ok, track} = TrackCache.get(gives)
      assert track.path == "/media/tracks/forest.mp3"
    end
  end

  describe "store" do
    test "writes bytes to media directory and inserts cache row" do
      test_dir =
        Path.join(System.tmp_dir!(), "track_cache_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(test_dir)
      on_exit(fn -> File.rm_rf(test_dir) end)

      Application.put_env(:meaning_game, :media_dir, test_dir)
      on_exit(fn -> Application.delete_env(:meaning_game, :media_dir) end)

      gives = ["space station", "solitude"]
      bytes = <<255, 251, 144, 100, 42, 42, 42>>

      mureka_result = %{
        bytes: bytes,
        url: "https://cdn.mureka.ai/audio/temp.mp3",
        model: "auto",
        cost_usd: 0.04
      }

      assert {:ok, track} = TrackCache.store(gives, mureka_result)
      assert String.starts_with?(track.path, "/media/tracks/")
      assert track.format == :mp3
      assert track.meta.provider == "mureka"
      assert track.meta.cost_usd == 0.04

      # Verify file was written on disk
      filename = Path.basename(track.path)
      disk_path = Path.join([test_dir, "tracks", filename])
      assert File.exists?(disk_path)
      assert File.read!(disk_path) == bytes

      # Verify subsequent get hits cache without needing provider
      assert {:ok, cached} = TrackCache.get(gives)
      assert cached.path == track.path
    end
  end
end
