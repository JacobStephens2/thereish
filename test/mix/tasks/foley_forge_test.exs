defmodule Mix.Tasks.Foley.ForgeTest do
  use MeaningGame.DataCase, async: true

  import ExUnit.CaptureIO

  alias MeaningGame.Foley.Briefs

  @tag :tmp_dir
  test "generates candidates, prints ranking, reasons, paths and spend", %{tmp_dir: tmp_dir} do
    output =
      capture_io(fn ->
        Mix.Tasks.Foley.Forge.run([
          "--candidates",
          "2",
          "--dir",
          tmp_dir
        ])
      end)

    # 10 briefs
    assert length(Briefs.all()) == 10

    for brief <- Briefs.all() do
      assert File.exists?(Path.join(tmp_dir, "#{brief.key}-1.mp3"))
      assert File.exists?(Path.join(tmp_dir, "#{brief.key}-2.mp3"))
      assert output =~ brief.key
    end

    assert output =~ "Ear Ranking"
    assert output =~ "Total spend"
  end

  @tag :tmp_dir
  test "given a manifest, copies chosen candidates to static audio directory", %{tmp_dir: tmp_dir} do
    candidates_dir = Path.join(tmp_dir, "candidates")
    dest_dir = Path.join(tmp_dir, "static_audio")
    File.mkdir_p!(candidates_dir)
    File.mkdir_p!(dest_dir)

    # Pre-populate candidate files
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

    for brief <- Briefs.all() do
      dest_file = Path.join(dest_dir, brief.target_filename)
      assert File.exists?(dest_file)
      assert File.read!(dest_file) == "audio-2-for-#{brief.key}"
      assert output =~ brief.target_filename
    end
  end
end
