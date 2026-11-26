defmodule Thereish.Steward.PrecedentTest do
  use Thereish.DataCase, async: false

  alias Thereish.Steward.Precedent

  @model "gemini-3.8-flash"
  @version "assay-4"
  @request %{
    bookends: ["lantern", "café tide", "wharf", "dusk"],
    bridges: ["beacon", "cairn", "lamp", "seagull"]
  }
  @verdict %{
    closeness: 80,
    reasoning: "Both words name a marker left to be found.",
    quip: "One built it, the other lit it.",
    furthest: ["seagull", "Beacon"],
    meta: %{
      model: @model,
      prompt_version: @version,
      cost_usd: 0.0018,
      forward: 95,
      reverse: 65,
      reasoning_reverse: "Both guide the lost."
    }
  }
  @ruling %{
    closeness: 90,
    reasoning: "We all meant the same shore.",
    quip: "House law."
  }

  test "normalizes Bridge text with NFC, lowercase, and collapsed whitespace" do
    assert Precedent.normalize("  CAFe\u0301 \t\n TIDE ") == "café tide"
  end

  test "a cold resolution stores the Verdict and later resolutions inherit all its fields" do
    expected = put_in(@verdict, [:meta, :spread], 30)

    assert {:ok, :cold, first} = resolve(@request, fn -> {:ok, @verdict} end)
    assert first == put_in(expected, [:meta, :precedent_hit], false)

    assert {:ok, :hit, ^expected} = resolve(@request)
  end

  test "reordered Bookends and Bridges, spelling variants, and prior Quips share a Precedent" do
    assert {:ok, :cold, _} = resolve(@request, fn -> {:ok, @verdict} end)

    assert {:ok, :hit, verdict} = resolve(equivalent_request())
    assert verdict.furthest == ["seagull", "Beacon"]
    assert verdict.closeness == 80
  end

  test "resolves a row written with the established key and no furthest Bridges" do
    Repo.insert!(%Precedent{
      key: "729d98af47ae239be97f0655a60fc04533e58ebfa1f6768347a2c0def7947d89",
      model: @model,
      prompt_version: @version,
      bookends: ["café tide", "dusk", "lantern", "wharf"],
      bridges: ["beacon", "cairn", "lamp", "seagull"],
      closeness: 74,
      reasoning: "A Verdict saved before resolution.",
      quip: "The old Quip."
    })

    assert {:ok, :hit, verdict} = resolve(equivalent_request())
    assert verdict.closeness == 74
    assert verdict.quip == "The old Quip."
    assert verdict.furthest == nil
    assert verdict.meta.spread == nil
  end

  test "switching model or prompt version requires a fresh grade" do
    assert {:ok, :cold, _} = resolve(@request, fn -> {:ok, @verdict} end)
    grade = fn -> {:error, :grading_called} end

    assert {:error, :grading_called} =
             Precedent.resolve("claude-fable", @version, @request, grade)

    assert {:error, :grading_called} = Precedent.resolve(@model, "assay-5", @request, grade)
  end

  test "a joint Overrule replaces the grade and keeps the stored readings and furthest Bridges" do
    assert {:ok, :cold, _} = resolve(@request, fn -> {:ok, @verdict} end)

    request = equivalent_request()

    assert {:ok, _} =
             Precedent.overrule(@model, @version, request.bookends, request.bridges, @ruling)

    assert {:ok, :hit, verdict} = resolve(@request)
    assert Map.take(verdict, Map.keys(@ruling)) == @ruling
    assert verdict.furthest == ["seagull", "Beacon"]

    assert %{forward: 95, reverse: 65, reasoning_reverse: "Both guide the lost.", spread: 30} =
             verdict.meta
  end

  test "reports a rejected first write and can resolve a valid Verdict on the next Assay" do
    invalid = %{@verdict | quip: nil}

    assert {:error, %Ecto.Changeset{} = error} = resolve(@request, fn -> {:ok, invalid} end)
    assert errors_on(error).quip == ["can't be blank"]

    assert {:ok, :cold, %{quip: "One built it, the other lit it."}} =
             resolve(@request, fn -> {:ok, @verdict} end)
  end

  test "failed grading leaves a Precedent written during the Assay intact" do
    assert {:error, :grading_failed} =
             resolve(@request, fn ->
               assert {:ok, _} =
                        Precedent.overrule(
                          @model,
                          @version,
                          @request.bookends,
                          @request.bridges,
                          @ruling
                        )

               {:error, :grading_failed}
             end)

    assert {:ok, :hit, verdict} = resolve(@request)
    assert Map.take(verdict, Map.keys(@ruling)) == @ruling
  end

  defp equivalent_request do
    %{
      bookends: ["  DUSK", "WHARF ", " CAFE\u0301 \t TIDE  ", "Lantern"],
      bridges: [" LAMP ", "Seagull", %{name: "Mara", bridge: "BEACON"}, " CAIRN "],
      prior_quips: ["A Quip that has already been used."]
    }
  end

  defp resolve(request, grade \\ fn -> flunk("expected the stored Precedent") end) do
    Precedent.resolve(@model, @version, request, grade)
  end
end
