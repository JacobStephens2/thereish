defmodule Mix.Tasks.Foley.ListenTest do
  @moduledoc """
  Tests for `mix foley.listen` (ticket 06).
  """
  use Thereish.DataCase, async: false

  alias Mix.Tasks.Foley.Listen

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "foley-listen-test-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{dir: tmp_dir}
  end

  test "renders three labelled beds and writes report without network in test mode", %{dir: dir} do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Listen.run(["--gives", "pine, cold river", "--dir", dir])
      end)

    assert output =~ dir
    assert output =~ "FIRST AUDIBLE LISTEN"
    assert output =~ "Control"
    assert output =~ "Mureka stream"
    assert output =~ "ElevenLabs"

    # Verify audio bed files exist
    control_file = Path.join(dir, "01-control.mp3")
    stream_file = Path.join(dir, "02-mureka-stream.aac")
    eleven_file = Path.join(dir, "03-elevenlabs-30s-loop.mp3")

    assert File.exists?(control_file), "Expected #{control_file} to exist"
    assert File.exists?(stream_file), "Expected #{stream_file} to exist"
    assert File.exists?(eleven_file), "Expected #{eleven_file} to exist"

    assert byte_size(File.read!(control_file)) > 0
    assert byte_size(File.read!(stream_file)) > 0
    assert byte_size(File.read!(eleven_file)) > 0

    # Verify report files exist
    report_txt = Path.join(dir, "report.txt")
    report_json = Path.join(dir, "report.json")

    assert File.exists?(report_txt)
    assert File.exists?(report_json)

    report_data = Jason.decode!(File.read!(report_json))
    assert report_data["gives"] == ["pine", "cold river"]
    assert String.contains?(report_data["prompt"], "pine, cold river")

    beds = report_data["beds"]
    assert Map.has_key?(beds, "control")
    assert Map.has_key?(beds, "mureka_stream")
    assert Map.has_key?(beds, "eleven_loop")

    assert is_number(beds["control"]["time_to_first_audible_ms"])
    assert is_number(beds["mureka_stream"]["time_to_first_audible_ms"])
    assert is_number(beds["eleven_loop"]["time_to_first_audible_ms"])
  end

  test "accepts positional gives arguments", %{dir: dir} do
    ExUnit.CaptureIO.capture_io(fn ->
      Listen.run(["cabin", "blizzard", "--dir", dir])
    end)

    report_json = Path.join(dir, "report.json")
    assert File.exists?(report_json)

    report_data = Jason.decode!(File.read!(report_json))
    assert report_data["gives"] == ["cabin", "blizzard"]
  end
end
