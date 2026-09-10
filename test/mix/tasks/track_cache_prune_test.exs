defmodule Mix.Tasks.TrackCache.PruneTest do
  use Thereish.DataCase, async: false

  alias Thereish.Steward.TrackCache

  @meta %{
    "provider" => "mureka",
    "model" => "auto",
    "cost_usd" => 0.04,
    "latency_ms" => 1250
  }

  setup do
    test_dir =
      Path.join(System.tmp_dir!(), "track_cache_prune_task_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(test_dir)
    Application.put_env(:thereish, :media_dir, test_dir)

    on_exit(fn ->
      Application.delete_env(:thereish, :media_dir)
      File.rm_rf(test_dir)
    end)

    %{media_dir: test_dir}
  end

  test "prunes dangling rows and prints the count", %{media_dir: media_dir} do
    # Row 1: dangling (no file)
    TrackCache.put(["desert", "night"], %{
      title: "Desert Night",
      path: "/media/tracks/desert-night.mp3",
      duration: 120,
      format: :mp3,
      meta: @meta
    })

    # Row 2: valid (file exists)
    valid_path = "/media/tracks/valid-track.mp3"
    full_path = Path.join(media_dir, "tracks/valid-track.mp3")
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "audio-bytes")

    TrackCache.put(["mountain", "dawn"], %{
      title: "Mountain Dawn",
      path: valid_path,
      duration: 120,
      format: :mp3,
      meta: @meta
    })

    assert Thereish.Repo.aggregate(TrackCache, :count) == 2

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.TrackCache.Prune.run([])
      end)

    assert output =~ "Pruned 1 dangling track cache row"
    assert Thereish.Repo.aggregate(TrackCache, :count) == 1
    assert Thereish.Repo.get_by(TrackCache, key: TrackCache.key(["mountain", "dawn"])) != nil
    assert Thereish.Repo.get_by(TrackCache, key: TrackCache.key(["desert", "night"])) == nil
  end
end
