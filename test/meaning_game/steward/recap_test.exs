defmodule MeaningGame.Steward.RecapTest do
  @moduledoc """
  What the Scribe is asked, and what the game refuses to be told.

  The deterministic check here is the half of the gate a schema cannot express
  and Vale should not have to: the recap has to be about the words these players
  actually wrote, and it must not put a number on an evening the Assayer has
  already put a number on (ADR-0006).
  """
  use ExUnit.Case, async: true

  alias MeaningGame.Steward.Recap

  defp page do
    %{
      anchors: ["lantern", "harbour"],
      melded: true,
      attempts: [
        %{
          number: 1,
          anchors: ["lantern", "harbour"],
          bridges: [
            %{seat_name: "Jacob", bridge: "keeper"},
            %{seat_name: "Mara", bridge: "guide"}
          ],
          verdicts: [%{band: "adjacent", reasoning: "Two jobs on the same shore.", closeness: 41}]
        },
        %{
          number: 2,
          anchors: ["keeper", "guide"],
          bridges: [
            %{seat_name: "Jacob", bridge: "watch"},
            %{seat_name: "Mara", bridge: "watch"}
          ],
          verdicts: [%{band: "deep_meld", reasoning: "The same word twice.", closeness: 100}]
        }
      ]
    }
  end

  describe "the question" do
    test "names every Bridge the players wrote, in the order they sat" do
      %{user: user} = Recap.prompt(page(), "Nothing yet; this is the first Page.")

      assert user =~ "keeper"
      assert user =~ "guide"
      assert user =~ "watch"
      assert user =~ "Jacob"
      assert user =~ "Mara"
    end

    test "carries the Chronicle so the Scribe has something to reach back to" do
      %{user: user} = Recap.prompt(page(), "Page 1 (candy · cane) — Melded on attempt 2")

      assert user =~ "candy"
    end

    test "asks for the band rather than the number" do
      %{user: user} = Recap.prompt(page(), "Nothing yet; this is the first Page.")

      assert user =~ "deep_meld" or user =~ "deep meld"
      refute user =~ "100"
    end

    test "the version rides on the question" do
      assert is_binary(Recap.version())
    end
  end

  describe "what counts as an answer" do
    test "a recap that names a Bridge the players wrote" do
      assert :ok =
               Recap.check(
                 %{
                   "recap" =>
                     ~s(Jacob wrote "keeper" and Mara wrote "guide", and they met at watch.),
                   "callback" => ""
                 },
                 page()
               )
    end

    test "a recap about nobody's words is refused" do
      assert {:error, why} =
               Recap.check(
                 %{"recap" => "A fine evening was had by all at the table.", "callback" => ""},
                 page()
               )

      assert why =~ "words the players wrote"
    end

    test "a recap that puts a number on the evening is refused" do
      assert {:error, why} =
               Recap.check(
                 %{"recap" => ~s(They landed "watch" together, a clean 100.), "callback" => ""},
                 page()
               )

      assert why =~ "number"
    end

    test "a blank recap is not a recap" do
      assert {:error, why} = Recap.check(%{"recap" => "   ", "callback" => ""}, page())
      assert why =~ "blank"
    end

    test "a callback is allowed to be empty, because the first evening has nothing behind it" do
      assert :ok =
               Recap.check(
                 %{
                   "recap" => ~s(Both of them wrote "watch" on the second try.),
                   "callback" => ""
                 },
                 page()
               )
    end

    test "a callback carrying a number is refused too" do
      assert {:error, why} =
               Recap.check(
                 %{
                   "recap" => ~s(Both of them wrote "watch".),
                   "callback" => "Like the candy cane, which they melded at 92."
                 },
                 page()
               )

      assert why =~ "number"
    end

    test "an answer of an unexpected shape is a rejection rather than a crash" do
      assert {:error, _why} = Recap.check(%{"recap" => 12}, page())
    end
  end

  describe "the recap the Chronicle stores" do
    test "is the prose and the callback, trimmed" do
      assert %{recap: "Both of them wrote watch.", callback: "Like the candy cane."} =
               Recap.recap(%{
                 "recap" => "  Both of them wrote watch.  ",
                 "callback" => "  Like the candy cane.  "
               })
    end

    test "an empty callback is nothing rather than an empty string" do
      assert %{callback: nil} =
               Recap.recap(%{"recap" => "Both of them wrote watch.", "callback" => "  "})
    end
  end
end
