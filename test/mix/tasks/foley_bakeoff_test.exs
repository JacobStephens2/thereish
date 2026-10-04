defmodule Mix.Tasks.Foley.BakeoffTest do
  @moduledoc """
  Tests for `mix foley.bakeoff` (ticket 04).
  """
  use Thereish.DataCase, async: false

  import Thereish.EntryFixtures

  alias Mix.Tasks.Foley.Bakeoff

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "foley-bakeoff-test-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{dir: tmp_dir}
  end

  test "renders paired blind files and key for Room DUST", %{dir: dir} do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Bakeoff.run(["--room", "DUST", "--count", "5", "--dir", dir])
      end)

    assert output =~ dir
    assert output =~ "Baked off 5 quip(s)"

    # Verify audio files exist
    for idx <- 1..5 do
      num = String.pad_leading("#{idx}", 2, "0")
      a_file = Path.join(dir, "#{num}-a.mp3")
      b_file = Path.join(dir, "#{num}-b.mp3")

      assert File.exists?(a_file), "Expected #{a_file} to exist"
      assert File.exists?(b_file), "Expected #{b_file} to exist"
      assert byte_size(File.read!(a_file)) > 0
      assert byte_size(File.read!(b_file)) > 0
    end

    # Verify key files exist
    key_txt = Path.join(dir, "key.txt")
    key_json = Path.join(dir, "key.json")

    assert File.exists?(key_txt)
    assert File.exists?(key_json)

    key_data = Jason.decode!(File.read!(key_json))
    assert Map.has_key?(key_data, "a")
    assert Map.has_key?(key_data, "b")

    providers = [key_data["a"]["provider"], key_data["b"]["provider"]]
    assert "ElevenLabs" in providers
    assert "Hume" in providers
  end

  test "accepts positional room and count arguments", %{dir: dir} do
    ExUnit.CaptureIO.capture_io(fn ->
      Bakeoff.run(["DUST", "2", "--dir", dir])
    end)

    assert File.exists?(Path.join(dir, "01-a.mp3"))
    assert File.exists?(Path.join(dir, "01-b.mp3"))
    assert File.exists?(Path.join(dir, "02-a.mp3"))
    assert File.exists?(Path.join(dir, "02-b.mp3"))
    refute File.exists?(Path.join(dir, "03-a.mp3"))
  end

  test "reads a Room in the database from its Page views, last N oldest first", %{dir: dir} do
    slug = "bakeoff-#{System.unique_integer([:positive])}"
    {:ok, room} = Thereish.Rooms.Store.insert_room(slug, 2, nil)

    for {quips, index} <- Enum.with_index([["first", ""], ["second", "third"]], 1) do
      attempts =
        quips
        |> Enum.with_index(1)
        |> Enum.map(fn {quip, number} -> %{number: number, verdicts: [%{quip: quip}]} end)

      opened_at = DateTime.add(DateTime.utc_now(), index, :second)

      {:ok, _page} =
        Thereish.Chronicle.write(room.id, entry(opened_at: opened_at, attempts: attempts))
    end

    ExUnit.CaptureIO.capture_io(fn ->
      Bakeoff.run(["--room", String.upcase(slug), "--count", "2", "--dir", dir])
    end)

    assert File.read!(Path.join(dir, "quips.txt")) == "01: second\n02: third\n"
  end

  test "raises when room has no chronicle or quips", %{dir: dir} do
    assert_raise Mix.Error, ~r/No quips found/, fn ->
      Bakeoff.run(["NONEXISTENT_ROOM_XYZ", "--dir", dir])
    end
  end
end
