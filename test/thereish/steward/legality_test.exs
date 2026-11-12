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

    test "function words never carry a collision" do
      assert :ok = Legality.check_bridge("the", ["theology"])
      assert :ok = Legality.check_bridge("and", ["android"])
      assert :ok = Legality.check_bridge("for", ["forest"])
      assert :ok = Legality.check_bridge("one", ["onerous"])
      assert :ok = Legality.check_bridge("out", ["outfit"])
      # Four-letter function words are the half the prefix floor does not catch.
      assert :ok = Legality.check_bridge("that", ["thatch"])
      assert :ok = Legality.check_bridge("thatch", ["that mill"])
    end

    test "a phrase's function words are dropped and its content words still collide" do
      assert :ok = Legality.check_bridge("the meaning of life", ["theology"])

      assert {:illegal, "\"the lava rock\" shares a root with \"lava\"."} =
               Legality.check_bridge("the lava rock", ["lava", "mountain"])
    end

    test "a bridge made only of function words is legal" do
      assert :ok = Legality.check_bridge("the one", ["theology", "android"])
      assert :ok = Legality.check_bridge("and so", ["forest", "onerous"])
    end

    test "seashore does not collide with sea" do
      assert :ok = Legality.check_bridge("seashore", ["sea", "harbour"])
      assert :ok = Legality.check_bridge("sea", ["seashore", "harbour"])
    end
  end

  describe "validate_bridge/3" do
    test "returns the normalized Bridge" do
      assert {:ok, "apollo 11's ice-cream"} =
               Legality.validate_bridge("  APOLLO\t11's   ICE-CREAM \n", ["lantern", "harbour"])
    end

    test "attributes an actual Nudge collision after checking lexical shape" do
      nudges = [%{name: "Bram", word: "rope"}]

      assert {:illegal, ~s(Bram nudged "rope" — nobody can use it as a bridge.)} =
               Legality.validate_bridge(" ROPES ", ["lantern", "rope"], nudges)

      assert {:illegal, ~s|Letters, digits, spaces, hyphens and apostrophes only ("abc!").|} =
               Legality.validate_bridge(" ABC! ", ["rope"], nudges)
    end

    test "distinguishes required input from malformed input even with Nudges" do
      nudges = [%{name: "Bram", word: "rope"}]

      for input <- [nil, "", " \t\n "] do
        assert {:required, "Write a word first."} = Legality.validate_bridge(input, [], nudges)
      end

      for input <- ["- -", "'", "!!!"] do
        assert {:illegal, "Write a word first."} = Legality.validate_bridge(input, [], nudges)
      end

      assert {:illegal, "Too long to fit on a card."} =
               Legality.validate_bridge(String.duplicate("a", 41), [], nudges)

      forty = String.duplicate("a", 40)
      assert {:ok, ^forty} = Legality.validate_bridge("  #{forty}  ", [], nudges)
    end

    test "an unrelated Nudge leaves ordinary collision reasons and order intact" do
      nudges = [%{name: "Bram", word: "rope"}]

      for {input, barred, reason} <- [
            {" LANTERNS ", ["lantern", "rope"], ~s("lanterns" shares a root with "lantern".)},
            {"earlier bridges", ["earlier bridge", "rope"],
             ~s("earlier bridges" shares a root with "earlier".)},
            {"lava rock", ["rock", "lava", "rope"], ~s("lava rock" shares a root with "rock".)}
          ] do
        assert {:illegal, ^reason} = Legality.validate_bridge(input, barred, nudges)
      end
    end

    test "Nudge identity, inflections, phrases and function words use the existing root rules" do
      for {input, word} <- [
            {"rope", "rope"},
            {"ran", "run"},
            {"children", "child"},
            {"rocky road", "lava rock"},
            {"beaches", "viking beaches"},
            {"the", "the"}
          ] do
        assert {:illegal, reason} =
                 Legality.validate_bridge(input, [word], [%{name: "Bram", word: word}])

        assert reason == ~s(Bram nudged "#{word}" — nobody can use it as a bridge.)
      end

      assert {:ok, "the meaning of life"} =
               Legality.validate_bridge("the meaning of life", ["theology"], [
                 %{name: "Bram", word: "theology"}
               ])
    end

    test "a real Nudge collision precedes ordinary collisions and the first arrival wins" do
      nudges = [%{name: "Bram", word: "rope"}, %{name: "Mara", word: "beach"}]

      assert {:illegal, ~s(Bram nudged "rope" — nobody can use it as a bridge.)} =
               Legality.validate_bridge(
                 "lava ropes on beaches",
                 ["lava", "beach", "rope"],
                 nudges
               )

      assert {:illegal, ~s(Mara nudged "beach" — nobody can use it as a bridge.)} =
               Legality.validate_bridge(
                 "lava ropes on beaches",
                 ["lava", "rope", "beach"],
                 Enum.reverse(nudges)
               )
    end

    test "omitting attribution keeps generic Nudge checks and player language" do
      assert {:illegal, ~s("ropes" shares a root with "rope".)} =
               Legality.validate_bridge(" ROPES ", ["rope"])

      for input <- [
            "viking beaches",
            "ice-cream",
            "rock 'n' roll",
            "apollo 11",
            "123",
            "xyzzyq",
            "damn"
          ] do
        assert {:ok, ^input} = Legality.validate_bridge(input, ["lantern", "harbour"])
      end
    end
  end

  describe "shared_root?/2" do
    test "still answers true for inflection, stem, and identity" do
      assert Legality.shared_root?("runner", "run")
      assert Legality.shared_root?("lanterns", "lantern")
      assert Legality.shared_root?("harbour", "harbour")
    end
  end

  describe "check_author_bridge/2" do
    test "bare validation preserves display casing and only the Author requires dictionary and clean words" do
      assert {:illegal, ~s|Letters, digits, spaces, hyphens and apostrophes only ("ABC!").|} =
               Legality.check_bridge("  ABC!  ", [])

      assert {:illegal, "Not in this Room."} = Legality.check_author_bridge("damn", [])

      assert {:illegal, ~s|One word, letters only ("apollo 11").|} =
               Legality.check_author_bridge("Apollo 11", [])

      assert {:illegal, ~s|"xyzzyq" is not in the dictionary.|} =
               Legality.check_author_bridge("xyzzyq", [])

      assert :ok = Legality.check_bridge("damn xyzzyq 11", [])
      assert Legality.normalize_bridge("  Gold\tRUSH ") == "gold rush"
    end

    test "still gates the Author's bookends through the same root check" do
      assert :ok = Legality.check_author_bridge("beacon", ["lantern", "harbour"])

      assert {:illegal, "\"runner\" shares a root with \"run\"."} =
               Legality.check_author_bridge("runner", ["run", "fast"])

      assert {:illegal, "\"xyzzyq\" is not in the dictionary."} =
               Legality.check_author_bridge("xyzzyq", ["lantern", "harbour"])
    end

    test "theology against the and seashore against sea are legal" do
      assert :ok = Legality.check_author_bridge("theology", ["the"])
      assert :ok = Legality.check_author_bridge("seashore", ["sea"])
    end
  end
end
