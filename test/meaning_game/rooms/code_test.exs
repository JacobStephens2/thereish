defmodule MeaningGame.Rooms.CodeTest do
  @moduledoc """
  The four-letter word a Room is known by.

  A Code is read aloud at a table, so what matters here is that it is always a
  real word, never one nobody would say out loud, and that it survives being
  typed in whatever case the thumb lands on.
  """
  use ExUnit.Case, async: true

  alias MeaningGame.Rooms.Code
  alias MeaningGame.Steward.Legality

  describe "reading a Code someone typed" do
    test "any case is the same Code" do
      assert Code.normalise("CANE") == "cane"
      assert Code.normalise("Cane") == "cane"
      assert Code.normalise("  cane ") == "cane"
    end

    test "a Code no Room could have is nothing at all" do
      assert Code.normalise("Not A Code") == nil
      assert Code.normalise("") == nil
      assert Code.normalise("   ") == nil
      assert Code.normalise(nil) == nil
    end

    test "the slugs Rooms already have are still Codes" do
      assert Code.normalise("couch") == "couch"
      assert Code.normalise("test-1234") == "test-1234"
    end
  end

  describe "saying a Code out loud" do
    test "it is shown uppercase" do
      assert Code.shout("cane") == "CANE"
    end
  end

  describe "drawing a Code" do
    test "a drawn Code is always a real four-letter word" do
      for _ <- 1..200 do
        code = Code.draw()

        assert String.length(code) == 4
        assert Legality.in_dictionary?(code)
        refute Legality.profane?(code)
        assert Code.normalise(code) == code
      end
    end

    test "the draw is not the same word every time" do
      drawn = Enum.map(1..50, fn _ -> Code.draw() end)

      assert length(Enum.uniq(drawn)) > 1
    end

    test "the words to draw from are many" do
      assert length(Code.words()) > 1_000
    end
  end
end
