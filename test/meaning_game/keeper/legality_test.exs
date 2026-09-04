defmodule MeaningGame.Keeper.LegalityTest do
  use ExUnit.Case, async: true

  alias MeaningGame.Keeper.Legality

  describe "single_word?/1" do
    test "accepts clean single words" do
      assert Legality.single_word?("lantern")
      assert Legality.single_word?("harbour")
      assert Legality.single_word?("bridge")
    end

    test "rejects multi-word, empty, or non-letter strings" do
      refute Legality.single_word?("")
      refute Legality.single_word?("   ")
      refute Legality.single_word?("hot dog")
      refute Legality.single_word?("ice-cream")
      refute Legality.single_word?("it's")
      refute Legality.single_word?("word123")
      refute Legality.single_word?("hello!")
    end
  end

  describe "in_dictionary?/1" do
    test "recognizes words in the ENABLE wordlist" do
      assert Legality.in_dictionary?("lantern")
      assert Legality.in_dictionary?("harbour")
      assert Legality.in_dictionary?("lighthouse")
      assert Legality.in_dictionary?("barbecue")
    end

    test "rejects nonsense non-words" do
      refute Legality.in_dictionary?("xyzzyq")
      refute Legality.in_dictionary?("asdfghjkl")
      refute Legality.in_dictionary?("blergblerg")
    end
  end

  describe "profane?/1" do
    test "detects profanity" do
      assert Legality.profane?("damn")
      assert Legality.profane?("hell")
      assert Legality.profane?("shit")
      assert Legality.profane?("fuck")
    end

    test "passes clean words" do
      refute Legality.profane?("lantern")
      refute Legality.profane?("harbour")
      refute Legality.profane?("scunthorpe")
    end
  end

  describe "check_bridge/2" do
    test "approves a legal bridge spanning the anchors" do
      assert :ok = Legality.check_bridge("beacon", ["lantern", "harbour"])
      assert :ok = Legality.check_bridge("tide", ["ocean", "moon"])
    end

    test "rejects empty bridge" do
      assert {:illegal, "Write a word first."} =
               Legality.check_bridge("", ["lantern", "harbour"])
    end

    test "rejects non-letter characters or multi-word bridge" do
      assert {:illegal, "One word, letters only (\"two words\")."} =
               Legality.check_bridge("two words", ["lantern", "harbour"])

      assert {:illegal, "One word, letters only (\"ice-cream\")."} =
               Legality.check_bridge("ice-cream", ["lantern", "harbour"])
    end

    test "rejects non-dictionary words" do
      assert {:illegal, "\"xyzzyq\" is not in the dictionary."} =
               Legality.check_bridge("xyzzyq", ["lantern", "harbour"])
    end

    test "rejects profanity" do
      assert {:illegal, "Not in this Room."} =
               Legality.check_bridge("damn", ["lantern", "harbour"])
    end

    test "rejects bridge identical to either anchor" do
      assert {:illegal, "That is the anchor itself (\"harbour\")."} =
               Legality.check_bridge("harbour", ["lantern", "harbour"])

      assert {:illegal, "That is the anchor itself (\"lantern\")."} =
               Legality.check_bridge("lantern", ["lantern", "harbour"])
    end

    test "rejects bridge sharing a stem with either anchor" do
      assert {:illegal, "\"runner\" shares a root with \"run\"."} =
               Legality.check_bridge("runner", ["run", "fast"])

      assert {:illegal, "\"dancing\" shares a root with \"dance\"."} =
               Legality.check_bridge("dancing", ["dance", "music"])

      assert {:illegal, "\"singer\" shares a root with \"sing\"."} =
               Legality.check_bridge("singer", ["sing", "choir"])
    end

    test "rejects bridge sharing an inflection root with either anchor" do
      assert {:illegal, "\"ran\" shares a root with \"run\"."} =
               Legality.check_bridge("ran", ["run", "speed"])

      assert {:illegal, "\"children\" shares a root with \"child\"."} =
               Legality.check_bridge("children", ["child", "school"])

      assert {:illegal, "\"mice\" shares a root with \"mouse\"."} =
               Legality.check_bridge("mice", ["mouse", "trap"])

      assert {:illegal, "\"knives\" shares a root with \"knife\"."} =
               Legality.check_bridge("knives", ["knife", "fork"])
    end
  end
end
