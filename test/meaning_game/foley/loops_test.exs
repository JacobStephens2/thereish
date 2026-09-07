defmodule MeaningGame.Foley.LoopsTest do
  use ExUnit.Case, async: true

  alias MeaningGame.Foley.Loops

  describe "all/0" do
    test "returns five house loops with the existing loop first" do
      loops = Loops.all()

      assert length(loops) == 5

      [first | rest] = loops
      assert first.path == "/audio/house-loop.mp3"
      assert first.name == "The Porch"

      assert Enum.map(rest, & &1.path) == [
               "/audio/house-loop-2.mp3",
               "/audio/house-loop-3.mp3",
               "/audio/house-loop-4.mp3",
               "/audio/house-loop-5.mp3"
             ]

      for loop <- loops do
        assert is_binary(loop.name) and byte_size(loop.name) > 0
        assert String.starts_with?(loop.path, "/audio/house-loop")
      end
    end

    test "matches every loop name and path in the committed manifest" do
      manifest_path = Path.expand(".scratch/coffee-table/manifest.json")
      manifest = manifest_path |> File.read!() |> Jason.decode!()
      loops = Loops.all()

      expected = [
        {"house_loop", "/audio/house-loop.mp3"},
        {"house_loop_2", "/audio/house-loop-2.mp3"},
        {"house_loop_3", "/audio/house-loop-3.mp3"},
        {"house_loop_4", "/audio/house-loop-4.mp3"},
        {"house_loop_5", "/audio/house-loop-5.mp3"}
      ]

      for {brief_key, path} <- expected do
        manifest_name = get_in(manifest, [brief_key, "name"])
        assert manifest_name != nil, "Manifest must contain a name for #{brief_key}"

        loop = Enum.find(loops, &(&1.path == path))
        assert loop != nil, "Expected loop with path #{path}"
        assert loop.name == manifest_name
      end
    end
  end

  describe "pick/1" do
    test "picks a loop from all loops when previous loop is nil" do
      loop = Loops.pick()
      assert loop in Loops.all()
    end

    test "never picks the previous loop" do
      all_loops = Loops.all()

      for prev <- all_loops do
        for _ <- 1..50 do
          picked = Loops.pick(prev)
          assert picked in all_loops
          refute picked == prev
          refute picked.name == prev.name
          refute picked.path == prev.path
        end
      end
    end
  end
end
