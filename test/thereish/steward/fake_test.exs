defmodule Thereish.Steward.FakeTest do
  @moduledoc """
  The Assayer every other test grades against.

  It has no model behind it, so what is worth pinning is that it is still a
  **dial**: that the number a test gets is the number the test's own words chose,
  and that the number two words have always got is still the number two words
  get. Every assertion the rest of the suite makes about a grade rests on the
  arithmetic here, so the arithmetic is written down once, in a test, rather than
  rediscovered by whoever breaks it.

  Like any adapter, it grades the one ordering it is handed. How two orderings
  become a Verdict is the Steward's, and is tested through `Thereish.Steward`.
  """
  use ExUnit.Case, async: true

  alias Thereish.Steward.Fake

  @bookends ["lantern", "harbour"]

  defp graded(bridges) do
    {:ok, answer} = Fake.assay(%{bookends: @bookends, bridges: bridges}, bridges)

    answer
  end

  describe "two words, which must be the grade they have always been" do
    # "cairn" and "cairo" share four letters from the front out of ten, which is
    # 80, which is the Meld the couch's tests have been asserting on since the
    # first one was written. Group play does not get to move it (ADR-0010).
    test "grades on the shared prefix, exactly as before" do
      assert graded(["cairn", "cairo"]).closeness == 80
      assert graded(["cairn", "beacon"]).closeness == 0
      assert graded(["moon", "moon"]).closeness == 100
    end

    test "writes the same reasoning and the same quip as before" do
      verdict = graded(["cairn", "cairo"])

      assert verdict.reasoning ==
               "\"cairn\" and \"cairo\" share 4 letters from the front. " <>
                 "That is all this Assayer knows how to look at."

      assert verdict.quip == "\"cairn\" and \"cairo\" walk into a bar. The bar has no opinion."
    end

    test "names the only two words as the two furthest apart" do
      assert graded(["cairn", "cairo"]).furthest == ["cairn", "cairo"]
    end

    test "grades the ordering it is handed, not the request's Bridges" do
      request = %{bookends: @bookends, bridges: ["cairn", "beacon"]}

      assert {:ok, %{closeness: 80}} = Fake.assay(request, ["cairn", "cairo"])
    end
  end

  describe "grading phrases" do
    test "grades phrases on their shared prefix" do
      # "viking beaches" (14) and "viking boats" (12) share "viking b" (8):
      # round(200 * 8 / 26) = 62
      assert graded(["viking beaches", "viking boats"]).closeness == 62
    end

    test "identical phrases grade 100 regardless of casing or extra whitespace" do
      assert graded(["Viking beaches", "  viking   beaches "]).closeness == 100
      assert graded(["Gold Rush", "gold rush"]).closeness == 100
    end

    test "grades bridges provided as maps with player names" do
      player_bridges = [
        %{player: "Mara", bridge: "viking beaches"},
        %{player: "Jacob", bridge: "viking boats"}
      ]

      {:ok, verdict} = Fake.assay(%{bookends: @bookends, bridges: player_bridges}, player_bridges)
      assert verdict.closeness == 62
      assert verdict.furthest == ["viking beaches", "viking boats"]
    end
  end

  describe "a table of four" do
    # The six pairs of these four words grade 80, 40, 0, 40, 0 and 0, which is a
    # mean of 26.67 and a Closeness of 27. A test that wants a different number
    # writes different words.
    @table ["cairn", "cairo", "cable", "beacon"]

    test "grades the mean of every pair's shared prefix" do
      assert graded(@table).closeness == 27
    end

    test "names the pair that graded lowest as the two furthest apart" do
      assert graded(@table).furthest == ["cairn", "beacon"]
    end

    test "breaks a tie for lowest by roster order" do
      # Three of the six pairs above grade zero. The one whose words sit
      # earliest in the roster is the one named, every time, so that a table
      # replaying an evening gets the same carry-forward it got the first time.
      assert graded(@table).furthest == ["cairn", "beacon"]
      assert graded(["beacon", "cable", "cairn", "cairo"]).furthest == ["beacon", "cable"]
    end

    test "grades the same in either ordering, because it is arithmetic" do
      assert graded(Enum.reverse(@table)).closeness == graded(@table).closeness
    end

    test "names the model and what it cost, and no two-ordering provenance of its own" do
      answer = graded(@table)

      assert answer.model == "fake"
      assert answer.cost_usd == 0.0
      refute Map.has_key?(answer, :meta)
    end

    test "writes its reasoning and its quip about the two furthest words" do
      verdict = graded(@table)

      assert verdict.reasoning =~ "\"cairn\" and \"beacon\""
      assert verdict.quip =~ "\"cairn\" and \"beacon\""
    end

    test "a table that all wrote the same word is a hundred" do
      assert graded(["moon", "moon", "moon", "moon"]).closeness == 100
    end

    test "grades N Bridges against N Bookends the same as against two" do
      {:ok, verdict} =
        Fake.assay(
          %{bookends: ["lantern", "harbour", "summit", "ember"], bridges: @table},
          @table
        )

      assert verdict.closeness == 27
      assert verdict.furthest == ["cairn", "beacon"]
    end
  end

  describe "N Bookends" do
    @four_bookends ["lantern", "harbour", "wharf", "dusk"]
    @table ["cairn", "cairo", "cable", "beacon"]

    test "grades N Bookends the same way it grades two: on the Bridges" do
      {:ok, with_two} = Fake.assay(%{bookends: @bookends, bridges: @table}, @table)
      {:ok, with_four} = Fake.assay(%{bookends: @four_bookends, bridges: @table}, @table)

      assert with_four.closeness == with_two.closeness
      assert with_four.furthest == with_two.furthest
      assert with_four.closeness == 27
      assert with_four.furthest == ["cairn", "beacon"]
    end

    test "still names exactly two written Bridges as furthest apart" do
      {:ok, verdict} = Fake.assay(%{bookends: @four_bookends, bridges: @table}, @table)

      assert [left, right] = verdict.furthest
      assert left in @table
      assert right in @table
    end
  end

  describe "the dials" do
    setup do
      steward = Application.fetch_env!(:thereish, :steward)
      on_exit(fn -> Application.put_env(:thereish, :steward, steward) end)

      :ok
    end

    defp fake(opts) do
      steward = Application.fetch_env!(:thereish, :steward)
      fake = Keyword.merge(steward[:fake], opts)

      Application.put_env(:thereish, :steward, Keyword.put(steward, :fake, fake))
    end

    test "an Assayer that cannot answer says so at four words as at two" do
      fake(mode: :unavailable)

      pair = ["cairn", "cairo"]
      table = ["cairn", "cairo", "cable", "beacon"]

      assert Fake.assay(%{bookends: @bookends, bridges: pair}, pair) == {:error, :no_verdict}
      assert Fake.assay(%{bookends: @bookends, bridges: table}, table) == {:error, :no_verdict}
    end

    test "Fake.speak answers a fixture MP3 with format and meta" do
      fake(voice_mode: :ok)

      assert {:ok, result} = Fake.speak("Close. One of you was thinking of the shore.")
      assert is_binary(result.audio)
      assert byte_size(result.audio) > 0
      assert result.format == :mp3
      assert result.meta.provider == "fake"
      assert result.meta.cost_usd == 0.0
    end

    test "Fake.speak obeys dials for unavailable, custom errors, and raise" do
      fake(voice_mode: :unavailable)
      assert Fake.speak("Miss.") == {:error, :voice_unavailable}

      fake(voice_mode: {:error, :rate_limited})
      assert Fake.speak("Miss.") == {:error, :rate_limited}

      fake(voice_mode: :raise)

      assert_raise RuntimeError, "this Voice is having a moment", fn ->
        Fake.speak("Miss.")
      end
    end

    test "Steward.speak measures latency and passes options to adapter" do
      fake(voice_mode: :ok, voice_delay_ms: 5)

      assert {:ok, result} = Thereish.Steward.speak("Meld.", voice_id: "custom-voice")
      assert result.meta.voice_id == "custom-voice"
      assert result.meta.latency_ms >= 5
    end

    test "the fake Scribe answers a configured word and quip, or default" do
      assert Fake.name_room(["some digest"], ["take"]) ==
               {:ok, %{word: "cane", quip: "A room from the old days."}}

      fake(name_word: "fork", name_quip: "Dinner is served.")

      assert Fake.name_room(["some digest"], ["take"]) ==
               {:ok, %{word: "fork", quip: "Dinner is served."}}
    end

    test "the fake Scribe answers nothing when configured to" do
      fake(name_word: nil)
      assert Fake.name_room(["some digest"], ["take"]) == {:error, :no_name}

      fake(name_mode: :unavailable)
      assert Fake.name_room(["some digest"], ["take"]) == {:error, :no_name}
    end

    test "the fake Scribe raises when configured to" do
      fake(name_mode: :raise)

      assert_raise RuntimeError, ~r/this Scribe is having a moment/, fn ->
        Fake.name_room(["some digest"], ["take"])
      end
    end

    test "the fake Scribe with no history returns :no_history" do
      assert Fake.name_room([], ["take"]) == {:error, :no_history}
    end

    test "the fake Scribe quip_code answers a configured quip or default" do
      assert Fake.quip_code("cane") == {:ok, "A fine room."}

      fake(quip_text: "A sweet room.")
      assert Fake.quip_code("cane") == {:ok, "A sweet room."}
    end

    test "the fake Author answers N Bookends offline" do
      six_gives =
        for name <- ~w(Mara Jacob Ada Ida Ola Ora) do
          %{name: name, text: "setting #{name}"}
        end

      assert {:ok, two} = Fake.author(%{gives: Enum.take(six_gives, 2), count: 2})
      assert two.bookends == ["lantern", "harbour"]
      assert two.meta.count == 2

      assert {:ok, six} = Fake.author(%{gives: six_gives, count: 6})
      assert length(six.bookends) == 6
      assert six.bookends == ["lantern", "harbour", "summit", "ember", "grove", "spire"]
      assert six.meta.count == 6
      assert six.bookends == Enum.uniq(six.bookends)

      eight_gives =
        six_gives ++
          for name <- ~w(Ivy Ned) do
            %{name: name, text: "setting #{name}"}
          end

      assert {:ok, eight} = Fake.author(%{gives: eight_gives, count: 8})

      assert eight.bookends == [
               "lantern",
               "harbour",
               "summit",
               "ember",
               "grove",
               "spire",
               "ridge",
               "hearth"
             ]

      assert eight.meta.count == 8
      assert eight.bookends == Enum.uniq(eight.bookends)
    end

    test "the fake Author answers N Bookends for any N, from however few Gives" do
      two_gives = [
        %{name: "Mara", text: "setting Mara"},
        %{name: "Bram", text: "setting Bram"}
      ]

      # Bookends per Give: four words from two settings, and every setting named
      # twice over in `from`, which is what the Author's own gate asks for.
      assert {:ok, four} = Fake.author(%{gives: two_gives, count: 4})
      assert length(four.bookends) == 4
      assert four.bookends == Enum.uniq(four.bookends)
      assert four.from == ["Mara", "Bram", "Mara", "Bram"]
      assert :ok = Thereish.Steward.Author.check(json(four), two_gives, 4)

      # Past the pool it keeps going and keeps every word distinct.
      assert {:ok, wide} = Fake.author(%{gives: two_gives, count: 11})
      assert length(wide.bookends) == 11
      assert wide.bookends == Enum.uniq(wide.bookends)
      assert length(wide.from) == 11
    end

    # The fake's answer as the gate reads it: string keys, as JSON.
    defp json(result) do
      %{"bookends" => result.bookends, "from" => result.from, "why" => result.why}
    end

    test "the fake Author still honours a configured pair" do
      fake(author_bookends: ["cactus", "dune"])

      assert {:ok, result} = Fake.author(%{gives: [%{name: "Mara", text: "desert"}], count: 2})
      assert result.bookends == ["cactus", "dune"]
    end

    test "the fake Scribe quip_code answers nothing or raises when configured to" do
      fake(quip_mode: :unavailable)
      assert Fake.quip_code("cane") == {:error, :no_quip}

      fake(quip_mode: :raise)

      assert_raise RuntimeError, ~r/this Scribe is having a moment/, fn ->
        Fake.quip_code("cane")
      end
    end
  end

  describe "foley forge and rank" do
    test "forge returns N candidate effects with fixture MP3 bytes and meta" do
      assert {:ok, candidates} = Fake.forge("brief for a sound effect", n: 4)
      assert length(candidates) == 4

      Enum.each(candidates, fn candidate ->
        assert is_binary(candidate.bytes)
        assert byte_size(candidate.bytes) > 0
        assert candidate.meta.model == "fake"
        assert candidate.meta.cost_usd == 0.0
      end)
    end

    test "rank returns a fixed ordering against the candidates" do
      {:ok, candidates} = Fake.forge("brief", n: 3)
      assert {:ok, ranking} = Fake.rank(candidates, "brief")

      assert length(ranking) == 3
      assert Enum.map(ranking, & &1.index) == [1, 2, 3]
      assert Enum.all?(ranking, &(&1.reason =~ "Candidate"))
    end
  end
end
