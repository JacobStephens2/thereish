defmodule MeaningGame.LadderTest do
  use ExUnit.Case, async: true

  alias MeaningGame.Ladder

  describe "bands and band_names" do
    test "bands/0 returns configured bands with floors lowest first" do
      bands = Ladder.bands()

      assert Keyword.keys(bands) == [:miss, :adjacent, :close, :almost, :meld, :deep_meld]
      assert bands[:miss] == 0
      assert bands[:adjacent] == 30
      assert bands[:close] == 55
      assert bands[:almost] == 75
      assert bands[:meld] == 90
      assert bands[:deep_meld] == 100
    end

    test "band_names/0 returns the band atoms in ascending order" do
      assert Ladder.band_names() == [:miss, :adjacent, :close, :almost, :meld, :deep_meld]
    end
  end

  describe "read/1 and band/1" do
    test "reads nil as nil closeness and nil band" do
      assert Ladder.read(nil) == %{closeness: nil, band: nil, melded?: false}
    end

    test "reads closeness into correct band" do
      assert Ladder.band(0) == :miss
      assert Ladder.band(29) == :miss
      assert Ladder.band(30) == :adjacent
      assert Ladder.band(54) == :adjacent
      assert Ladder.band(55) == :close
      assert Ladder.band(74) == :close
      assert Ladder.band(75) == :almost
      assert Ladder.band(89) == :almost
      assert Ladder.band(90) == :meld
      assert Ladder.band(99) == :meld
      assert Ladder.band(100) == :deep_meld
    end

    test "melded?/1 triggers at meld threshold" do
      refute Ladder.melded?(74)
      refute Ladder.melded?(75)
      refute Ladder.melded?(89)
      assert Ladder.melded?(90)
      assert Ladder.melded?(100)
    end
  end
end
