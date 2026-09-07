defmodule Thereish.Steward.LegalityTest do
  use ExUnit.Case, async: true

  alias Thereish.Steward.Legality

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
    test "approves a legal bridge spanning the bookends" do
      assert :ok = Legality.check_bridge("beacon", ["lantern", "harbour"])
      assert :ok = Legality.check_bridge("tide", ["ocean", "moon"])
    end

    test "approves multi-word phrases and short phrases" do
      assert :ok = Legality.check_bridge("Viking beaches", ["lantern", "harbour"])
      assert :ok = Legality.check_bridge("Gold Rush", ["lantern", "harbour"])
    end

    test "approves hyphens, apostrophes, and digits" do
      assert :ok = Legality.check_bridge("ice-cream", ["lantern", "harbour"])
      assert :ok = Legality.check_bridge("rock 'n' roll", ["lantern", "harbour"])
      assert :ok = Legality.check_bridge("apollo 11", ["lantern", "harbour"])
      assert :ok = Legality.check_bridge("route 66", ["lantern", "harbour"])
    end

    test "normalizes whitespace and casing" do
      assert :ok = Legality.check_bridge("   viking   beaches   ", ["lantern", "harbour"])
    end

    test "allows words not in the dictionary for player bridges" do
      assert :ok = Legality.check_bridge("xyzzyq", ["lantern", "harbour"])
      assert :ok = Legality.check_bridge("blergblerg", ["lantern", "harbour"])
    end

    test "allows profanity for player bridges" do
      assert :ok = Legality.check_bridge("damn", ["lantern", "harbour"])
      assert :ok = Legality.check_bridge("hell", ["lantern", "harbour"])
    end

    test "rejects empty bridge or whitespace/punctuation only" do
      assert {:illegal, "Write a word first."} =
               Legality.check_bridge("", ["lantern", "harbour"])

      assert {:illegal, "Write a word first."} =
               Legality.check_bridge("   ", ["lantern", "harbour"])

      assert {:illegal, "Write a word first."} =
               Legality.check_bridge("- -", ["lantern", "harbour"])

      assert {:illegal, "Write a word first."} =
               Legality.check_bridge("'", ["lantern", "harbour"])
    end

    test "rejects characters outside letters, digits, spaces, hyphens, and apostrophes" do
      assert {:illegal, "Letters, digits, spaces, hyphens and apostrophes only (\"hello!\")."} =
               Legality.check_bridge("hello!", ["lantern", "harbour"])

      assert {:illegal, "Letters, digits, spaces, hyphens and apostrophes only (\"cool@stuff\")."} =
               Legality.check_bridge("cool@stuff", ["lantern", "harbour"])
    end

    test "rejects bridges over 40 characters" do
      long = String.duplicate("a", 41)

      assert {:illegal, "Too long to fit on a card."} =
               Legality.check_bridge(long, ["lantern", "harbour"])

      assert :ok = Legality.check_bridge(String.duplicate("a", 40), ["lantern", "harbour"])
    end

    test "rejects bridge identical to either bookend" do
      assert {:illegal, "\"harbour\" shares a root with \"harbour\"."} =
               Legality.check_bridge("harbour", ["lantern", "harbour"])

      assert {:illegal, "\"lantern\" shares a root with \"lantern\"."} =
               Legality.check_bridge("lantern", ["lantern", "harbour"])
    end

    test "rejects bridge sharing a stem with either bookend" do
      assert {:illegal, "\"runner\" shares a root with \"run\"."} =
               Legality.check_bridge("runner", ["run", "fast"])

      assert {:illegal, "\"dancing\" shares a root with \"dance\"."} =
               Legality.check_bridge("dancing", ["dance", "music"])

      assert {:illegal, "\"singer\" shares a root with \"sing\"."} =
               Legality.check_bridge("singer", ["sing", "choir"])
    end

    test "rejects bridge sharing an inflection root with either bookend" do
      assert {:illegal, "\"ran\" shares a root with \"run\"."} =
               Legality.check_bridge("ran", ["run", "speed"])

      assert {:illegal, "\"children\" shares a root with \"child\"."} =
               Legality.check_bridge("children", ["child", "school"])

      assert {:illegal, "\"mice\" shares a root with \"mouse\"."} =
               Legality.check_bridge("mice", ["mouse", "trap"])

      assert {:illegal, "\"knives\" shares a root with \"knife\"."} =
               Legality.check_bridge("knives", ["knife", "fork"])
    end

    test "rejects phrase colliding with a bookend and names the collision" do
      assert {:illegal, "\"lava rock\" shares a root with \"lava\"."} =
               Legality.check_bridge("lava rock", ["lava", "mountain"])

      assert {:illegal, "\"rocky road\" shares a root with \"rock\"."} =
               Legality.check_bridge("rocky road", ["mountain", "rock"])
    end

    test "rejects bridge colliding with a word in a multi-word barred phrase" do
      assert {:illegal, "\"beaches\" shares a root with \"beaches\"."} =
               Legality.check_bridge("beaches", ["viking beaches", "harbour"])

      assert {:illegal, "\"viking ship\" shares a root with \"viking\"."} =
               Legality.check_bridge("viking ship", ["viking beaches", "harbour"])
    end
  end
end
