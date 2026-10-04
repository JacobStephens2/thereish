defmodule Thereish.OverruleTest do
  @moduledoc """
  A table's joint overrule of one Attempt's grade, through its own interface:
  no Room and no Repo. The Game's overrule tests are the integration check.
  """
  use ExUnit.Case, async: true

  alias Thereish.Ladder
  alias Thereish.Overrule

  @graded %{
    graded?: true,
    closeness: 41,
    reasoning: "Too far apart.",
    quip: "Not quite.",
    furthest: ["beacon", "cairn"],
    meta: %{}
  }

  @attempt %{number: 2, bookends: ["lantern", "harbour"], bridges: ["beacon", "cairn"]}

  test "a proposal defaults to the floor of the meld band, and its proposer agrees" do
    proposal = Overrule.propose("mara")

    assert proposal.proposer_id == "mara"
    assert proposal.closeness == Ladder.meld_threshold()
    assert Overrule.unanimous?(proposal, ["mara"])
  end

  test "a proposal by the only Seat rules at once" do
    assert Overrule.unanimous?(Overrule.propose("mara", 90), ["mara"])
  end

  test "one Seat still to agree leaves it pending" do
    proposal = Overrule.propose("mara", 90)

    refute Overrule.unanimous?(proposal, ["mara", "jacob"])
    assert Overrule.unanimous?(Overrule.agree(proposal, "jacob"), ["mara", "jacob"])
  end

  test "a Seat that wrote no Bridge but plays the Page still counts toward unanimity" do
    # Unanimity is over the Seats playing the Page, whoever wrote.
    proposal = "mara" |> Overrule.propose(90) |> Overrule.agree("jacob")

    refute Overrule.unanimous?(proposal, ["mara", "jacob", "quiet"])
    assert Overrule.unanimous?(Overrule.agree(proposal, "quiet"), ["mara", "jacob", "quiet"])
  end

  test "the ruled Verdict is the table's, and keeps the Assayer's original grade" do
    {verdict, _ruling} = Overrule.rule(Overrule.propose("mara", 95), @graded, @attempt)

    assert verdict.graded?
    assert verdict.overruled?
    assert verdict.closeness == 95
    assert verdict.reasoning == "Overruled jointly across all Seats. Recorded as precedent."
    assert verdict.quip == "House law."
    assert verdict.original_closeness == 41
    assert verdict.original_reasoning == "Too far apart."
    assert verdict.original_quip == "Not quite."
    assert verdict.furthest == @graded.furthest
    assert Overrule.overruled?(verdict)
    refute Overrule.overruled?(@graded)
    refute Overrule.overruled?(nil)
  end

  test "the ruling carries what the machine said beside what the table said" do
    {_verdict, ruling} = Overrule.rule(Overrule.propose("mara", 95), @graded, @attempt)

    assert ruling == %{
             attempt_number: 2,
             proposer_seat_id: "mara",
             bookends: ["lantern", "harbour"],
             bridges: ["beacon", "cairn"],
             machine_closeness: 41,
             machine_reasoning: "Too far apart.",
             machine_quip: "Not quite.",
             couple_closeness: 95,
             couple_reasoning: "Overruled jointly across all Seats. Recorded as precedent.",
             couple_quip: "House law."
           }
  end

  test "an ungraded Verdict can be overruled into a number" do
    ungraded = %{
      graded?: false,
      closeness: nil,
      reasoning: nil,
      quip: nil,
      furthest: nil,
      meta: %{}
    }

    {verdict, ruling} = Overrule.rule(Overrule.propose("mara"), ungraded, @attempt)

    assert verdict.graded?
    assert verdict.closeness == Ladder.meld_threshold()
    assert verdict.original_closeness == nil
    assert ruling.machine_closeness == nil
    assert ruling.couple_closeness == Ladder.meld_threshold()
  end

  describe "a pending proposal, as one viewer sees it" do
    test "says who proposed, at what Closeness, and who agreed" do
      proposal = "mara" |> Overrule.propose(90) |> Overrule.agree("jacob")

      view = Overrule.view(proposal, "jacob")

      assert view.pending?
      assert view.proposer_id == "mara"
      assert view.closeness == 90
      assert Enum.sort(view.agreed_seat_ids) == ["jacob", "mara"]
      refute view.you_proposed?
      assert view.you_agreed?
    end

    test "tells the proposer they proposed, and a viewer with no Seat nothing of theirs" do
      proposal = Overrule.propose("mara", 90)

      assert Overrule.view(proposal, "mara").you_proposed?
      refute Overrule.view(proposal, nil).you_agreed?
      assert Overrule.view(nil, "mara") == nil
    end
  end
end
