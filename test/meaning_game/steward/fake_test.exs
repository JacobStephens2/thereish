defmodule MeaningGame.Steward.FakeTest do
  @moduledoc """
  The Assayer every other test grades against.

  It has no model behind it, so what is worth pinning is that it is still a
  **dial**: that the number a test gets is the number the test's own words chose,
  and that the number two words have always got is still the number two words
  get. Every assertion the rest of the suite makes about a grade rests on the
  arithmetic here, so the arithmetic is written down once, in a test, rather than
  rediscovered by whoever breaks it.
  """
  use ExUnit.Case, async: true

  alias MeaningGame.Steward.Fake

  @anchors ["lantern", "harbour"]

  defp graded(bridges) do
    {:ok, verdict} = Fake.assay(%{anchors: @anchors, bridges: bridges})

    verdict
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

      assert verdict.meta.reasoning_reverse ==
               "\"cairo\" and \"cairn\" share the same 4 letters the other way round."
    end

    test "names the only two words as the two furthest apart" do
      assert graded(["cairn", "cairo"]).furthest == ["cairn", "cairo"]
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

    test "says the same thing in both orderings, because it is arithmetic" do
      verdict = graded(@table)

      assert verdict.meta.forward == verdict.closeness
      assert verdict.meta.reverse == verdict.closeness
    end

    test "writes its reasoning and its quip about the two furthest words" do
      verdict = graded(@table)

      assert verdict.reasoning =~ "\"cairn\" and \"beacon\""
      assert verdict.quip =~ "\"cairn\" and \"beacon\""
    end

    test "a table that all wrote the same word is a hundred" do
      assert graded(["moon", "moon", "moon", "moon"]).closeness == 100
    end
  end

  describe "the dials" do
    setup do
      steward = Application.fetch_env!(:meaning_game, :steward)
      on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

      :ok
    end

    defp fake(opts) do
      steward = Application.fetch_env!(:meaning_game, :steward)
      fake = Keyword.merge(steward[:fake], opts)

      Application.put_env(:meaning_game, :steward, Keyword.put(steward, :fake, fake))
    end

    test "an Assayer that cannot answer says so at four words as at two" do
      fake(mode: :unavailable)

      assert Fake.assay(%{anchors: @anchors, bridges: ["cairn", "cairo"]}) ==
               {:error, :no_verdict}

      assert Fake.assay(%{anchors: @anchors, bridges: ["cairn", "cairo", "cable", "beacon"]}) ==
               {:error, :no_verdict}
    end

    test "the fake Scribe answers a configured word, or a default word" do
      assert Fake.name_room(["some digest"], ["take"]) == {:ok, "cane"}

      fake(name_word: "fork")
      assert Fake.name_room(["some digest"], ["take"]) == {:ok, "fork"}
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
  end
end
