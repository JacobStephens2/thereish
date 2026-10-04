defmodule Thereish.Chronicle.OpinionTest do
  @moduledoc """
  The Opinion rules, read from plain maps and structs. No database and no Room:
  inserting a row is the Chronicle's test, and refusing a tap before the reveal
  is the Game's.
  """
  use ExUnit.Case, async: true

  alias Thereish.Chronicle.FairnessTap
  alias Thereish.Chronicle.Opinion
  alias Thereish.Ladder

  @room_id "room"
  @melissa "melissa"
  @jacob "jacob"
  @admin "admin"

  defp graded(attrs \\ []) do
    Enum.into(attrs, %{
      page_id: "page",
      attempt_number: 1,
      bookends: ["lantern", "harbour"],
      bridges: ["beacon", "cairn"],
      participant_ids: [@melissa, @jacob],
      closeness: 62,
      machine_closeness: nil,
      band: nil,
      model: "test",
      prompt_version: "v1"
    })
  end

  defp row(attrs) do
    struct!(
      %FairnessTap{
        id: "tap",
        room_id: @room_id,
        page_id: "page",
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["beacon", "cairn"],
        closeness: 62,
        band: "close",
        label: "fair",
        source: "participant",
        seat_id: @melissa,
        inserted_at: ~U[2026-10-01 20:00:00.000000Z]
      },
      attrs
    )
  end

  describe "label/1" do
    test "reads the atoms and the strings, with an underscore or a space, in any case" do
      for input <- [:fair, "fair", " Fair ", "FAIR"],
          do: assert(Opinion.label(input) == {:ok, "fair"})

      for input <- [:too_kind, "too_kind", "too kind", "Too Kind", "  TOO_KIND\n"],
          do: assert(Opinion.label(input) == {:ok, "too_kind"})

      for input <- [:too_harsh, "too_harsh", "too harsh", "Too harsh"],
          do: assert(Opinion.label(input) == {:ok, "too_harsh"})
    end

    test "refuses anything else" do
      for input <- ["bogus", :bogus, "", "tookind", "too-kind", nil, 3],
          do: assert(Opinion.label(input) == {:error, :invalid_label})
    end
  end

  test "human/1 words a label" do
    assert Opinion.human("too_harsh") == "too harsh"
    assert Opinion.human(:fair) == "fair"
    assert Opinion.human("too_kind") == "too kind"
  end

  test "labels/0 is the vocabulary, in the order of the scale" do
    assert Opinion.labels() == ["too_harsh", "fair", "too_kind"]
  end

  describe "new/3" do
    test "builds the participant's row from a graded Attempt" do
      assert {:ok, attrs} = Opinion.new(graded(), {:participant, @melissa}, :too_harsh)

      assert attrs == %{
               page_id: "page",
               attempt_number: 1,
               bookends: ["lantern", "harbour"],
               bridges: ["beacon", "cairn"],
               closeness: 62,
               band: to_string(Ladder.band(62)),
               model: "test",
               prompt_version: "v1",
               label: "too_harsh",
               source: "participant",
               seat_id: @melissa,
               admin_id: nil
             }
    end

    test "judges the grade the Assayer gave before an overrule, and reads its band from it" do
      overruled = graded(closeness: 85, machine_closeness: 30, band: "meld")

      assert {:ok, attrs} = Opinion.new(overruled, {:participant, @jacob}, "fair")
      assert attrs.closeness == 30
      assert attrs.band == to_string(Ladder.band(30))
    end

    test "keeps the stored band only when there is no grade" do
      assert {:ok, attrs} =
               Opinion.new(graded(closeness: nil, band: "near"), {:participant, @melissa}, "fair")

      assert attrs.closeness == nil
      assert attrs.band == "near"
    end

    test "refuses an Attempt with neither a grade nor a band" do
      assert Opinion.new(graded(closeness: nil), {:participant, @melissa}, "fair") ==
               {:error, :not_assayed}
    end

    test "accepts a Seat that wrote a Bridge and refuses one that wrote none" do
      assert {:ok, _} = Opinion.new(graded(), {:participant, @jacob}, "fair")

      assert Opinion.new(graded(), {:participant, "ida"}, "fair") ==
               {:error, :not_a_participant}
    end

    test "lets the admin review any Attempt, attributed separately" do
      assert {:ok, attrs} = Opinion.new(graded(participant_ids: []), {:admin, @admin}, "too kind")
      assert %{source: "admin", admin_id: @admin, seat_id: nil, label: "too_kind"} = attrs
    end

    test "refuses an invalid label" do
      assert Opinion.new(graded(), {:participant, @melissa}, "bogus") == {:error, :invalid_label}
    end
  end

  test "may_give?/2 lets participants and the admin give an opinion, and nobody else" do
    assert Opinion.may_give?(graded(), {:participant, @melissa})
    refute Opinion.may_give?(graded(), {:participant, "ida"})
    assert Opinion.may_give?(graded(participant_ids: []), {:admin, @admin})
    refute Opinion.may_give?(graded(), nil)
  end

  describe "current/1" do
    test "a Seat's retrospective opinion replaces its tap during play" do
      tap = row(id: "tap", page_id: nil, label: "fair")

      retrospective =
        row(id: "later", label: "too_harsh", inserted_at: ~U[2026-10-02 09:00:00.000000Z])

      assert [%{id: "later"}] = Opinion.current([tap, retrospective])
    end

    test "keeps each reviewer's latest, oldest first" do
      rows = [
        row(id: "m1", seat_id: @melissa, label: "fair"),
        row(id: "j1", seat_id: @jacob, label: "too_kind"),
        row(id: "a1", source: "admin", seat_id: nil, admin_id: @admin, label: "fair"),
        row(id: "m2", seat_id: @melissa, label: "too_harsh"),
        row(id: "m1-attempt-2", attempt_number: 2, seat_id: @melissa)
      ]

      assert rows |> Opinion.current() |> Enum.map(& &1.id) == ["j1", "a1", "m2", "m1-attempt-2"]
    end

    test "treats different Bookends or Rooms as different Attempts" do
      rows = [
        row(id: "here"),
        row(id: "other bookends", bookends: ["salt", "sea"]),
        row(id: "other room", room_id: "elsewhere")
      ]

      assert length(Opinion.current(rows)) == 3
    end
  end

  test "of/2 is one reviewer's current label" do
    rows = [
      row(id: "m1", seat_id: @melissa, label: "fair"),
      row(id: "m2", seat_id: @melissa, label: "too_kind"),
      row(id: "a1", source: "admin", seat_id: nil, admin_id: @admin, label: "too_harsh")
    ]

    assert Opinion.of(rows, {:participant, @melissa}) == "too_kind"
    assert Opinion.of(rows, {:admin, @admin}) == "too_harsh"
    assert Opinion.of(rows, {:participant, @jacob}) == nil
  end

  test "calibration/1 holds each participant's current opinion and leaves out the admin's" do
    rows = [
      row(
        id: "m1",
        seat_id: @melissa,
        label: "fair",
        seat: %Thereish.Rooms.Seat{name: "Melissa"}
      ),
      row(id: "a1", source: "admin", seat_id: nil, admin_id: @admin, label: "too_harsh"),
      row(
        id: "m2",
        seat_id: @melissa,
        label: "too_kind",
        seat: %Thereish.Rooms.Seat{name: "Melissa"}
      )
    ]

    assert [entry] = Opinion.calibration(rows)

    assert entry == %{
             id: "m2",
             room_id: @room_id,
             page_id: "page",
             attempt_number: 1,
             seat_id: @melissa,
             seat_name: "Melissa",
             bookends: ["lantern", "harbour"],
             bridges: ["beacon", "cairn"],
             grade: 62,
             closeness: 62,
             band: "close",
             model: nil,
             prompt_version: nil,
             label: "too_kind",
             inserted_at: ~U[2026-10-01 20:00:00.000000Z]
           }
  end

  test "tally/1 counts every label among current participant opinions" do
    rows = [
      row(id: "m1", seat_id: @melissa, label: "fair"),
      row(id: "m2", seat_id: @melissa, label: "too_harsh"),
      row(id: "j1", seat_id: @jacob, label: "too_harsh"),
      row(id: "a1", source: "admin", seat_id: nil, admin_id: @admin, label: "fair")
    ]

    assert Opinion.tally(rows) == %{"too_harsh" => 2, "fair" => 0, "too_kind" => 0}
    assert Opinion.tally([]) == %{"too_harsh" => 0, "fair" => 0, "too_kind" => 0}
  end
end
