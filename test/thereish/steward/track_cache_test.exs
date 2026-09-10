defmodule Thereish.Steward.TrackCacheTest do
  use Thereish.DataCase, async: false

  alias Thereish.Steward.TrackCache

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

  setup do
    test_dir =
      Path.join(System.tmp_dir!(), "track_cache_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(test_dir)
    Application.put_env(:thereish, :media_dir, test_dir)

    on_exit(fn ->
      Application.delete_env(:thereish, :media_dir)
      File.rm_rf(test_dir)
    end)

    %{media_dir: test_dir}
  end

  defp write_track_file(media_dir, "/media/" <> rel, content) do
    full_path = Path.join(media_dir, rel)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, content)
    full_path
  end

  defp write_track_file(media_dir, path, content) do
    full_path = Path.join(media_dir, path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, content)
    full_path
  end

  describe "get and put" do
    test "returns :miss when key is absent" do
      assert TrackCache.get(["unheard theme", "quiet room"]) == :miss
    end

    test "cache lookup with a missing file returns a miss and removes the row" do
      gives = ["vanished", "tracks"]

      track_attrs = %{
        title: "Vanished Tracks",
        path: "/media/tracks/non-existent-file.mp3",
        duration: 120,
        format: :mp3,
        meta: @meta
      }

      assert {:ok, _} = TrackCache.put(gives, track_attrs)
      assert Thereish.Repo.get_by(TrackCache, key: TrackCache.key(gives)) != nil

      assert TrackCache.get(gives) == :miss
      assert Thereish.Repo.get_by(TrackCache, key: TrackCache.key(gives)) == nil
    end

    test "stores and retrieves a track when file exists on disk", %{media_dir: media_dir} do
      gives = ["lantern", "harbour"]

      track_attrs = %{
        title: "Lantern Harbour",
        path: "/media/tracks/test-lantern-harbour.mp3",
        duration: 180,
        format: :mp3,
        meta: @meta
      }

      write_track_file(media_dir, track_attrs.path, "audio-data")

      assert {:ok, _} = TrackCache.put(gives, track_attrs)

      # Querying in reverse order hits the same cached entry
      assert {:ok, track} = TrackCache.get(["harbour", "lantern"])

      assert track.title == "Lantern Harbour"
      assert track.path == "/media/tracks/test-lantern-harbour.mp3"
      assert track.duration == 180
      assert track.format == :mp3
      assert track.meta == @meta
    end

    test "subsequent put for the same key does not fail or overwrite", %{media_dir: media_dir} do
      gives = ["forest", "mountain"]

      track_attrs = %{
        path: "/media/tracks/forest.mp3",
        duration: 120,
        format: :mp3,
        meta: @meta
      }

      write_track_file(media_dir, track_attrs.path, "audio-data")

      assert {:ok, _} = TrackCache.put(gives, track_attrs)

      different_attrs = %{
        track_attrs
        | path: "/media/tracks/different.mp3"
      }

      assert {:ok, _} = TrackCache.put(gives, different_attrs)

      assert {:ok, track} = TrackCache.get(gives)
      assert track.path == "/media/tracks/forest.mp3"
    end

    test "subsequent put with title updates title on existing untitled row", %{media_dir: media_dir} do
      gives = ["fog", "lighthouse"]

      track_attrs = %{
        path: "/media/tracks/fog.mp3",
        duration: 120,
        format: :mp3,
        meta: @meta
      }

      write_track_file(media_dir, track_attrs.path, "audio-data")

      # Initially stored without title
      assert {:ok, _} = TrackCache.put(gives, track_attrs)
      assert {:ok, initial} = TrackCache.get(gives)
      assert initial.title == nil

      # Later titled by Scribe
      titled_attrs = Map.put(track_attrs, :title, "Beacon in the Mist")
      assert {:ok, _} = TrackCache.put(gives, titled_attrs)

      assert {:ok, updated} = TrackCache.get(gives)
      assert updated.title == "Beacon in the Mist"
      assert updated.path == "/media/tracks/fog.mp3"
    end
  end

  describe "store" do
    test "writes bytes to media directory and inserts cache row" do
      test_dir =
        Path.join(System.tmp_dir!(), "track_cache_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(test_dir)
      on_exit(fn -> File.rm_rf(test_dir) end)

      Application.put_env(:thereish, :media_dir, test_dir)
      on_exit(fn -> Application.delete_env(:thereish, :media_dir) end)

      gives = ["space station", "solitude"]
      bytes = <<255, 251, 144, 100, 42, 42, 42>>

      mureka_result = %{
        title: "Solitude Station",
        bytes: bytes,
        url: "https://cdn.mureka.ai/audio/temp.mp3",
        model: "auto",
        cost_usd: 0.04
      }

      assert {:ok, track} = TrackCache.store(gives, mureka_result)
      assert track.title == "Solitude Station"
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
      assert cached.title == "Solitude Station"
      assert cached.path == track.path
    end
  end

  describe "prune_dangling/0" do
    test "deletes all rows whose files are missing on disk and reports count", %{media_dir: media_dir} do
      # Row 1: missing file
      TrackCache.put(["desert", "mirage"], %{
        title: "Desert Mirage",
        path: "/media/tracks/desert-mirage.mp3",
        duration: 120,
        format: :mp3,
        meta: @meta
      })

      # Row 2: missing file
      TrackCache.put(["ocean", "abyss"], %{
        title: "Ocean Abyss",
        path: "/media/tracks/ocean-abyss.mp3",
        duration: 120,
        format: :mp3,
        meta: @meta
      })

      # Row 3: file exists on disk
      existing_path = "/media/tracks/valid-track.mp3"
      write_track_file(media_dir, existing_path, "audio-bytes")

      TrackCache.put(["forest", "canopy"], %{
        title: "Forest Canopy",
        path: existing_path,
        duration: 120,
        format: :mp3,
        meta: @meta
      })

      assert Thereish.Repo.aggregate(TrackCache, :count) == 3

      assert {:ok, 2} = TrackCache.prune_dangling()

      assert Thereish.Repo.aggregate(TrackCache, :count) == 1
      assert Thereish.Repo.get_by(TrackCache, key: TrackCache.key(["forest", "canopy"])) != nil
      assert Thereish.Repo.get_by(TrackCache, key: TrackCache.key(["desert", "mirage"])) == nil
      assert Thereish.Repo.get_by(TrackCache, key: TrackCache.key(["ocean", "abyss"])) == nil

      # Second run finds nothing dangling
      assert {:ok, 0} = TrackCache.prune_dangling()
    end
  end
end
