defmodule Thereish.Chronicle.DocumentTest do
  @moduledoc """
  A Page's Document has one shape from the Game to every Chronicle reader:
  load reads every spelling the Chronicle has stored, and dump writes only
  today's keys (ticket 233).
  """
  use ExUnit.Case, async: true

  alias Thereish.Chronicle.Document

  describe "load/1" do
    test "reads a string-keyed row as a Page written today stores it" do
      row = %{
        "bookends" => ["lantern", "harbour"],
        "bookend_origins" => [
          %{"word" => "lantern", "seat_id" => "jacob", "seat_name" => "Jacob", "give" => "dock"}
        ],
        "gives" => %{"jacob" => "dock"},
        "meta" => %{"model" => "gemini-3.8-flash"},
        "full_table" => false
      }

      assert Document.load(row) ==
               {:ok,
                %Document{
                  bookends: ["lantern", "harbour"],
                  origins: [
                    %{word: "lantern", seat_id: "jacob", seat_name: "Jacob", give: "dock"}
                  ],
                  gives: %{"jacob" => "dock"},
                  meta: %{"model" => "gemini-3.8-flash"},
                  full_table: false,
                  give: nil,
                  identifier: nil
                }}
    end

    test "reads an atom-keyed map, padding a short origin with nils" do
      map = %{
        bookends: ["lantern", "harbour"],
        bookend_origins: [
          %{word: "lantern", seat_id: "mara", seat_name: "Mara", give: "lighthouse"},
          %{word: "harbour"}
        ],
        gives: %{"mara" => "lighthouse"},
        meta: %{arm: "flash"},
        full_table: true
      }

      assert {:ok, %Document{} = document} = Document.load(map)
      assert document.bookends == ["lantern", "harbour"]
      assert document.gives == %{"mara" => "lighthouse"}
      assert document.meta == %{arm: "flash"}
      assert document.full_table == true

      assert document.origins == [
               %{word: "lantern", seat_id: "mara", seat_name: "Mara", give: "lighthouse"},
               %{word: "harbour", seat_id: nil, seat_name: nil, give: nil}
             ]
    end

    test "reads the legacy bookend_gives as the origins, atom or string keyed" do
      assert {:ok, %Document{origins: [%{word: "lantern", give: "lighthouse", seat_id: nil}]}} =
               Document.load(%{
                 "bookend_gives" => [%{"word" => "lantern", "give" => "lighthouse"}]
               })

      assert {:ok, %Document{origins: [%{word: "lantern", give: "lighthouse"}]}} =
               Document.load(%{bookend_gives: [%{word: "lantern", give: "lighthouse"}]})
    end

    test "reads the legacy single Give and the document's own id" do
      row = %{
        "id" => "author-page",
        "bookends" => ["lantern", "harbour"],
        "give" => "a lighthouse"
      }

      assert {:ok, %Document{give: "a lighthouse", identifier: "author-page"}} =
               Document.load(row)

      assert {:ok, %Document{give: "a lighthouse", identifier: "42"}} =
               Document.load(%{bookends: ["lantern"], give: "a lighthouse", id: 42})
    end

    test "reads a row from before the Full table rule as nil, with empty defaults" do
      assert Document.load(%{"bookends" => ["lantern", "harbour"]}) ==
               {:ok,
                %Document{
                  bookends: ["lantern", "harbour"],
                  origins: [],
                  gives: %{},
                  meta: %{},
                  full_table: nil,
                  give: nil,
                  identifier: nil
                }}
    end

    test "passes a Document through" do
      document = %Document{bookends: ["lantern"]}
      assert Document.load(document) == {:ok, document}
    end

    test "refuses what is not a map" do
      assert Document.load("lantern") == :error
    end
  end

  describe "cast/1" do
    test "reads a stored map as load does" do
      assert Document.cast(%{"bookends" => ["lantern"], "id" => "old"}) ==
               Document.load(%{"bookends" => ["lantern"], "id" => "old"})
    end
  end

  describe "dump/1" do
    test "writes the keys a Page written today stores, and the legacy ones only when set" do
      document = %Document{
        bookends: ["lantern", "harbour"],
        origins: [%{word: "lantern", seat_id: "jacob", seat_name: "Jacob", give: "dock"}],
        gives: %{"jacob" => "dock"},
        meta: %{model: "gemini-3.8-flash"},
        full_table: true
      }

      assert {:ok, dumped} = Document.dump(document)

      assert dumped == %{
               "bookends" => ["lantern", "harbour"],
               "bookend_origins" => [
                 %{word: "lantern", seat_id: "jacob", seat_name: "Jacob", give: "dock"}
               ],
               "gives" => %{"jacob" => "dock"},
               "meta" => %{model: "gemini-3.8-flash"},
               "full_table" => true
             }

      assert {:ok, %{"give" => "a lighthouse", "id" => "old"}} =
               Document.dump(%Document{bookends: [], give: "a lighthouse", identifier: "old"})
    end

    test "round-trips through load" do
      document = %Document{
        bookends: ["lantern", "harbour"],
        origins: [%{word: "lantern", seat_id: "jacob", seat_name: "Jacob", give: "dock"}],
        gives: %{"jacob" => "dock"},
        meta: %{"model" => "gemini-3.8-flash"},
        full_table: false,
        give: "a lighthouse",
        identifier: "old"
      }

      assert {:ok, dumped} = Document.dump(document)
      assert Document.load(dumped) == {:ok, document}
    end

    test "refuses a bare map" do
      assert Document.dump(%{"bookends" => ["lantern", "harbour"]}) == :error
    end
  end
end
