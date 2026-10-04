defmodule Thereish.EntryFixtures do
  @moduledoc """
  Builds a `Thereish.Chronicle.Entry` the way the Room hands one over, for
  tests that write a closed Page into the Chronicle.

  Every field has a default, and any field can be overridden. Gives, Attempts
  and Verdicts may be given as plain maps or keyword lists; they are built into
  their structs here, so a key the Entry does not declare fails at once rather
  than writing an empty column.
  """

  alias Thereish.Chronicle.Entry

  @doc """
  A closed Page: a one-Attempt Meld on "lantern" and "harbour", opened now.
  """
  def entry(attrs \\ %{}) do
    attrs = Map.new(attrs)

    defaults = %{
      page: %{bookends: ["lantern", "harbour"]},
      closed_because: :meld,
      melded?: true,
      closeness: 80,
      attempts: [%{}],
      opened_at: DateTime.utc_now()
    }

    fields =
      defaults
      |> Map.merge(attrs)
      |> Map.update!(:attempts, fn attempts -> Enum.map(attempts, &attempt/1) end)
      |> Map.update(:gives, [], fn gives -> Enum.map(gives, &give/1) end)

    struct!(Entry, fields)
  end

  @doc "One Give."
  def give(%Entry.Give{} = give), do: give
  def give(attrs), do: struct!(Entry.Give, Map.merge(%{text: ""}, Map.new(attrs)))

  @doc """
  One Attempt: the first, a Meld at 80 on "lantern" and "harbour", with no
  Bridges and no Verdict unless given.
  """
  def attempt(%Entry.Attempt{} = attempt), do: attempt

  def attempt(attrs) do
    defaults = %{
      number: 1,
      bookends: ["lantern", "harbour"],
      closeness: 80,
      melded?: true,
      bridges: [],
      verdicts: []
    }

    fields =
      defaults
      |> Map.merge(Map.new(attrs))
      |> Map.update!(:verdicts, fn verdicts -> Enum.map(verdicts, &verdict/1) end)

    struct!(Entry.Attempt, fields)
  end

  @doc "One Verdict: graded, a Meld at 80, from the fake Assayer."
  def verdict(%Entry.Verdict{} = verdict), do: verdict

  def verdict(attrs) do
    defaults = %{
      seat_ids: [],
      bridges: [],
      graded?: true,
      closeness: 80,
      band: :meld,
      reasoning: "Close enough.",
      quip: nil,
      meta: %{model: "fake", prompt_version: "assay-2", latency_ms: 10, cost_usd: 0.0}
    }

    struct!(Entry.Verdict, Map.merge(defaults, Map.new(attrs)))
  end
end
