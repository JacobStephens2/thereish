defmodule MeaningGame.PagesTest do
  use MeaningGame.DataCase, async: false

  alias MeaningGame.Pages

  @valid_page %{
    id: "P123456",
    chapter: "suburban family life",
    theme: "suburban family life",
    give: nil,
    anchors: ["backyard", "weekend"],
    bait: "barbecue",
    deep_bridges: ["lawnmower", "chores"],
    likely_bridges: ["barbecue", "lawnmower", "chores", "family", "party"],
    why_these: "Backyard and weekend invite barbecue as the immediate trap.",
    band_scripts: %{
      "miss" => "Different neighbourhoods entirely.",
      "adjacent" => "On the same block, across the street.",
      "close" => "Passable.",
      "meld" => "You both saw the grill.",
      "deep_meld" => "Two minds at the mower."
    },
    meta: %{
      model: "claude-fable-5-1",
      prompt_version: "author-2",
      attempts: 1,
      cost_usd: 0.15,
      latency_ms: 1200
    }
  }

  describe "pool management" do
    test "inserts authored page into the pool" do
      assert {:ok, page} = Pages.insert_page(@valid_page)
      assert page.anchors == ["backyard", "weekend"]
      assert page.bait == "barbecue"
      assert is_nil(page.played_at)
    end

    test "draws from the pool and marks it played" do
      {:ok, page1} = Pages.insert_page(@valid_page)
      room_id = Ecto.UUID.generate()

      assert {:ok, drawn} = Pages.draw(room_id)
      assert drawn.id == page1.id
      assert drawn.anchors == ["backyard", "weekend"]
      assert drawn.bait == "barbecue"

      # The page is now marked played in the database
      persisted = Pages.get_page(drawn.id)
      assert persisted.played_at != nil
      assert persisted.played_room_id == room_id
    end

    test "the pool draining and refusing to repeat a Page" do
      room_id = Ecto.UUID.generate()

      # Add exactly two pages to the pool
      page1_attrs = %{@valid_page | id: "P000001", anchors: ["kettle", "window"], bait: "steam"}
      page2_attrs = %{@valid_page | id: "P000002", anchors: ["desert", "mirror"], bait: "mirage"}

      {:ok, _} = Pages.insert_page(page1_attrs)
      {:ok, _} = Pages.insert_page(page2_attrs)

      # First draw gets page 1
      assert {:ok, drawn1} = Pages.draw(room_id)
      assert drawn1.id == "P000001"

      # Second draw gets page 2
      assert {:ok, drawn2} = Pages.draw(room_id)
      assert drawn2.id == "P000002"

      # Pool is now drained: next draw refuses to repeat any page
      assert {:error, :pool_exhausted} = Pages.draw(room_id)
      assert {:error, :pool_exhausted} = Pages.draw(room_id)
    end

    test "authoring ahead of play against a named Chapter fills the pool" do
      room_id = Ecto.UUID.generate()

      # Author two pages into the pool
      assert {:ok, pages} = Pages.author_chapter("suburban family life", 2)
      assert length(pages) == 2

      # Pages can now be drawn from the pool without invoking any model
      assert {:ok, drawn1} = Pages.draw(room_id)
      assert drawn1.chapter == "suburban family life"
      assert drawn1.bait != nil

      assert {:ok, drawn2} = Pages.draw(room_id)
      assert drawn2.chapter == "suburban family life"
    end

    test "authoring for a Give tags pages with the give and allows targeted draw" do
      room_id = Ecto.UUID.generate()

      # Author two pages for a give
      give = "the world St. Thérèse grew up in"
      assert {:ok, pages} = Pages.author_give(give, count: 2)
      assert length(pages) == 2
      assert Enum.all?(pages, &(&1.give == give))

      # Draw specifically for this give
      assert {:ok, drawn} = Pages.draw(room_id, give: give)
      assert drawn.give == give
      assert drawn.anchors != nil

      # Draw second page for this give
      assert {:ok, drawn2} = Pages.draw(room_id, give: give)
      assert drawn2.give == give

      # Give is now exhausted
      assert {:error, :pool_exhausted} = Pages.draw(room_id, give: give)
    end
  end

  describe "first/1 and next/2" do
    test "draws from unplayed pool when pages exist" do
      room_id = Ecto.UUID.generate()
      {:ok, page} = Pages.insert_page(@valid_page)

      drawn = Pages.first(room_id)
      assert drawn.id == page.id

      # With no more pages in pool, next returns {:error, :pool_exhausted}
      assert {:error, :pool_exhausted} = Pages.next(drawn.id, room_id)
    end

    test "falls back to hand-written pool when authored pool is empty" do
      room_id = Ecto.UUID.generate()
      first = Pages.first(room_id)
      assert first.id != nil
      assert first.anchors != nil

      assert {:ok, next} = Pages.next(first.id, room_id)
      assert next.id != nil
      assert next.id != first.id
    end
  end

  describe "provisional_reading at two Bridges" do
    test "reads meld for bait and deep meld for deep bridges" do
      assert Pages.provisional_reading(@valid_page, ~w(barbecue barbecue)) == :meld
      assert Pages.provisional_reading(@valid_page, ~w(lawnmower lawnmower)) == :deep_meld
      assert Pages.provisional_reading(@valid_page, ~w(chores chores)) == :deep_meld
      assert Pages.provisional_reading(@valid_page, ~w(family family)) == :meld
    end

    test "reads close when both are in likely_bridges" do
      assert Pages.provisional_reading(@valid_page, ~w(lawnmower family)) == :close
      assert Pages.provisional_reading(@valid_page, ~w(barbecue chores)) == :close
    end

    test "reads adjacent when one is in likely_bridges" do
      assert Pages.provisional_reading(@valid_page, ~w(lawnmower airplane)) == :adjacent
      assert Pages.provisional_reading(@valid_page, ~w(spaceship family)) == :adjacent
    end

    test "reads miss when neither is in likely_bridges" do
      assert Pages.provisional_reading(@valid_page, ~w(spaceship airplane)) == :miss
    end
  end

  describe "provisional_reading at three and more" do
    test "every Bridge the same word reads as a Meld, deep if it was planted deep" do
      assert Pages.provisional_reading(@valid_page, ~w(barbecue barbecue barbecue)) == :meld

      assert Pages.provisional_reading(@valid_page, ~w(lawnmower lawnmower lawnmower)) ==
               :deep_meld
    end

    test "every Bridge among the likely ones reads as close" do
      assert Pages.provisional_reading(@valid_page, ~w(barbecue lawnmower chores family)) ==
               :close
    end

    test "one stray among likely Bridges reads as adjacent rather than a miss" do
      assert Pages.provisional_reading(@valid_page, ~w(barbecue lawnmower spaceship)) == :adjacent
    end

    test "no Bridge among the likely ones is a miss" do
      assert Pages.provisional_reading(@valid_page, ~w(spaceship airplane submarine)) == :miss
    end
  end
end
