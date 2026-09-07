defmodule Mix.Tasks.Foley.ForgeTest do
  use Thereish.DataCase, async: true

  import ExUnit.CaptureIO

  alias Thereish.Foley.Briefs

  @tag :tmp_dir
  test "generates candidates, prints ranking, reasons, paths and spend across all 17 briefs", %{
    tmp_dir: tmp_dir
  } do
    output =
      capture_io(fn ->
        Mix.Tasks.Foley.Forge.run([
          "--candidates",
          "2",
          "--dir",
          tmp_dir
        ])
      end)

    # 17 briefs: 10 original + 7 new
    assert length(Briefs.all()) == 17

    for brief <- Briefs.all() do
      assert File.exists?(Path.join(tmp_dir, "#{brief.key}-1.mp3"))
      assert File.exists?(Path.join(tmp_dir, "#{brief.key}-2.mp3"))
      assert output =~ brief.key
    end

    assert output =~ "Ear Ranking"
    assert output =~ "Total spend"
  end

  @tag :tmp_dir
  test "given a manifest with loop names, copies the seven new winners to fixed names", %{
    tmp_dir: tmp_dir
  } do
    candidates_dir = Path.join(tmp_dir, "candidates")
    dest_dir = Path.join(tmp_dir, "static_audio")
    File.mkdir_p!(candidates_dir)
    File.mkdir_p!(dest_dir)

    new_brief_keys = [
      "house_loop_2",
      "house_loop_3",
      "house_loop_4",
      "house_loop_5",
      "victory_meld",
      "victory_deep_meld",
      "commit_tick"
    ]

    new_briefs = Enum.map(new_brief_keys, &Briefs.get/1)
    assert length(new_briefs) == 7

    # Pre-populate candidate files for the seven new sounds
    for brief <- new_briefs do
      file1 = Path.join(candidates_dir, "#{brief.key}-1.mp3")
      file2 = Path.join(candidates_dir, "#{brief.key}-2.mp3")
      File.write!(file1, "audio-1-for-#{brief.key}")
      File.write!(file2, "audio-2-for-#{brief.key}")
    end

    # Manifest specifying loop names and candidate selections
    manifest = %{
      "house_loop" => %{"name" => "First Light"},
      "house_loop_2" => %{"candidate" => 2, "name" => "Sunlit Drift"},
      "house_loop_3" => %{"candidate" => 1, "name" => "Morning Mist"},
      "house_loop_4" => %{"candidate" => 2, "name" => "Cottage Warmth"},
      "house_loop_5" => %{"candidate" => 1, "name" => "Evening Fire"},
      "victory_meld" => 2,
      "victory_deep_meld" => 1,
      "commit_tick" => 2
    }

    manifest_path = Path.join(tmp_dir, "manifest.json")
    File.write!(manifest_path, Jason.encode!(manifest))

    output =
      capture_io(fn ->
        Mix.Tasks.Foley.Forge.run([
          "--manifest",
          manifest_path,
          "--dir",
          candidates_dir,
          "--dest",
          dest_dir
        ])
      end)

    assert output =~ "7 assets copied"

    for brief <- new_briefs do
      dest_file = Path.join(dest_dir, brief.target_filename)
      assert File.exists?(dest_file)

      chosen_idx =
        if brief.key in ["house_loop_3", "house_loop_5", "victory_deep_meld"], do: 1, else: 2

      assert File.read!(dest_file) == "audio-#{chosen_idx}-for-#{brief.key}"
      assert output =~ brief.target_filename
    end

    # house_loop had only a name, so no candidate file was copied
    refute File.exists?(Path.join(dest_dir, "house-loop.mp3"))
  end

  @tag :tmp_dir
  test "given a full manifest, copies all 17 candidates to static audio directory", %{
    tmp_dir: tmp_dir
  } do
    candidates_dir = Path.join(tmp_dir, "candidates")
    dest_dir = Path.join(tmp_dir, "static_audio")
    File.mkdir_p!(candidates_dir)
    File.mkdir_p!(dest_dir)

    # Pre-populate candidate files for all 17 briefs
    manifest =
      Briefs.all()
      |> Enum.with_index(1)
      |> Map.new(fn {brief, _idx} ->
        file1 = Path.join(candidates_dir, "#{brief.key}-1.mp3")
        file2 = Path.join(candidates_dir, "#{brief.key}-2.mp3")
        File.write!(file1, "audio-1-for-#{brief.key}")
        File.write!(file2, "audio-2-for-#{brief.key}")

        {to_string(brief.key), 2}
      end)

    manifest_path = Path.join(tmp_dir, "manifest.json")
    File.write!(manifest_path, Jason.encode!(manifest))

    output =
      capture_io(fn ->
        Mix.Tasks.Foley.Forge.run([
          "--manifest",
          manifest_path,
          "--dir",
          candidates_dir,
          "--dest",
          dest_dir
        ])
      end)

    assert output =~ "17 assets copied"

    for brief <- Briefs.all() do
      dest_file = Path.join(dest_dir, brief.target_filename)
      assert File.exists?(dest_file)
      assert File.read!(dest_file) == "audio-2-for-#{brief.key}"
      assert output =~ brief.target_filename
    end
  end
end
