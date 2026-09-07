defmodule Thereish.Foley.BriefsTest do
  use ExUnit.Case, async: true

  alias Thereish.Foley.Briefs

  describe "all/0" do
    test "contains 17 briefs: 10 original and 7 new sounds" do
      all = Briefs.all()
      assert length(all) == 17
    end

    test "carries the four new house loops with music kind, loop true, and distinct target filenames" do
      expected_loops = [
        {"house_loop_2", "house-loop-2.mp3"},
        {"house_loop_3", "house-loop-3.mp3"},
        {"house_loop_4", "house-loop-4.mp3"},
        {"house_loop_5", "house-loop-5.mp3"}
      ]

      for {key, filename} <- expected_loops do
        brief = Briefs.get(key)
        assert brief != nil, "Expected brief for #{key}"
        assert brief.kind == :music
        assert brief.loop == true
        assert brief.target_filename == filename
        assert is_binary(brief.prompt) and byte_size(brief.prompt) > 0
      end
    end

    test "carries the two victory cues (8-12 seconds, effects kind, meld resolving, deep meld brighter and longer)" do
      meld = Briefs.get("victory_meld")
      assert meld != nil
      assert meld.kind == :effects
      assert meld.loop == false
      assert meld.duration_seconds >= 8.0 and meld.duration_seconds <= 12.0
      assert meld.target_filename == "victory-meld.mp3"

      deep_meld = Briefs.get("victory_deep_meld")
      assert deep_meld != nil
      assert deep_meld.kind == :effects
      assert deep_meld.loop == false
      assert deep_meld.duration_seconds >= 8.0 and deep_meld.duration_seconds <= 12.0
      assert deep_meld.duration_seconds > meld.duration_seconds
      assert deep_meld.target_filename == "victory-deep-meld.mp3"
    end

    test "carries the commit tick (under 0.5s, soft click or wood tap, effects kind)" do
      tick = Briefs.get("commit_tick")
      assert tick != nil
      assert tick.kind == :effects
      assert tick.loop == false
      assert tick.duration_seconds <= 0.5
      assert tick.target_filename == "commit-tick.mp3"
      assert is_binary(tick.prompt) and byte_size(tick.prompt) > 0
    end
  end

  describe "get/1" do
    test "retrieves brief by atom, string key, or target filename" do
      assert Briefs.get(:commit_tick) == Briefs.get("commit_tick")
      assert Briefs.get("commit-tick.mp3") == Briefs.get(:commit_tick)
    end
  end
end
