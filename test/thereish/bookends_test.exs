defmodule Thereish.BookendsTest do
  @moduledoc """
  Which Bridges a miss carries forward, whose each one is, and how a set of
  Bookends dresses as chips: one rule, read the same at the table and in the
  Chronicle (ticket 231, ADR-0016).
  """
  use ExUnit.Case, async: true

  alias Thereish.Bookends
  alias Thereish.Mask

  @bridges [
    %{seat_id: "melissa", bridge: "beacon"},
    %{seat_id: "jacob", bridge: "cairn"},
    %{seat_id: "ada", bridge: "lamp"},
    %{seat_id: "sam", bridge: "seagull"}
  ]

  defp graded(furthest), do: %{graded?: true, furthest: furthest}

  defp mask(name), do: %Mask{url: "/media/masks/#{name}.png", meta: %{}}

  defp masks, do: %{"melissa" => mask("melissa"), "jacob" => mask("jacob")}

  describe "carry/3" do
    test "at a Full table, every Bridge carries with its Seat" do
      assert Bookends.carry(@bridges, graded(["beacon", "seagull"]), true) == %{
               carried: [
                 %{word: "beacon", seat_id: "melissa"},
                 %{word: "cairn", seat_id: "jacob"},
                 %{word: "lamp", seat_id: "ada"},
                 %{word: "seagull", seat_id: "sam"}
               ],
               chosen?: true
             }
    end

    test "at a Full table with no Verdict, every Bridge still carries as chosen" do
      assert %{chosen?: true, carried: carried} = Bookends.carry(@bridges, nil, true)
      assert Enum.map(carried, & &1.word) == ["beacon", "cairn", "lamp", "seagull"]
    end

    test "otherwise, the Verdict's furthest pair carries, each with its Seat" do
      assert Bookends.carry(@bridges, graded(["seagull", "beacon"]), false) == %{
               carried: [
                 %{word: "seagull", seat_id: "sam"},
                 %{word: "beacon", seat_id: "melissa"}
               ],
               chosen?: true
             }
    end

    test "a paraphrased pair the Bridges cannot account for falls back to the first two" do
      assert Bookends.carry(@bridges, graded(["beacons", "seagull"]), false) == %{
               carried: [
                 %{word: "beacon", seat_id: "melissa"},
                 %{word: "cairn", seat_id: "jacob"}
               ],
               chosen?: false
             }
    end

    test "an ungraded Verdict falls back to the first two" do
      verdict = %{graded?: false, furthest: ["lamp", "seagull"]}

      assert %{chosen?: false, carried: carried} = Bookends.carry(@bridges, verdict, false)
      assert Enum.map(carried, & &1.word) == ["beacon", "cairn"]
    end

    test "a graded Verdict that names no pair falls back to the first two" do
      assert %{chosen?: false, carried: carried} = Bookends.carry(@bridges, graded(nil), false)
      assert Enum.map(carried, & &1.word) == ["beacon", "cairn"]
    end

    test "no Verdict falls back to the first two" do
      assert %{chosen?: false, carried: carried} = Bookends.carry(@bridges, nil, false)
      assert Enum.map(carried, & &1.seat_id) == ["melissa", "jacob"]
    end

    test "a pair naming one word twice needs two Bridges that wrote it" do
      once = [%{seat_id: "melissa", bridge: "stone"}, %{seat_id: "jacob", bridge: "moss"}]
      twice = [%{seat_id: "melissa", bridge: "stone"}, %{seat_id: "jacob", bridge: "stone"}]

      assert %{chosen?: false} = Bookends.carry(once, graded(["stone", "stone"]), false)

      assert Bookends.carry(twice, graded(["stone", "stone"]), false) == %{
               carried: [
                 %{word: "stone", seat_id: "melissa"},
                 %{word: "stone", seat_id: "jacob"}
               ],
               chosen?: true
             }
    end

    test "a pair written by Bridges with no Seat is still a choice" do
      unseated = [%{seat_id: nil, bridge: "beacon"}, %{seat_id: nil, bridge: "cairn"}]

      assert %{chosen?: true, carried: [%{word: "cairn"}, %{word: "beacon"}]} =
               Bookends.carry(unseated, graded(["cairn", "beacon"]), false)
    end
  end

  describe "claim/2" do
    test "one word written twice is claimed once per Seat, in roster order" do
      bridges = [
        %{seat_id: "melissa", bridge: "stone"},
        %{seat_id: "jacob", bridge: "stone"}
      ]

      assert Bookends.claim(["stone", "stone", "stone"], bridges) == [
               %{word: "stone", seat_id: "melissa"},
               %{word: "stone", seat_id: "jacob"},
               %{word: "stone", seat_id: nil}
             ]
    end

    test "a word no Bridge wrote names no Seat" do
      assert Bookends.claim(["moss", "lamp"], @bridges) == [
               %{word: "moss", seat_id: nil},
               %{word: "lamp", seat_id: "ada"}
             ]
    end
  end

  describe "chips/4" do
    test "a first-Attempt chip names its Give and Seat and never wears a Mask" do
      origins = [
        %{word: "lantern", seat_id: "melissa", seat_name: "Melissa", give: "lighthouse"},
        %{word: "harbour", seat_id: "jacob", seat_name: "Jacob", give: "dock"}
      ]

      assert Bookends.chips(["lantern", "harbour"], origins, 1, masks()) == [
               %{
                 word: "lantern",
                 seat_id: "melissa",
                 seat_name: "Melissa",
                 give: "lighthouse",
                 mask: nil
               },
               %{word: "harbour", seat_id: "jacob", seat_name: "Jacob", give: "dock", mask: nil}
             ]
    end

    test "a later chip names the Seat it carried from and wears that Seat's Mask" do
      origins = [%{word: "cairn", seat_id: "jacob"}, %{word: "lamp", seat_id: "ada"}]

      assert Bookends.chips(["cairn", "lamp"], origins, 2, masks()) == [
               %{word: "cairn", seat_id: "jacob", seat_name: nil, give: nil, mask: mask("jacob")},
               %{word: "lamp", seat_id: "ada", seat_name: nil, give: nil, mask: nil}
             ]
    end

    test "missing origins pad with nils, one chip per word" do
      assert Bookends.chips(["cairn", "lamp"], [%{seat_id: "melissa"}], 2, masks()) == [
               %{
                 word: "cairn",
                 seat_id: "melissa",
                 seat_name: nil,
                 give: nil,
                 mask: mask("melissa")
               },
               %{word: "lamp", seat_id: nil, seat_name: nil, give: nil, mask: nil}
             ]

      assert Bookends.chips(["cairn"], [], 1, %{}) == [
               %{word: "cairn", seat_id: nil, seat_name: nil, give: nil, mask: nil}
             ]
    end
  end
end
