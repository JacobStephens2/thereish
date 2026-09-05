defmodule Mix.Tasks.Chronicle.ExportTest do
  @moduledoc """
  Tests for `mix chronicle.export` (ticket 08, design brief).
  """
  use MeaningGame.DataCase, async: false

  import MeaningGame.RoomFixtures

  alias MeaningGame.Rooms

  setup do
    slug = open_room()
    {:ok, mara} = Rooms.join(slug, "Mara", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    :ok = Rooms.commit_bridge(slug, mara.id, "cairn")
    :ok = Rooms.commit_bridge(slug, jacob.id, "cairns")
    await_reveal(slug)

    %{slug: slug, mara: mara, jacob: jacob}
  end

  test "exports Chronicle to stdout", %{slug: slug} do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Chronicle.Export.run(["--room", slug])
      end)

    assert output =~ "# The Chronicle"
    assert output =~ "## Room: #{slug}"
    assert output =~ "lantern · harbour"
    assert output =~ "Mara: cairn"
    assert output =~ "Jacob: cairns"
  end

  test "exports Chronicle to a specified output file", %{slug: slug} do
    tmp_path =
      Path.join(System.tmp_dir!(), "chronicle-test-#{System.unique_integer([:positive])}.md")

    on_exit(fn -> File.rm(tmp_path) end)

    ExUnit.CaptureIO.capture_io(fn ->
      Mix.Tasks.Chronicle.Export.run(["--room", slug, "--output", tmp_path])
    end)

    assert File.exists?(tmp_path)
    content = File.read!(tmp_path)
    assert content =~ "# The Chronicle"
    assert content =~ "## Room: #{slug}"
  end
end
